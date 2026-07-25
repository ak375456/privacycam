import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../domain/models.dart';
import '../domain/pdf_models.dart';
import '../services/pdf_service.dart';
import 'providers.dart';

const pdfFreePageLimit = 2;

final pdfServiceProvider = Provider((_) => PdfService());
final secureStorageProvider = Provider((_) => const FlutterSecureStorage());

class PdfSessionController extends Notifier<PdfSession?> {
  static const _rememberedTermsKey = 'privacyCamPdfPrivateTermsV1';
  final _undo = <int, List<ImageSession>>{};
  final _redo = <int, List<ImageSession>>{};

  @override
  PdfSession? build() => null;

  Future<void> importAndScan(
    String path, {
    required void Function(PdfScanProgress progress) onProgress,
    bool Function()? shouldCancel,
  }) async {
    await clear();
    final fileName = path.split(Platform.pathSeparator).last;
    final rememberedTerms = await _readRememberedTerms();
    state = PdfSession(
      sourcePath: path,
      fileName: fileName,
      customTerms: rememberedTerms,
      status: PdfWorkStatus.preparing,
    );
    final pages = await ref
        .read(pdfServiceProvider)
        .renderPages(
          path,
          shouldCancel: shouldCancel,
          onPage: (page, total) => onProgress(
            PdfScanProgress(
              page: page,
              totalPages: total,
              stage: ScanStage.preparing,
            ),
          ),
        );
    if (shouldCancel?.call() ?? false) return;
    state = state!.copyWith(pages: pages, status: PdfWorkStatus.scanning);
    for (var pageIndex = 0; pageIndex < pages.length; pageIndex++) {
      if (shouldCancel?.call() ?? false) return;
      await _scanPage(pageIndex, onProgress);
    }
    state = state!.copyWith(status: PdfWorkStatus.ready);
  }

  Future<void> _scanPage(
    int index,
    void Function(PdfScanProgress progress) onProgress,
  ) async {
    final current = state!;
    final page = current.pages[index];
    final image = page.image;
    final size = Size(image.width.toDouble(), image.height.toDouble());
    final detector = ref.read(detectionProvider);
    void stage(ScanStage value) => onProgress(
      PdfScanProgress(
        page: index + 1,
        totalPages: current.pages.length,
        stage: value,
      ),
    );

    stage(ScanStage.faces);
    final faces = await detector.detectFaces(image.sourcePath, size);
    stage(ScanStage.people);
    final people = await detector.detectPeople(image.sourcePath, size);
    stage(ScanStage.text);
    final text = await detector.detectText(image.sourcePath, size);
    stage(ScanStage.sensitiveInfo);
    await Future<void>.delayed(const Duration(milliseconds: 40));
    stage(ScanStage.numberPlates);
    final plates = await detector.detectNumberPlates(image.sourcePath, size);
    stage(ScanStage.codes);
    final codes = await detector.detectCodes(image.sourcePath, size);
    final settings = ref.read(settingsProvider);
    final customTerms = state!.customTerms;
    final all = [...people, ...faces, ...text, ...plates, ...codes];
    final customIds = <String>{...state!.customMatchIds};
    final styled = <RedactionItem>[];
    for (final item in all) {
      final customMatch = _matchesCustomTerm(item.label, customTerms);
      if (customMatch) customIds.add(item.id);
      styled.add(
        item.copyWith(
          selected:
              customMatch ||
              settings.autoHideCategories.contains(item.category),
          style: switch (item.category) {
            RedactionCategory.face => settings.faceStyle,
            RedactionCategory.person => settings.peopleStyle,
            RedactionCategory.qrCode => RedactionStyle.pixelate,
            RedactionCategory.numberPlate => RedactionStyle.pixelate,
            RedactionCategory.cardSecurityCode => RedactionStyle.blackout,
            RedactionCategory.otherText => item.style,
            _ => settings.sensitiveStyle,
          },
        ),
      );
    }
    final updatedPage = page.copyWith(
      image: image.copyWith(items: styled),
      scanned: true,
    );
    state = state!.copyWith(
      pages: [
        for (var i = 0; i < state!.pages.length; i++)
          i == index ? updatedPage : state!.pages[i],
      ],
      currentPageIndex: index,
      customMatchIds: customIds,
    );
    stage(ScanStage.complete);
  }

  bool _matchesCustomTerm(String? value, List<String> terms) {
    if (value == null || value.trim().isEmpty || terms.isEmpty) return false;
    final normalized = _normalize(value);
    return terms.any((term) => normalized.contains(_normalize(term)));
  }

  String _normalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9@.+]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  Future<List<String>> _readRememberedTerms() async {
    try {
      final raw = await ref
          .read(secureStorageProvider)
          .read(key: _rememberedTermsKey);
      if (raw == null) return const [];
      return [
        for (final value in jsonDecode(raw) as List)
          if ((value as String).trim().length >= 2) value.trim(),
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<void> setCustomTerms(
    List<String> values, {
    required bool remember,
  }) async {
    final s = state;
    if (s == null) return;
    final terms = values
        .map((value) => value.trim())
        .where((value) => value.length >= 2)
        .toSet()
        .take(20)
        .toList();
    if (remember) {
      await ref
          .read(secureStorageProvider)
          .write(key: _rememberedTermsKey, value: jsonEncode(terms));
    } else {
      await ref.read(secureStorageProvider).delete(key: _rememberedTermsKey);
    }
    final matches = <String>{};
    final autoHide = ref.read(settingsProvider).autoHideCategories;
    final pages = [
      for (final page in s.pages)
        page.copyWith(
          image: page.image.copyWith(
            items: [
              for (final item in page.image.items)
                if (_matchesCustomTerm(item.label, terms))
                  _customSelected(item, matches)
                else if (s.customMatchIds.contains(item.id))
                  item.copyWith(selected: autoHide.contains(item.category))
                else
                  item,
            ],
            clearPreview: true,
            clearExport: true,
          ),
        ),
    ];
    state = s.copyWith(
      pages: pages,
      customTerms: terms,
      customMatchIds: matches,
      status: PdfWorkStatus.ready,
      clearExport: true,
      flatteningVerified: false,
    );
  }

  RedactionItem _customSelected(RedactionItem item, Set<String> matches) {
    matches.add(item.id);
    return item.copyWith(selected: true);
  }

  void setCurrentPage(int index) {
    final s = state;
    if (s == null || index < 0 || index >= s.pages.length) return;
    state = s.copyWith(currentPageIndex: index);
  }

  void _commitImage(ImageSession next) {
    final s = state;
    if (s == null || s.currentPage == null) return;
    final index = s.currentPageIndex;
    (_undo[index] ??= []).add(s.currentPage!.image);
    _redo[index] = [];
    final clean = next.copyWith(clearPreview: true, clearExport: true);
    state = s.copyWith(
      pages: [
        for (var i = 0; i < s.pages.length; i++)
          i == index ? s.pages[i].copyWith(image: clean) : s.pages[i],
      ],
      status: PdfWorkStatus.ready,
      clearExport: true,
      flatteningVerified: false,
    );
  }

  void toggle(String id) {
    final image = state!.currentPage!.image;
    _commitImage(
      image.copyWith(
        items: [
          for (final item in image.items)
            item.id == id ? item.copyWith(selected: !item.selected) : item,
        ],
      ),
    );
  }

  void selectAll() {
    final image = state!.currentPage!.image;
    _commitImage(
      image.copyWith(
        items: [for (final item in image.items) item.copyWith(selected: true)],
      ),
    );
  }

  void setCategorySelected(RedactionCategory category, bool selected) {
    final image = state!.currentPage!.image;
    _commitImage(
      image.copyWith(
        items: [
          for (final item in image.items)
            item.category == category
                ? item.copyWith(selected: selected)
                : item,
        ],
      ),
    );
  }

  void setAllStyle(RedactionStyle style) {
    final image = state!.currentPage!.image;
    _commitImage(
      image.copyWith(
        items: [
          for (final item in image.items)
            item.selected ? item.copyWith(style: style) : item,
        ],
        strokes: [
          for (final stroke in image.strokes)
            BrushStroke(
              id: stroke.id,
              points: stroke.points,
              size: stroke.size,
              style: style,
            ),
        ],
      ),
    );
  }

  void setDocumentStyle(RedactionStyle style) {
    final s = state;
    if (s == null) return;
    state = s.copyWith(
      pages: [
        for (final page in s.pages)
          page.copyWith(
            image: page.image.copyWith(
              items: [
                for (final item in page.image.items)
                  item.selected ? item.copyWith(style: style) : item,
              ],
              strokes: [
                for (final stroke in page.image.strokes)
                  BrushStroke(
                    id: stroke.id,
                    points: stroke.points,
                    size: stroke.size,
                    style: style,
                  ),
              ],
              clearPreview: true,
              clearExport: true,
            ),
          ),
      ],
      status: PdfWorkStatus.ready,
      clearExport: true,
      flatteningVerified: false,
    );
  }

  void updateBounds(String id, Rect bounds) {
    final image = state!.currentPage!.image;
    _commitImage(
      image.copyWith(
        items: [
          for (final item in image.items)
            item.id == id ? item.copyWith(bounds: bounds) : item,
        ],
      ),
    );
  }

  String addRectangle(Rect bounds, RedactionStyle style) {
    final image = state!.currentPage!.image;
    final id = 'pdf_manual_${DateTime.now().microsecondsSinceEpoch}';
    _commitImage(
      image.copyWith(
        items: [
          ...image.items,
          RedactionItem(
            id: id,
            category: RedactionCategory.manual,
            bounds: bounds,
            selected: true,
            style: style,
            source: RedactionSource.manual,
          ),
        ],
      ),
    );
    return id;
  }

  void deleteItem(String id) {
    final image = state!.currentPage!.image;
    _commitImage(
      image.copyWith(
        items: image.items.where((item) => item.id != id).toList(),
      ),
    );
  }

  void addStroke(BrushStroke stroke) {
    final image = state!.currentPage!.image;
    _commitImage(image.copyWith(strokes: [...image.strokes, stroke]));
  }

  bool eraseAt(Offset point, {double radius = 18}) {
    final image = state!.currentPage!.image;
    final nearbyStrokes =
        image.strokes
            .where(
              (stroke) => _distance(stroke, point) <= radius + stroke.size / 2,
            )
            .toList()
          ..sort((a, b) => _distance(a, point).compareTo(_distance(b, point)));

    if (nearbyStrokes.isNotEmpty) {
      final erasedId = nearbyStrokes.first.id;
      _commitImage(
        image.copyWith(
          strokes: image.strokes
              .where((stroke) => stroke.id != erasedId)
              .toList(),
        ),
      );
      return true;
    }

    final hit = image.items
        .where(
          (item) =>
              item.selected && item.bounds.inflate(radius).contains(point),
        )
        .lastOrNull;
    if (hit == null) return false;

    _commitImage(
      image.copyWith(
        items: [
          for (final item in image.items)
            if (item.id != hit.id)
              item
            else if (item.source == RedactionSource.automatic)
              item.copyWith(selected: false),
        ],
      ),
    );
    return true;
  }

  double _distance(BrushStroke stroke, Offset point) => stroke.points.isEmpty
      ? double.infinity
      : stroke.points
            .map((candidate) => (candidate - point).distance)
            .reduce((a, b) => a < b ? a : b);

  void undo() {
    final s = state;
    if (s == null || s.currentPage == null) return;
    final index = s.currentPageIndex;
    final history = _undo[index];
    if (history == null || history.isEmpty) return;
    (_redo[index] ??= []).add(s.currentPage!.image);
    final previous = history.removeLast();
    state = s.copyWith(
      pages: [
        for (var i = 0; i < s.pages.length; i++)
          i == index ? s.pages[i].copyWith(image: previous) : s.pages[i],
      ],
      clearExport: true,
      flatteningVerified: false,
    );
  }

  void redo() {
    final s = state;
    if (s == null || s.currentPage == null) return;
    final index = s.currentPageIndex;
    final history = _redo[index];
    if (history == null || history.isEmpty) return;
    (_undo[index] ??= []).add(s.currentPage!.image);
    final next = history.removeLast();
    state = s.copyWith(
      pages: [
        for (var i = 0; i < s.pages.length; i++)
          i == index ? s.pages[i].copyWith(image: next) : s.pages[i],
      ],
      clearExport: true,
      flatteningVerified: false,
    );
  }

  Future<void> export({void Function(int page, int total)? onPage}) async {
    final s = state;
    if (s == null) return;
    state = s.copyWith(status: PdfWorkStatus.exporting);
    final settings = ref.read(settingsProvider);
    try {
      state = await ref
          .read(pdfServiceProvider)
          .exportFlattened(
            s,
            ref.read(exportProvider),
            ExportSettings(
              blurStrength: settings.blurStrength,
              pixelSize: settings.pixelSize,
              format: 'jpg',
            ),
            onPage: onPage,
          );
    } catch (_) {
      state = s.copyWith(status: PdfWorkStatus.ready);
      rethrow;
    }
  }

  Future<void> clear() async {
    final old = state;
    state = null;
    _undo.clear();
    _redo.clear();
    if (!ref.read(settingsProvider).keepTemporary) {
      await ref.read(pdfServiceProvider).deleteWorkingFiles(old);
    }
  }
}

final pdfSessionProvider = NotifierProvider<PdfSessionController, PdfSession?>(
  PdfSessionController.new,
);
