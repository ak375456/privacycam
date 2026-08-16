import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:privacycam/domain/models.dart';
import 'package:privacycam/presentation/widgets/image_geometry.dart';

void main() {
  test('maps contained portrait overlays and touch points without drift', () {
    final geometry = ImageGeometry(
      const Size(400, 400),
      const Size(1000, 2000),
    );
    expect(geometry.displayed, const Size(200, 400));
    expect(geometry.origin, const Offset(100, 0));
    expect(
      geometry.toLocalRect(const Rect.fromLTWH(100, 200, 300, 400)),
      const Rect.fromLTWH(120, 40, 60, 80),
    );
    expect(geometry.toImage(const Offset(120, 40)), const Offset(100, 200));
  });

  test('small redactions keep a 48 logical-pixel touch target', () {
    const tinyPlate = RedactionItem(
      id: 'plate',
      category: RedactionCategory.numberPlate,
      bounds: Rect.fromLTWH(500, 500, 12, 8),
      selected: false,
      style: RedactionStyle.blackout,
      source: RedactionSource.automatic,
    );

    expect(
      hitTestRedactionItems(
        const [tinyPlate],
        const Offset(530, 504),
        displayScale: .5,
      )?.id,
      'plate',
    );
  });

  test('the smallest exact match wins when redactions overlap', () {
    const person = RedactionItem(
      id: 'person',
      category: RedactionCategory.person,
      bounds: Rect.fromLTWH(100, 100, 500, 900),
      selected: true,
      style: RedactionStyle.blackout,
      source: RedactionSource.automatic,
    );
    const face = RedactionItem(
      id: 'face',
      category: RedactionCategory.face,
      bounds: Rect.fromLTWH(220, 150, 120, 120),
      selected: true,
      style: RedactionStyle.blur,
      source: RedactionSource.automatic,
    );

    expect(
      hitTestRedactionItems(
        const [person, face],
        const Offset(250, 180),
        displayScale: 1,
      )?.id,
      'face',
    );
  });
}
