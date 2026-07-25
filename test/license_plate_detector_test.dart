import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:privacycam/domain/models.dart';
import 'package:privacycam/services/license_plate_detector.dart';

void main() {
  test('number plates default to selected strong pixelation', () {
    expect(RedactionCategory.numberPlate.selectedByDefault, isTrue);
    expect(RedactionCategory.numberPlate.defaultStyle, RedactionStyle.pixelate);
  });

  test('decodes, maps, and pads an end-to-end plate box', () {
    final predictions = decodeLicensePlateOutput(
      const [0, 100, 120, 200, 160, 0, .8, 0, 20, 20, 40, 30, 0, .1],
      modelScale: .5,
      horizontalPadding: 10,
      verticalPadding: 20,
      imageSize: const Size(640, 640),
    );

    expect(predictions, hasLength(1));
    expect(predictions.single.confidence, .8);
    expect(predictions.single.bounds, const Rect.fromLTRB(160, 184, 400, 296));
  });

  test('rejects malformed and vertical plate candidates', () {
    final predictions = decodeLicensePlateOutput(
      const [
        // Wrong batch index: this is not an end-to-end detection row.
        120,
        20,
        20,
        100,
        50,
        0,
        .99,
        // Wrong class index.
        0,
        20,
        20,
        100,
        50,
        3,
        .99,
        // Tall text/UI fragment rather than a horizontal plate.
        0,
        20,
        20,
        40,
        180,
        0,
        .99,
        // Low-confidence model candidate.
        0,
        20,
        20,
        100,
        50,
        0,
        .2,
      ],
      modelScale: 1,
      horizontalPadding: 0,
      verticalPadding: 0,
      imageSize: const Size(384, 384),
    );

    expect(predictions, isEmpty);
  });

  test('deduplicates overlapping plate candidates', () {
    final predictions = decodeLicensePlateOutput(
      const [0, 100, 100, 200, 140, 0, .9, 0, 102, 101, 198, 139, 0, .8],
      modelScale: 1,
      horizontalPadding: 0,
      verticalPadding: 0,
      imageSize: const Size(384, 384),
    );

    expect(predictions, hasLength(1));
    expect(predictions.single.confidence, .9);
  });
}
