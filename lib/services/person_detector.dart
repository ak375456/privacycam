import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:image/image.dart' as img;

const _modelAsset = 'assets/models/yolox_nano.onnx';
const _inputSize = 416;
const _predictionCount = 3549;
const _valuesPerPrediction = 85;

class PersonPrediction {
  const PersonPrediction(this.bounds, this.confidence);

  final Rect bounds;
  final double confidence;
}

class PersonDetector {
  Future<OrtSession>? _session;

  Future<List<PersonPrediction>> detect(
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
      final output = outputs['output'];
      if (output == null) return const [];
      final values = await output.asFlattenedList();
      final shape = output.shape;
      if (shape.length != 3 ||
          shape[0] != 1 ||
          shape[1] != _predictionCount ||
          shape[2] != _valuesPerPrediction ||
          values.length != _predictionCount * _valuesPerPrediction) {
        return const [];
      }
      return decodePersonOutput(
        values,
        modelScale: prepared.scale,
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

class _PreparedPersonInput {
  const _PreparedPersonInput(this.pixels, this.scale);

  final Float32List pixels;
  final double scale;
}

_PreparedPersonInput? _prepareInput(String imagePath) {
  final source = img.decodeImage(File(imagePath).readAsBytesSync());
  if (source == null) return null;

  final scale = min(_inputSize / source.width, _inputSize / source.height);
  final resizedWidth = max(1, (source.width * scale).round());
  final resizedHeight = max(1, (source.height * scale).round());
  final resized = img.copyResize(
    source,
    width: resizedWidth,
    height: resizedHeight,
    interpolation: img.Interpolation.linear,
  );

  // YOLOX consumes unnormalized RGB values in NCHW order. Its official ONNX
  // preprocessing places the resized image at the top-left of a 114-gray
  // square while preserving the source aspect ratio.
  final planeSize = _inputSize * _inputSize;
  final pixels = Float32List(planeSize * 3)..fillRange(0, planeSize * 3, 114);
  for (var y = 0; y < resizedHeight; y++) {
    final row = y * _inputSize;
    for (var x = 0; x < resizedWidth; x++) {
      final pixel = resized.getPixel(x, y);
      final target = row + x;
      pixels[target] = pixel.r.toDouble();
      pixels[planeSize + target] = pixel.g.toDouble();
      pixels[planeSize * 2 + target] = pixel.b.toDouble();
    }
  }
  return _PreparedPersonInput(pixels, scale);
}

List<PersonPrediction> decodePersonOutput(
  List<dynamic> output, {
  required double modelScale,
  required Size imageSize,
  double confidenceThreshold = .25,
}) {
  if (modelScale <= 0 ||
      output.length != _predictionCount * _valuesPerPrediction) {
    return const [];
  }

  final predictions = <PersonPrediction>[];
  for (var index = 0; index < _predictionCount; index++) {
    final offset = index * _valuesPerPrediction;
    final rawX = (output[offset] as num).toDouble();
    final rawY = (output[offset + 1] as num).toDouble();
    final rawWidth = (output[offset + 2] as num).toDouble();
    final rawHeight = (output[offset + 3] as num).toDouble();
    final objectConfidence = (output[offset + 4] as num).toDouble();
    // COCO class zero is "person".
    final personConfidence = (output[offset + 5] as num).toDouble();
    final confidence = objectConfidence * personConfidence;
    if (![
          rawX,
          rawY,
          rawWidth,
          rawHeight,
          confidence,
        ].every((value) => value.isFinite) ||
        confidence < confidenceThreshold ||
        rawWidth.abs() > 12 ||
        rawHeight.abs() > 12) {
      continue;
    }

    final grid = _gridFor(index);
    final centerX = (rawX + grid.x) * grid.stride;
    final centerY = (rawY + grid.y) * grid.stride;
    final modelWidth = exp(rawWidth) * grid.stride;
    final modelHeight = exp(rawHeight) * grid.stride;
    if (![
          centerX,
          centerY,
          modelWidth,
          modelHeight,
        ].every((value) => value.isFinite) ||
        modelWidth < 4 ||
        modelHeight < 6) {
      continue;
    }

    var bounds = Rect.fromLTRB(
      (centerX - modelWidth / 2) / modelScale,
      (centerY - modelHeight / 2) / modelScale,
      (centerX + modelWidth / 2) / modelScale,
      (centerY + modelHeight / 2) / modelScale,
    ).intersect(Rect.fromLTWH(0, 0, imageSize.width, imageSize.height));
    if (bounds.width < 12 || bounds.height < 18) continue;

    final aspectRatio = bounds.width / bounds.height;
    if (aspectRatio < .12 || aspectRatio > 2.4) continue;

    // Protect hair, hands, loose clothing and small detector edge errors.
    final horizontalSafety = bounds.width * .09;
    final topSafety = bounds.height * .08;
    final bottomSafety = bounds.height * .05;
    bounds = Rect.fromLTRB(
      max(0, bounds.left - horizontalSafety),
      max(0, bounds.top - topSafety),
      min(imageSize.width, bounds.right + horizontalSafety),
      min(imageSize.height, bounds.bottom + bottomSafety),
    );
    predictions.add(PersonPrediction(bounds, confidence));
  }

  predictions.sort((a, b) => b.confidence.compareTo(a.confidence));
  final distinct = <PersonPrediction>[];
  for (final prediction in predictions) {
    if (distinct.any(
      (kept) => _intersectionOverUnion(kept.bounds, prediction.bounds) > .45,
    )) {
      continue;
    }
    distinct.add(prediction);
    if (distinct.length == 30) break;
  }
  return distinct;
}

({int x, int y, int stride}) _gridFor(int index) {
  const stride8Count = 52 * 52;
  const stride16Count = 26 * 26;
  if (index < stride8Count) {
    return (x: index % 52, y: index ~/ 52, stride: 8);
  }
  final afterStride8 = index - stride8Count;
  if (afterStride8 < stride16Count) {
    return (x: afterStride8 % 26, y: afterStride8 ~/ 26, stride: 16);
  }
  final afterStride16 = afterStride8 - stride16Count;
  return (x: afterStride16 % 13, y: afterStride16 ~/ 13, stride: 32);
}

double _intersectionOverUnion(Rect a, Rect b) {
  final intersection = a.intersect(b);
  if (intersection.isEmpty) return 0;
  final intersectionArea = intersection.width * intersection.height;
  final unionArea = a.width * a.height + b.width * b.height - intersectionArea;
  return unionArea <= 0 ? 0 : intersectionArea / unionArea;
}
