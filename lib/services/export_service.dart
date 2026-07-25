import 'dart:io';
import 'dart:developer' as developer;
import 'dart:isolate';
import 'dart:math';
import 'dart:ui' show Offset, Rect;

import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import '../domain/models.dart';
import 'image_io_service.dart';

class ExportService {
  Future<ImageSession> preview(
    ImageSession session,
    ExportSettings settings,
  ) async {
    try {
      final directory = await getTemporaryDirectory();
      final path =
          '${directory.path}/PrivacyCam_preview_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final rendered = await Isolate.run(
        () => ExportService()._render(
          session,
          settings,
          path,
          false,
          maximumSide: 1400,
          jpegQuality: 88,
          verifyMetadata: false,
        ),
      );
      if (!rendered) {
        throw const ImageIoException('The preview could not be verified.');
      }
      return session.copyWith(
        previewPath: path,
        clearExport: true,
        metadataRemoved: false,
      );
    } on ImageIoException {
      rethrow;
    } catch (error, stackTrace) {
      developer.log(
        'Privacy preview rendering failed.',
        name: 'PrivacyCam.Export',
        error: error,
        stackTrace: stackTrace,
      );
      throw const ImageIoException(
        'The privacy preview could not be created. Try again or reduce the blur strength.',
      );
    }
  }

  Future<ImageSession> export(
    ImageSession session,
    ExportSettings settings,
  ) async {
    try {
      final png =
          settings.format == 'png' ||
          (settings.format == 'source' &&
              session.sourcePath.toLowerCase().endsWith('.png'));
      final directory = await getTemporaryDirectory();
      final path =
          '${directory.path}/PrivacyCam_safe_${DateTime.now().millisecondsSinceEpoch}.${png ? 'png' : 'jpg'}';
      final verified = await Isolate.run(
        () => ExportService()._render(session, settings, path, png),
      );
      if (!verified) {
        throw const ImageIoException(
          'Metadata removal could not be verified. Export was stopped.',
        );
      }
      return session.copyWith(exportPath: path, metadataRemoved: true);
    } on ImageIoException {
      rethrow;
    } catch (error, stackTrace) {
      developer.log(
        'Full-resolution export rendering failed.',
        name: 'PrivacyCam.Export',
        error: error,
        stackTrace: stackTrace,
      );
      throw const ImageIoException(
        'The privacy-safe copy could not be created. Try again or reduce the blur strength.',
      );
    }
  }

  bool _render(
    ImageSession session,
    ExportSettings settings,
    String outputPath,
    bool png, {
    int? maximumSide,
    int jpegQuality = 95,
    bool verifyMetadata = true,
  }) {
    var decoded = img.decodeImage(File(session.sourcePath).readAsBytesSync());
    if (decoded == null) {
      throw const ImageIoException('The working image could not be read.');
    }

    var items = session.items;
    var strokes = session.strokes;
    var renderScale = 1.0;
    final sourceLargestSide = max(decoded.width, decoded.height);
    if (maximumSide != null && sourceLargestSide > maximumSide) {
      final scale = maximumSide / sourceLargestSide;
      renderScale = scale;
      decoded = img.copyResize(
        decoded,
        width: max(1, (decoded.width * scale).round()),
        height: max(1, (decoded.height * scale).round()),
        interpolation: img.Interpolation.average,
      );
      items = [
        for (final item in items)
          item.copyWith(
            bounds: Rect.fromLTRB(
              item.bounds.left * scale,
              item.bounds.top * scale,
              item.bounds.right * scale,
              item.bounds.bottom * scale,
            ),
          ),
      ];
      strokes = [
        for (final stroke in strokes)
          BrushStroke(
            id: stroke.id,
            points: [for (final point in stroke.points) point * scale],
            size: stroke.size * scale,
            style: stroke.style,
          ),
      ];
    }

    var output = decoded;
    for (final item in items.where((e) => e.selected)) {
      output = _applyRect(output, item, settings, renderScale);
    }
    for (final stroke in strokes) {
      output = _applyStroke(output, stroke, settings, renderScale);
    }
    output.exif.clear();
    output.iccProfile = null;
    output.textData = null;
    output.extraChannels = null;
    final bytes = png
        ? img.encodePng(output)
        : img.encodeJpg(output, quality: jpegQuality);
    File(outputPath).writeAsBytesSync(bytes, flush: true);
    if (!verifyMetadata) return bytes.isNotEmpty;
    final verified = img.decodeImage(File(outputPath).readAsBytesSync());
    return verified != null && verified.exif.isEmpty;
  }

  /// Returns a pixel-identical working image with optional metadata removed.
  img.Image withoutMetadata(img.Image source) {
    final clean = img.Image.from(source, noAnimation: true);
    clean.exif.clear();
    clean.iccProfile = null;
    clean.textData = null;
    clean.extraChannels = null;
    return clean;
  }

  img.Image _applyRect(
    img.Image image,
    RedactionItem item,
    ExportSettings settings,
    double renderScale,
  ) {
    final x = item.bounds.left.floor().clamp(0, image.width - 1);
    final y = item.bounds.top.floor().clamp(0, image.height - 1);
    final w = item.bounds.width.ceil().clamp(1, image.width - x);
    final h = item.bounds.height.ceil().clamp(1, image.height - y);
    if (item.style == RedactionStyle.blackout) {
      img.fillRect(
        image,
        x1: x,
        y1: y,
        x2: x + w - 1,
        y2: y + h - 1,
        color: img.ColorRgba8(0, 0, 0, 255),
      );
      return image;
    }
    var region = img.copyCrop(image, x: x, y: y, width: w, height: h);
    if (item.style == RedactionStyle.blur) {
      if (item.category == RedactionCategory.face) {
        // Remove identifying facial detail on a tiny buffer. This is both
        // stronger and dramatically faster than blurring a full-size face.
        final normalizedStrength = ((settings.blurStrength - 2) / 62).clamp(
          0.0,
          1.0,
        );
        final detailAcrossLargestSide = (22 - normalizedStrength * 14)
            .round()
            .clamp(8, 22);
        final largestSide = max(w, h);
        final reducedWidth = max(
          4,
          (w / largestSide * detailAcrossLargestSide).round(),
        );
        final reducedHeight = max(
          4,
          (h / largestSide * detailAcrossLargestSide).round(),
        );
        region = img.copyResize(
          region,
          width: reducedWidth,
          height: reducedHeight,
          interpolation: img.Interpolation.average,
        );
        region = _safeGaussianBlur(
          region,
          radius: (1 + normalizedStrength * 4).round().clamp(1, 5),
        );
        region = img.copyResize(
          region,
          width: w,
          height: h,
          interpolation: img.Interpolation.cubic,
        );
      } else {
        region = _safeGaussianBlur(
          region,
          radius: (settings.blurStrength * renderScale).round().clamp(2, 64),
        );
      }
    } else {
      // QR modules can survive small cosmetic pixel blocks. Force a block
      // large enough to merge several modules and make the code unreadable.
      final requestedBlock = (settings.pixelSize * renderScale).round().clamp(
        4,
        160,
      );
      final privacyMinimum = switch (item.category) {
        RedactionCategory.qrCode => (min(w, h) / 12).ceil().clamp(12, 160),
        RedactionCategory.numberPlate => (min(w, h) / 5).ceil().clamp(10, 160),
        RedactionCategory.person => (min(w, h) / 20).ceil().clamp(10, 160),
        _ => 4,
      };
      final block = max(requestedBlock, privacyMinimum);
      final small = img.copyResize(
        region,
        width: max(1, w ~/ block),
        height: max(1, h ~/ block),
        interpolation: img.Interpolation.nearest,
      );
      region = img.copyResize(
        small,
        width: w,
        height: h,
        interpolation: img.Interpolation.nearest,
      );
    }
    img.compositeImage(image, region, dstX: x, dstY: y);
    return image;
  }

  img.Image _applyStroke(
    img.Image image,
    BrushStroke stroke,
    ExportSettings settings,
    double renderScale,
  ) {
    if (stroke.points.isEmpty) return image;
    if (stroke.style == RedactionStyle.blackout) {
      _drawStroke(image, stroke, img.ColorRgba8(0, 0, 0, 255));
      return image;
    }
    final padding = (stroke.size / 2).ceil() + 2;
    final left = (stroke.points.map((p) => p.dx).reduce(min).floor() - padding)
        .clamp(0, image.width - 1);
    final top = (stroke.points.map((p) => p.dy).reduce(min).floor() - padding)
        .clamp(0, image.height - 1);
    final right = (stroke.points.map((p) => p.dx).reduce(max).ceil() + padding)
        .clamp(left + 1, image.width);
    final bottom = (stroke.points.map((p) => p.dy).reduce(max).ceil() + padding)
        .clamp(top + 1, image.height);
    final width = right - left;
    final height = bottom - top;
    var altered = img.copyCrop(
      image,
      x: left,
      y: top,
      width: width,
      height: height,
    );
    if (stroke.style == RedactionStyle.blur) {
      altered = _safeGaussianBlur(
        altered,
        radius: (settings.blurStrength * renderScale).round().clamp(2, 50),
      );
    } else {
      final block = (settings.pixelSize * renderScale).round().clamp(4, 80);
      altered = img.copyResize(
        img.copyResize(
          altered,
          width: max(1, width ~/ block),
          height: max(1, height ~/ block),
          interpolation: img.Interpolation.nearest,
        ),
        width: width,
        height: height,
        interpolation: img.Interpolation.nearest,
      );
    }
    final mask = img.Image(width: width, height: height, numChannels: 1);
    final localStroke = BrushStroke(
      id: stroke.id,
      points: [
        for (final p in stroke.points)
          p - Offset(left.toDouble(), top.toDouble()),
      ],
      size: stroke.size,
      style: stroke.style,
    );
    _drawStroke(mask, localStroke, img.ColorUint8.fromList([255]));
    img.compositeImage(image, altered, dstX: left, dstY: top, mask: mask);
    return image;
  }

  /// The image package's Gaussian kernel reflects pixels at the crop edge.
  /// A radius equal to or larger than a very narrow crop can reflect beyond
  /// the crop a second time and throw a RangeError. Detected text and card
  /// details frequently become only a few pixels tall in the quick preview,
  /// so keep the kernel inside both dimensions instead of reporting the
  /// resulting bounds error as an out-of-memory failure.
  img.Image _safeGaussianBlur(img.Image image, {required int radius}) {
    final maximumRadius = min(image.width, image.height) - 1;
    if (maximumRadius < 1) return image;
    return img.gaussianBlur(image, radius: radius.clamp(1, maximumRadius));
  }

  void _drawStroke(img.Image image, BrushStroke stroke, img.Color color) {
    final radius = max(1, stroke.size ~/ 2);
    for (var i = 0; i < stroke.points.length; i++) {
      final p = stroke.points[i];
      img.drawCircle(
        image,
        x: p.dx.round(),
        y: p.dy.round(),
        radius: radius,
        color: color,
        antialias: true,
      );
      if (i > 0) {
        final a = stroke.points[i - 1];
        img.drawLine(
          image,
          x1: a.dx.round(),
          y1: a.dy.round(),
          x2: p.dx.round(),
          y2: p.dy.round(),
          color: color,
          thickness: radius * 2,
          antialias: true,
        );
      }
    }
  }

  Future<bool> verifyMetadataRemoved(String path) async {
    final decoded = img.decodeImage(await File(path).readAsBytes());
    return decoded != null && decoded.exif.isEmpty;
  }
}
