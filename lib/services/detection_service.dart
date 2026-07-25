import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:ui';

import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import '../domain/models.dart';
import 'classifier.dart';
import 'license_plate_detector.dart';
import 'person_detector.dart';

class DetectionService {
  DetectionService({
    SensitiveTextClassifier? classifier,
    LicensePlateDetector? licensePlateDetector,
    PersonDetector? personDetector,
  }) : _classifier = classifier ?? SensitiveTextClassifier(),
       _licensePlateDetector = licensePlateDetector ?? LicensePlateDetector(),
       _personDetector = personDetector ?? PersonDetector();
  final SensitiveTextClassifier _classifier;
  final LicensePlateDetector _licensePlateDetector;
  final PersonDetector _personDetector;
  late final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      performanceMode: FaceDetectorMode.accurate,
      enableClassification: true,
    ),
  );
  late final FaceDetector _fastFaceDetector = FaceDetector(
    options: FaceDetectorOptions(
      performanceMode: FaceDetectorMode.fast,
      enableClassification: false,
      enableTracking: true,
      minFaceSize: .05,
    ),
  );
  late final FaceDetector _videoAccurateFaceDetector = FaceDetector(
    options: FaceDetectorOptions(
      performanceMode: FaceDetectorMode.accurate,
      enableClassification: false,
      enableTracking: true,
      minFaceSize: .05,
    ),
  );
  late final TextRecognizer _textRecognizer = TextRecognizer(
    script: TextRecognitionScript.latin,
  );
  late final BarcodeScanner _barcodeScanner = BarcodeScanner(
    formats: [
      BarcodeFormat.qrCode,
      BarcodeFormat.code128,
      BarcodeFormat.code39,
      BarcodeFormat.ean8,
      BarcodeFormat.ean13,
      BarcodeFormat.upca,
      BarcodeFormat.upce,
      BarcodeFormat.dataMatrix,
      BarcodeFormat.pdf417,
    ],
  );

  Future<List<RedactionItem>> detectFaces(String path, Size size) async {
    final faces = await _faceDetector.processImage(
      InputImage.fromFilePath(path),
    );
    return [
      for (final face in faces)
        _item(RedactionCategory.face, _padded(face.boundingBox, size)),
    ];
  }

  /// A lighter face pass for sampled video frames. Repeated checks across the
  /// clip provide the temporal safety that a single still image cannot.
  Future<List<RedactionItem>> detectFacesFast(String path, Size size) async {
    final faces = await _fastFaceDetector.processImage(
      InputImage.fromFilePath(path),
    );
    return [
      for (final face in faces)
        _item(RedactionCategory.face, _padded(face.boundingBox, size)),
    ];
  }

  /// Uses the fast detector on every sampled video frame and periodically
  /// verifies it with the accurate model. Keeping the accurate pass on a
  /// controlled cadence protects difficult and partly cropped faces without
  /// making face-free videos unnecessarily slow to analyse.
  Future<List<RedactionItem>> detectFacesVideo(
    String path,
    Size size, {
    required bool verificationPass,
    required bool recoverEdges,
  }) async {
    final fast = await _fastFaceDetector.processImage(
      InputImage.fromFilePath(path),
    );
    final result = [
      for (final face in fast)
        _item(RedactionCategory.face, _padded(face.boundingBox, size)),
    ];
    if (!verificationPass) return result;

    final accurate = await _videoAccurateFaceDetector.processImage(
      InputImage.fromFilePath(path),
    );
    for (final face in accurate) {
      final item = _item(
        RedactionCategory.face,
        _padded(face.boundingBox, size),
      );
      if (result.every(
        (existing) => _intersectionOverUnion(existing.bounds, item.bounds) < .5,
      )) {
        result.add(item);
      }
    }
    if (result.isEmpty && recoverEdges) {
      result.addAll(await _detectMirroredEdgeFaces(path, size));
    }
    return result;
  }

  Future<List<RedactionItem>> _detectMirroredEdgeFaces(
    String path,
    Size size,
  ) async {
    var variants = const <_MirroredFaceVariant>[];
    try {
      final temporaryDirectory = await getTemporaryDirectory();
      variants = await _createMirroredFaceVariants(
        path,
        temporaryDirectory.path,
      );
      final recovered = <RedactionItem>[];
      for (final variant in variants) {
        final faces = await _videoAccurateFaceDetector.processImage(
          InputImage.fromFilePath(variant.path),
        );
        for (final face in faces) {
          final box = face.boundingBox;
          // Only accept a synthetic face that actually crosses the mirrored
          // seam. Normal faces duplicated elsewhere in the image are ignored.
          if (box.left >= variant.seamX || box.right <= variant.seamX) {
            continue;
          }
          final scaleX = size.width / variant.scaledWidth;
          final scaleY = size.height / variant.scaledHeight;
          final mapped = Rect.fromLTRB(
            (box.left - variant.originalLeft) * scaleX,
            box.top * scaleY,
            (box.right - variant.originalLeft) * scaleX,
            box.bottom * scaleY,
          );
          final visible = mapped.intersect(
            Rect.fromLTWH(0, 0, size.width, size.height),
          );
          final touchesExpectedEdge = variant.rightEdge
              ? visible.right >= size.width * .94
              : visible.left <= size.width * .06;
          if (!touchesExpectedEdge ||
              visible.width < 12 ||
              visible.height < 20) {
            continue;
          }
          final item = _item(RedactionCategory.face, _padded(mapped, size));
          if (recovered.every(
            (existing) =>
                _intersectionOverUnion(existing.bounds, item.bounds) < .5,
          )) {
            recovered.add(item);
          }
        }
      }
      return recovered;
    } catch (_) {
      // Edge recovery is an additive safety pass. A temporary image or model
      // failure must not abort the rest of video analysis.
      return const [];
    } finally {
      for (final variant in variants) {
        try {
          await File(variant.path).delete();
        } catch (_) {}
      }
    }
  }

  Future<List<RedactionItem>> detectPeople(String path, Size size) async {
    try {
      final predictions = await _personDetector.detect(path, size);
      return [
        for (final prediction in predictions)
          _item(
            RedactionCategory.person,
            _clamp(prediction.bounds, size),
            confidence: prediction.confidence,
          ),
      ];
    } catch (_) {
      // Full-person support is additive. A model/runtime problem must not
      // prevent the other privacy checks from completing.
      return const [];
    }
  }

  Future<List<RedactionItem>> detectText(String path, Size size) async {
    final text = await _textRecognizer.processImage(
      InputImage.fromFilePath(path),
    );
    final lines = [
      for (final block in text.blocks)
        for (final line in block.lines)
          _DetectedTextLine(line.text, _clamp(line.boundingBox, size)),
    ];
    return [for (final line in lines) _textItem(line, lines, size)];
  }

  RedactionCategory _textCategory(
    _DetectedTextLine line,
    List<_DetectedTextLine> lines,
  ) {
    final direct = _classifier.classify(line.text);
    if (direct != RedactionCategory.otherText) return direct;
    if (_isInAddressBlock(line, lines)) return RedactionCategory.address;
    if (!_classifier.hasPossibleSecurityCodeValue(line.text)) return direct;

    final nearLabel = lines.any(
      (candidate) =>
          (_classifier.isCardSecurityCodeLabel(candidate.text) ||
              _classifier.isCardSecurityContext(candidate.text)) &&
          _isNearbySecurityCode(candidate.bounds, line.bounds),
    );
    final nearCardNumber = lines.any(
      (candidate) =>
          _classifier.classify(candidate.text) == RedactionCategory.card &&
          _isNearbyCardDetail(candidate.bounds, line.bounds),
    );
    return nearLabel || nearCardNumber
        ? RedactionCategory.cardSecurityCode
        : RedactionCategory.otherText;
  }

  bool _isInAddressBlock(
    _DetectedTextLine line,
    List<_DetectedTextLine> lines,
  ) {
    for (final anchor in lines) {
      if (!_classifier.isAddressLabel(anchor.text) &&
          !_classifier.looksLikeAddressValue(anchor.text)) {
        continue;
      }
      final lineHeight = max(anchor.bounds.height, line.bounds.height);
      final startsBelowAnchor =
          line.bounds.top >= anchor.bounds.top - lineHeight * .4;
      final closeVertically =
          line.bounds.top <= anchor.bounds.bottom + lineHeight * 4;
      final alignedLeft =
          (anchor.bounds.left - line.bounds.left).abs() <= lineHeight * 2.2;
      if (startsBelowAnchor && closeVertically && alignedLeft) {
        return true;
      }
    }
    return false;
  }

  RedactionItem _textItem(
    _DetectedTextLine line,
    List<_DetectedTextLine> lines,
    Size imageSize,
  ) {
    final category = _textCategory(line, lines);
    final bounds = category == RedactionCategory.cardSecurityCode
        ? _paddedSecurityBounds(line.bounds, imageSize)
        : line.bounds;
    return _item(category, bounds, label: line.text);
  }

  bool _isNearbySecurityCode(Rect label, Rect value) {
    final height = max(label.height, value.height);
    final horizontalGap = max(
      0,
      max(label.left, value.left) - min(label.right, value.right),
    );
    final verticalGap = max(
      0,
      max(label.top, value.top) - min(label.bottom, value.bottom),
    );
    return horizontalGap <= max(label.width * 1.5, height * 8) &&
        verticalGap <= height * 2.5;
  }

  bool _isNearbyCardDetail(Rect cardNumber, Rect candidate) {
    final height = max(cardNumber.height, candidate.height);
    final horizontalGap = max(
      0,
      max(cardNumber.left, candidate.left) -
          min(cardNumber.right, candidate.right),
    );
    final verticalGap = max(
      0,
      max(cardNumber.top, candidate.top) -
          min(cardNumber.bottom, candidate.bottom),
    );
    return horizontalGap <= max(cardNumber.width * .6, height * 10) &&
        verticalGap <= height * 10;
  }

  Rect _paddedSecurityBounds(Rect value, Size image) {
    final horizontal = max(value.width * .06, value.height * .65);
    final vertical = value.height * .35;
    return _clamp(
      Rect.fromLTRB(
        value.left - horizontal,
        value.top - vertical,
        value.right + horizontal,
        value.bottom + vertical,
      ),
      image,
    );
  }

  Future<List<RedactionItem>> detectCodes(String path, Size size) async {
    final temporaryFiles = <String>[];
    try {
      // Start with untouched pixels. If a camera photo fails, retry at a
      // detector-friendly size and with glare/moire-resistant enhancement.
      final original = await _barcodeScanner.processImage(
        InputImage.fromFilePath(path),
      );
      if (original.any((code) => code.format == BarcodeFormat.qrCode)) {
        return _codeItems(original, size, 1, 1);
      }

      var bestCodes = original;
      var bestScaleX = 1.0;
      var bestScaleY = 1.0;

      final temp = await getTemporaryDirectory();
      final variants = await _createCodeScanVariants(
        path,
        temp.path,
        size.width.round(),
        size.height.round(),
      );
      temporaryFiles.addAll(variants.map((v) => v.path));
      for (final variant in variants) {
        final codes = await _barcodeScanner.processImage(
          InputImage.fromFilePath(variant.path),
        );
        if (codes.length > bestCodes.length ||
            codes.any((code) => code.format == BarcodeFormat.qrCode)) {
          bestCodes = codes;
          bestScaleX = size.width / variant.width;
          bestScaleY = size.height / variant.height;
        }
        if (codes.any((code) => code.format == BarcodeFormat.qrCode)) {
          break;
        }
      }
      final detected = _codeItems(bestCodes, size, bestScaleX, bestScaleY);
      if (bestCodes.any((code) => code.format == BarcodeFormat.qrCode)) {
        return detected;
      }

      final contextualQr = await _detectContextualQr(path, size);
      return [...detected, ...contextualQr];
    } finally {
      for (final path in temporaryFiles) {
        final file = File(path);
        if (await file.exists()) await file.delete();
      }
    }
  }

  /// A single-pass code scan for sampled video frames. The video analyzer sees
  /// the same region on several frames, so expensive still-photo enhancement
  /// retries are deliberately left to [detectCodes].
  Future<List<RedactionItem>> detectCodesFast(String path, Size size) async {
    final codes = await _barcodeScanner.processImage(
      InputImage.fromFilePath(path),
    );
    return _codeItems(codes, size, 1, 1);
  }

  Future<List<RedactionItem>> _detectContextualQr(
    String path,
    Size imageSize,
  ) async {
    final text = await _textRecognizer.processImage(
      InputImage.fromFilePath(path),
    );
    final scanToPay = RegExp(
      r'\bscan\s+(?:this\s+)?(?:qr\s+|the\s+)?(?:code\s+)?to\s+pay\b|\bscan\s+to\s+pay\b',
      caseSensitive: false,
    );
    final items = <RedactionItem>[];
    for (final block in text.blocks) {
      for (final line in block.lines) {
        if (!scanToPay.hasMatch(line.text)) continue;
        final anchor = _clamp(line.boundingBox, imageSize);
        final side = max(anchor.width * 1.05, anchor.height * 5.5);
        final bounds = _clamp(
          Rect.fromLTWH(
            anchor.left - side * .08,
            anchor.bottom + anchor.height * .12,
            side * 1.16,
            side * 1.16,
          ),
          imageSize,
        );
        if (bounds.width > anchor.height * 3 &&
            bounds.height > anchor.height * 3) {
          items.add(_item(RedactionCategory.qrCode, bounds));
        }
      }
    }
    return items;
  }

  Future<void> dispose() async {
    await Future.wait([
      _faceDetector.close(),
      _fastFaceDetector.close(),
      _videoAccurateFaceDetector.close(),
      _textRecognizer.close(),
      _barcodeScanner.close(),
    ]);
  }

  Future<List<RedactionItem>> detectNumberPlates(String path, Size size) async {
    try {
      final predictions = await _licensePlateDetector.detect(path, size);
      return [
        for (final prediction in predictions)
          _item(
            RedactionCategory.numberPlate,
            _clamp(prediction.bounds, size),
            confidence: prediction.confidence,
          ),
      ];
    } catch (_) {
      // Plate support is additive. A model/runtime problem must not prevent
      // face, text, and code privacy checks from completing.
      return const [];
    }
  }

  List<RedactionItem> _codeItems(
    List<Barcode> codes,
    Size imageSize,
    double scaleX,
    double scaleY,
  ) => [
    for (final code in codes)
      _item(
        code.format == BarcodeFormat.qrCode
            ? RedactionCategory.qrCode
            : RedactionCategory.barcode,
        _clamp(
          Rect.fromLTRB(
            code.boundingBox.left * scaleX,
            code.boundingBox.top * scaleY,
            code.boundingBox.right * scaleX,
            code.boundingBox.bottom * scaleY,
          ),
          imageSize,
        ),
      ),
  ];

  RedactionItem _item(
    RedactionCategory category,
    Rect bounds, {
    double? confidence,
    String? label,
  }) => RedactionItem(
    id: '${category.name}_${DateTime.now().microsecondsSinceEpoch}_${bounds.hashCode}',
    category: category,
    bounds: bounds,
    selected: category.selectedByDefault,
    style: category.defaultStyle,
    source: RedactionSource.automatic,
    confidence: confidence,
    label: label,
  );

  Rect _padded(Rect value, Size image) {
    final dx = value.width * .24, dy = value.height * .3;
    return _clamp(
      Rect.fromLTRB(
        value.left - dx,
        value.top - dy,
        value.right + dx,
        value.bottom + dy,
      ),
      image,
    );
  }

  Rect _clamp(Rect r, Size s) => Rect.fromLTRB(
    max(0, r.left),
    max(0, r.top),
    min(s.width, r.right),
    min(s.height, r.bottom),
  );

  double _intersectionOverUnion(Rect a, Rect b) {
    final intersection = a.intersect(b);
    if (intersection.width <= 0 || intersection.height <= 0) return 0;
    final area = intersection.width * intersection.height;
    final union = a.width * a.height + b.width * b.height - area;
    return union <= 0 ? 0 : area / union;
  }
}

class _DetectedTextLine {
  const _DetectedTextLine(this.text, this.bounds);

  final String text;
  final Rect bounds;
}

class _CodeScanVariant {
  const _CodeScanVariant(this.path, this.width, this.height);
  final String path;
  final int width;
  final int height;
}

class _MirroredFaceVariant {
  const _MirroredFaceVariant({
    required this.path,
    required this.scaledWidth,
    required this.scaledHeight,
    required this.originalLeft,
    required this.rightEdge,
  });

  final String path;
  final int scaledWidth;
  final int scaledHeight;
  final int originalLeft;
  final bool rightEdge;

  double get seamX => scaledWidth.toDouble();
}

Future<List<_MirroredFaceVariant>> _createMirroredFaceVariants(
  String sourcePath,
  String temporaryDirectory,
) => Isolate.run(() {
  final decoded = img.decodeImage(File(sourcePath).readAsBytesSync());
  if (decoded == null) return <_MirroredFaceVariant>[];

  const maximumSide = 1280;
  final factor = min(1.0, maximumSide / max(decoded.width, decoded.height));
  final width = max(1, (decoded.width * factor).round());
  final height = max(1, (decoded.height * factor).round());
  final original = img.copyResize(
    decoded,
    width: width,
    height: height,
    interpolation: img.Interpolation.linear,
  );
  final mirrored = img.copyFlip(
    original,
    direction: img.FlipDirection.horizontal,
  );
  final leftRecovery = img.Image(
    width: width * 2,
    height: height,
    numChannels: 3,
  );
  final rightRecovery = img.Image(
    width: width * 2,
    height: height,
    numChannels: 3,
  );

  // Left edge: mirror | original. Right edge: original | mirror. A cropped
  // half-face becomes a temporary symmetric face precisely at the seam.
  img.compositeImage(leftRecovery, mirrored);
  img.compositeImage(leftRecovery, original, dstX: width);
  img.compositeImage(rightRecovery, original);
  img.compositeImage(rightRecovery, mirrored, dstX: width);

  final stamp = DateTime.now().microsecondsSinceEpoch;
  final leftPath = '$temporaryDirectory/privacycam_face_${stamp}_left.jpg';
  final rightPath = '$temporaryDirectory/privacycam_face_${stamp}_right.jpg';
  File(leftPath).writeAsBytesSync(img.encodeJpg(leftRecovery, quality: 91));
  File(rightPath).writeAsBytesSync(img.encodeJpg(rightRecovery, quality: 91));
  return [
    _MirroredFaceVariant(
      path: leftPath,
      scaledWidth: width,
      scaledHeight: height,
      originalLeft: width,
      rightEdge: false,
    ),
    _MirroredFaceVariant(
      path: rightPath,
      scaledWidth: width,
      scaledHeight: height,
      originalLeft: 0,
      rightEdge: true,
    ),
  ];
});

Future<List<_CodeScanVariant>> _createCodeScanVariants(
  String sourcePath,
  String temporaryDirectory,
  int originalWidth,
  int originalHeight,
) => Isolate.run(() {
  final source = img.decodeImage(File(sourcePath).readAsBytesSync());
  if (source == null) return <_CodeScanVariant>[];
  const maximumSide = 2048;
  final factor = min(1.0, maximumSide / max(originalWidth, originalHeight));
  final width = max(1, (originalWidth * factor).round());
  final height = max(1, (originalHeight * factor).round());
  final resized = img.copyResize(
    source,
    width: width,
    height: height,
    interpolation: img.Interpolation.linear,
  );
  final stamp = DateTime.now().microsecondsSinceEpoch;
  final normalPath = '$temporaryDirectory/privacycam_code_${stamp}_scaled.jpg';
  File(normalPath).writeAsBytesSync(img.encodeJpg(resized, quality: 94));

  final enhanced = img.adjustColor(
    img.Image.from(resized, noAnimation: true),
    contrast: 1.55,
    saturation: 0,
  );
  final enhancedPath =
      '$temporaryDirectory/privacycam_code_${stamp}_enhanced.jpg';
  File(enhancedPath).writeAsBytesSync(img.encodeJpg(enhanced, quality: 96));

  final threshold = img.luminanceThreshold(
    img.Image.from(resized, noAnimation: true),
    threshold: .52,
  );
  final thresholdPath =
      '$temporaryDirectory/privacycam_code_${stamp}_threshold.jpg';
  File(thresholdPath).writeAsBytesSync(img.encodeJpg(threshold, quality: 98));
  return [
    _CodeScanVariant(normalPath, width, height),
    _CodeScanVariant(enhancedPath, width, height),
    _CodeScanVariant(thresholdPath, width, height),
  ];
});
