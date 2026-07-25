import 'dart:io';
import 'dart:math';

import 'package:file_selector/file_selector.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart' show PdfPageFormat;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart';

import '../domain/models.dart';
import '../domain/pdf_models.dart';
import 'export_service.dart';

class PdfFeatureException implements Exception {
  const PdfFeatureException(this.message);

  final String message;

  @override
  String toString() => message;
}

class PdfService {
  static const _pdfType = XTypeGroup(
    label: 'PDF documents',
    extensions: ['pdf'],
    mimeTypes: ['application/pdf'],
    uniformTypeIdentifiers: ['com.adobe.pdf'],
  );

  Future<String?> pickPdf() async {
    final file = await openFile(acceptedTypeGroups: const [_pdfType]);
    return file?.path;
  }

  Future<PdfInspection> inspect(String path) async {
    PdfDocument? document;
    try {
      document = await PdfDocument.openFile(path);
      return PdfInspection(
        pageCount: document.pages.length,
        encrypted: document.isEncrypted,
      );
    } catch (_) {
      throw const PdfFeatureException(
        'This PDF could not be opened. Password-protected or damaged PDFs are not supported yet.',
      );
    } finally {
      await document?.dispose();
    }
  }

  Future<List<PdfPageSession>> renderPages(
    String path, {
    void Function(int page, int total)? onPage,
    bool Function()? shouldCancel,
  }) async {
    PdfDocument? document;
    final rendered = <PdfPageSession>[];
    try {
      document = await PdfDocument.openFile(path);
      if (document.isEncrypted) {
        throw const PdfFeatureException(
          'Remove the PDF password, then choose it again.',
        );
      }
      if (document.pages.isEmpty) {
        throw const PdfFeatureException('This PDF has no readable pages.');
      }
      final directory = await getTemporaryDirectory();
      final token = DateTime.now().microsecondsSinceEpoch;
      for (var index = 0; index < document.pages.length; index++) {
        if (shouldCancel?.call() ?? false) break;
        onPage?.call(index + 1, document.pages.length);
        final page = await document.pages[index].ensureLoaded();
        final largestPointSide = max(page.width, page.height);
        final scale = (2400 / largestPointSide).clamp(.1, 3.0);
        final width = max(1, (page.width * scale).round());
        final height = max(1, (page.height * scale).round());
        final pdfImage = await page.render(
          fullWidth: width.toDouble(),
          fullHeight: height.toDouble(),
        );
        if (pdfImage == null) {
          throw PdfFeatureException('Page ${index + 1} could not be rendered.');
        }
        try {
          final image = img.Image.fromBytes(
            width: pdfImage.width,
            height: pdfImage.height,
            bytes: pdfImage.pixels.buffer,
            numChannels: 4,
            order: img.ChannelOrder.bgra,
          );
          image.exif.clear();
          image.iccProfile = null;
          image.textData = null;
          image.extraChannels = null;
          final imagePath =
              '${directory.path}/PrivacyCam_pdf_${token}_page_${index + 1}.jpg';
          await File(
            imagePath,
          ).writeAsBytes(img.encodeJpg(image, quality: 94), flush: true);
          rendered.add(
            PdfPageSession(
              pageNumber: index + 1,
              widthPoints: page.width,
              heightPoints: page.height,
              image: ImageSession(
                sourcePath: imagePath,
                width: width,
                height: height,
              ),
            ),
          );
        } finally {
          pdfImage.dispose();
        }
      }
      return rendered;
    } on PdfFeatureException {
      rethrow;
    } catch (_) {
      throw const PdfFeatureException(
        'The PDF pages could not be prepared. Try a smaller or repaired PDF.',
      );
    } finally {
      await document?.dispose();
    }
  }

  Future<PdfSession> exportFlattened(
    PdfSession session,
    ExportService exportService,
    ExportSettings settings, {
    void Function(int page, int total)? onPage,
  }) async {
    if (session.pages.isEmpty) {
      throw const PdfFeatureException('There are no PDF pages to export.');
    }
    final safePages = <PdfPageSession>[];
    final output = pw.Document(compress: true);
    for (var index = 0; index < session.pages.length; index++) {
      onPage?.call(index + 1, session.pages.length);
      final page = session.pages[index];
      final safeImage = await exportService.export(
        page.image,
        ExportSettings(
          blurStrength: settings.blurStrength,
          pixelSize: settings.pixelSize,
          format: 'jpg',
        ),
      );
      final imagePath = safeImage.exportPath;
      if (imagePath == null) {
        throw PdfFeatureException('Page ${index + 1} could not be flattened.');
      }
      final image = pw.MemoryImage(await File(imagePath).readAsBytes());
      output.addPage(
        pw.Page(
          pageFormat: PdfPageFormat(page.widthPoints, page.heightPoints),
          margin: pw.EdgeInsets.zero,
          build: (_) => pw.Image(
            image,
            width: page.widthPoints,
            height: page.heightPoints,
            fit: pw.BoxFit.fill,
          ),
        ),
      );
      safePages.add(page.copyWith(image: safeImage));
    }

    final directory = await getTemporaryDirectory();
    final baseName = session.fileName.toLowerCase().endsWith('.pdf')
        ? session.fileName.substring(0, session.fileName.length - 4)
        : session.fileName;
    final safeBase = baseName.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
    final path =
        '${directory.path}/${safeBase.isEmpty ? 'PrivacyCam' : safeBase}_privacy_safe_${DateTime.now().millisecondsSinceEpoch}.pdf';
    await File(path).writeAsBytes(await output.save(), flush: true);
    await _verifyFlattened(path, session.pages.length);
    return session.copyWith(
      pages: safePages,
      status: PdfWorkStatus.exported,
      exportPath: path,
      flatteningVerified: true,
    );
  }

  Future<void> _verifyFlattened(String path, int expectedPages) async {
    PdfDocument? document;
    try {
      document = await PdfDocument.openFile(path);
      if (document.isEncrypted || document.pages.length != expectedPages) {
        throw const PdfFeatureException(
          'The flattened PDF could not be verified. Export was stopped.',
        );
      }
      for (final page in document.pages) {
        final text = await page.loadText();
        if ((text?.fullText.trim().isNotEmpty ?? false)) {
          throw const PdfFeatureException(
            'A removable text layer remained in the PDF. Export was stopped.',
          );
        }
      }
    } on PdfFeatureException {
      rethrow;
    } catch (_) {
      throw const PdfFeatureException(
        'The flattened PDF could not be verified. Export was stopped.',
      );
    } finally {
      await document?.dispose();
    }
  }

  Future<void> deleteWorkingFiles(PdfSession? session) async {
    if (session == null) return;
    final paths = <String>{
      for (final page in session.pages) page.image.sourcePath,
      for (final page in session.pages)
        if (page.image.previewPath != null) page.image.previewPath!,
      for (final page in session.pages)
        if (page.image.exportPath != null) page.image.exportPath!,
      if (session.exportPath != null) session.exportPath!,
    };
    for (final path in paths) {
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
  }
}
