import 'package:flutter_test/flutter_test.dart';
import 'package:privacycam/domain/models.dart';
import 'package:privacycam/services/stroke_eraser.dart';

void main() {
  BrushStroke line() => const BrushStroke(
    id: 'line',
    points: [Offset(0, 50), Offset(100, 50)],
    size: 10,
    style: RedactionStyle.blackout,
  );

  test('erasing the middle preserves both sides of a brush line', () {
    final fragments = eraseBrushStroke(
      line(),
      center: const Offset(50, 50),
      radius: 10,
      fragmentIdPrefix: 'part',
    );

    expect(fragments, hasLength(2));
    expect(fragments.first.points.first.dx, 0);
    expect(fragments.first.points.last.dx, lessThanOrEqualTo(35));
    expect(fragments.last.points.first.dx, greaterThanOrEqualTo(65));
    expect(fragments.last.points.last.dx, 100);
    expect(fragments.every((fragment) => fragment.size == 10), isTrue);
  });

  test('a distant eraser leaves the original stroke untouched', () {
    final original = line();
    final fragments = eraseBrushStroke(
      original,
      center: const Offset(50, 100),
      radius: 10,
      fragmentIdPrefix: 'part',
    );

    expect(fragments, hasLength(1));
    expect(identical(fragments.single, original), isTrue);
  });

  test('covering the complete stroke removes it', () {
    final fragments = eraseBrushStroke(
      line(),
      center: const Offset(50, 50),
      radius: 100,
      fragmentIdPrefix: 'part',
    );

    expect(fragments, isEmpty);
  });
}
