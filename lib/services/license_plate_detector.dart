import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:image/image.dart' as img;

const _modelAsset = 'assets/models/license_plate_yolov9_t_384.onnx';
const _inputSize = 384;

class LicensePlatePrediction {
  const LicensePlatePrediction(this.bounds, this.confidence);

  final Rect bounds;
  final double confidence;
}

class LicensePlateDetector {
  Future<OrtSession>? _session;

  Future<List<LicensePlatePrediction>> detect(
    String imagePath,
    Size imageSize,
  ) async {
    final prepared = await Isolate.run(() => _prepareInput(imagePath));
    if (prepared == null) return const [];

    final session = await (_session ??= OnnxRuntime().createSessionFromAsset(
      _modelAsset,
      options: OrtSessionOptions(intraOpNumThreads: 4, interOpNumThreads: 1),
    ));
    OrtValue? input;
    var outputs = <String, OrtValue>{};
    try {
      input = await OrtValue.fromList(prepared.pixels, const [
        1,
        3,
        _inputSize,
        _inputSize,
      ]);
      outputs = await session.run({'images': input});
      final output = outputs['output0'];
      if (output == null) return const [];
      final values = await output.asFlattenedList();
      final shape = output.shape;
      if (shape.length != 2 ||
          shape.last != 7 ||
          shape.first < 0 ||
          values.length != shape.first * 7) {
        return const [];
      }
      return decodeLicensePlateOutput(
        values,
        modelScale: prepared.scale,
        horizontalPadding: prepared.horizontalPadding,
        verticalPadding: prepared.verticalPadding,
        imageSize: imageSize,
      );
    } finally {
      for (final output in outputs.values) {
        await output.dispose();
      }
      await input?.dispose();
    }
  }
}

class _PreparedPlateInput {
  const _PreparedPlateInput(
    this.pixels,
    this.scale,
    this.horizontalPadding,
    this.verticalPadding,
  );

  final Float32List pixels;
  final double scale;
  final double horizontalPadding;
  final double verticalPadding;
}

_PreparedPlateInput? _prepareInput(String imagePath) {
  final source = img.decodeImage(File(imagePath).readAsBytesSync());
  if (source == null) return null;

  final scale = min(_inputSize / source.width, _inputSize / source.height);
  final resizedWidth = max(1, (source.width * scale).round());
  final resizedHeight = max(1, (source.height * scale).round());
  final horizontalPadding = (_inputSize - resizedWidth) / 2;
  final verticalPadding = (_inputSize - resizedHeight) / 2;
  final left = (horizontalPadding - .1).round();
  final top = (verticalPadding - .1).round();
  final resized = img.copyResize(
    source,
    width: resizedWidth,
    height: resizedHeight,
    interpolation: img.Interpolation.linear,
  );

  // The model consumes normalized RGB in NCHW order with centered 114-gray
  // letterboxing, matching its YOLOv9 training preprocessing exactly.
  final planeSize = _inputSize * _inputSize;
  final pixels = Float32List(planeSize * 3)
    ..fillRange(0, planeSize * 3, 114 / 255);
  for (var y = 0; y < resizedHeight; y++) {
    final row = (y + top) * _inputSize + left;
    for (var x = 0; x < resizedWidth; x++) {
      final pixel = resized.getPixel(x, y);
      final target = row + x;
      pixels[target] = pixel.r.toInt() / 255;
      pixels[planeSize + target] = pixel.g.toInt() / 255;
      pixels[planeSize * 2 + target] = pixel.b.toInt() / 255;
    }
  }
  return _PreparedPlateInput(pixels, scale, horizontalPadding, verticalPadding);
}

/// Decodes the model's end-to-end NMS output. Each row contains batch index,
/// left, top, right, bottom, class index, and confidence.
List<LicensePlatePrediction> decodeLicensePlateOutput(
  List<dynamic> output, {
  required double modelScale,
  required double horizontalPadding,
  required double verticalPadding,
  required Size imageSize,
  double confidenceThreshold = .4,
}) {
  if (output.length % 7 != 0 || modelScale <= 0) return const [];
  final predictions = <LicensePlatePrediction>[];
  for (var offset = 0; offset < output.length; offset += 7) {
    final batchIndex = (output[offset] as num).toDouble();
    final classIndex = (output[offset + 5] as num).toDouble();
    final confidence = (output[offset + 6] as num).toDouble();
    final modelLeft = (output[offset + 1] as num).toDouble();
    final modelTop = (output[offset + 2] as num).toDouble();
    final modelRight = (output[offset + 3] as num).toDouble();
    final modelBottom = (output[offset + 4] as num).toDouble();

    // This end-to-end model emits [batch, x1, y1, x2, y2, class,
    // confidence]. Strictly validate that contract so an incompatible or
    // malformed tensor cannot turn ordinary coordinates into plate scores.
    if (![
      batchIndex,
      classIndex,
      confidence,
      modelLeft,
      modelTop,
      modelRight,
      modelBottom,
    ].every((value) => value.isFinite)) {
      continue;
    }
    if (batchIndex.abs() > .001 ||
        classIndex.abs() > .001 ||
        confidence < confidenceThreshold ||
        confidence > 1.001 ||
        modelLeft < -1 ||
        modelTop < -1 ||
        modelRight > _inputSize + 1 ||
        modelBottom > _inputSize + 1 ||
        modelRight <= modelLeft ||
        modelBottom <= modelTop) {
      continue;
    }

    final modelWidth = modelRight - modelLeft;
    final modelHeight = modelBottom - modelTop;
    final aspectRatio = modelWidth / modelHeight;
    // Car plates are horizontally oriented. This rejects the tall UI/text
    // fragments that caused the false-positive flood in social screenshots.
    if (modelWidth < 6 ||
        modelHeight < 3 ||
        aspectRatio < 1.1 ||
        aspectRatio > 8 ||
        modelWidth * modelHeight > _inputSize * _inputSize * .35) {
      continue;
    }
    final bounds = Rect.fromLTRB(
      (modelLeft - horizontalPadding) / modelScale,
      (modelTop - verticalPadding) / modelScale,
      (modelRight - horizontalPadding) / modelScale,
      (modelBottom - verticalPadding) / modelScale,
    ).intersect(Rect.fromLTWH(0, 0, imageSize.width, imageSize.height));
    if (bounds.width < 4 || bounds.height < 3) continue;

    final horizontalSafety = bounds.width * .1;
    final verticalSafety = bounds.height * .2;
    predictions.add(
      LicensePlatePrediction(
        Rect.fromLTRB(
          max(0, bounds.left - horizontalSafety),
          max(0, bounds.top - verticalSafety),
          min(imageSize.width, bounds.right + horizontalSafety),
          min(imageSize.height, bounds.bottom + verticalSafety),
        ),
        confidence,
      ),
    );
  }
  predictions.sort((a, b) => b.confidence.compareTo(a.confidence));
  final distinct = <LicensePlatePrediction>[];
  for (final prediction in predictions) {
    if (distinct.any(
      (kept) => _intersectionOverUnion(kept.bounds, prediction.bounds) > .55,
    )) {
      continue;
    }
    distinct.add(prediction);
    // A 384 px input cannot reliably distinguish an unbounded number of
    // plates. Capping anomalous output is safer than masking an entire photo.
    if (distinct.length == 20) break;
  }
  return distinct;
}

double _intersectionOverUnion(Rect a, Rect b) {
  final intersection = a.intersect(b);
  if (intersection.isEmpty) return 0;
  final intersectionArea = intersection.width * intersection.height;
  final unionArea = a.width * a.height + b.width * b.height - intersectionArea;
  return unionArea <= 0 ? 0 : intersectionArea / unionArea;
}
