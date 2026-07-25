import '../domain/models.dart';

enum PdfWorkStatus { idle, preparing, scanning, ready, exporting, exported }

class PdfPageSession {
  const PdfPageSession({
    required this.pageNumber,
    required this.widthPoints,
    required this.heightPoints,
    required this.image,
    this.scanned = false,
  });

  final int pageNumber;
  final double widthPoints;
  final double heightPoints;
  final ImageSession image;
  final bool scanned;

  PdfPageSession copyWith({ImageSession? image, bool? scanned}) =>
      PdfPageSession(
        pageNumber: pageNumber,
        widthPoints: widthPoints,
        heightPoints: heightPoints,
        image: image ?? this.image,
        scanned: scanned ?? this.scanned,
      );
}

class PdfSession {
  const PdfSession({
    required this.sourcePath,
    required this.fileName,
    this.pages = const [],
    this.currentPageIndex = 0,
    this.customTerms = const [],
    this.customMatchIds = const {},
    this.status = PdfWorkStatus.idle,
    this.exportPath,
    this.flatteningVerified = false,
  });

  final String sourcePath;
  final String fileName;
  final List<PdfPageSession> pages;
  final int currentPageIndex;
  final List<String> customTerms;
  final Set<String> customMatchIds;
  final PdfWorkStatus status;
  final String? exportPath;
  final bool flatteningVerified;

  int get pageCount => pages.length;
  bool get isEmpty => pages.isEmpty;
  PdfPageSession? get currentPage =>
      currentPageIndex >= 0 && currentPageIndex < pages.length
      ? pages[currentPageIndex]
      : null;
  int get selectedCount => pages.fold(
    0,
    (sum, page) =>
        sum +
        page.image.items.where((item) => item.selected).length +
        page.image.strokes.length,
  );

  PdfSession copyWith({
    List<PdfPageSession>? pages,
    int? currentPageIndex,
    List<String>? customTerms,
    Set<String>? customMatchIds,
    PdfWorkStatus? status,
    String? exportPath,
    bool? flatteningVerified,
    bool clearExport = false,
  }) => PdfSession(
    sourcePath: sourcePath,
    fileName: fileName,
    pages: pages ?? this.pages,
    currentPageIndex: currentPageIndex ?? this.currentPageIndex,
    customTerms: customTerms ?? this.customTerms,
    customMatchIds: customMatchIds ?? this.customMatchIds,
    status: status ?? this.status,
    exportPath: clearExport ? null : exportPath ?? this.exportPath,
    flatteningVerified: flatteningVerified ?? this.flatteningVerified,
  );
}

class PdfInspection {
  const PdfInspection({required this.pageCount, required this.encrypted});

  final int pageCount;
  final bool encrypted;
}

class PdfScanProgress {
  const PdfScanProgress({
    required this.page,
    required this.totalPages,
    required this.stage,
  });

  final int page;
  final int totalPages;
  final ScanStage stage;
}
