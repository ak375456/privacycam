import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
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
}
