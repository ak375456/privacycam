import 'dart:math';
import 'dart:ui';

import '../domain/models.dart';

/// Converts a rectangular mask into a stroke that fully covers the rectangle
/// while allowing later eraser gestures to split it into smaller pieces.
BrushStroke redactionItemAsStroke(RedactionItem item, {required String id}) {
  final bounds = item.bounds;
  final horizontal = bounds.width >= bounds.height;
  final center = bounds.center;
  return BrushStroke(
    id: id,
    points: horizontal
        ? [Offset(bounds.left, center.dy), Offset(bounds.right, center.dy)]
        : [Offset(center.dx, bounds.top), Offset(center.dx, bounds.bottom)],
    size: max(1, horizontal ? bounds.height : bounds.width),
    style: item.style,
  );
}

/// Removes only the part of a brush stroke covered by a circular eraser.
List<BrushStroke> eraseBrushStroke(
  BrushStroke stroke, {
  required Offset center,
  required double radius,
  required String fragmentIdPrefix,
}) {
  if (stroke.points.isEmpty || radius <= 0) return [stroke];

  final effectiveRadius = radius + stroke.size / 2;
  final sampleStep = min(6.0, max(1.0, min(stroke.size / 4, radius / 3)));
  final samples = _samplePolyline(stroke.points, sampleStep);
  final erased = [
    for (final point in samples) (point - center).distance <= effectiveRadius,
  ];
  if (!erased.any((value) => value)) return [stroke];

  final fragments = <List<Offset>>[];
  var current = <Offset>[];
  for (var index = 0; index < samples.length; index++) {
    if (erased[index]) {
      if (current.isNotEmpty) fragments.add(current);
      current = <Offset>[];
      continue;
    }
    current.add(samples[index]);
  }
  if (current.isNotEmpty) fragments.add(current);

  return [
    for (var index = 0; index < fragments.length; index++)
      BrushStroke(
        id: '${fragmentIdPrefix}_$index',
        points: fragments[index].length == 1
            ? [
                fragments[index].single,
                fragments[index].single + const Offset(.01, .01),
              ]
            : fragments[index],
        size: stroke.size,
        style: stroke.style,
      ),
  ];
}

List<Offset> _samplePolyline(List<Offset> points, double step) {
  if (points.length == 1) return [points.single];
  final sampled = <Offset>[];
  for (var index = 0; index < points.length - 1; index++) {
    final start = points[index];
    final end = points[index + 1];
    final segments = max(1, ((end - start).distance / step).ceil());
    for (var part = index == 0 ? 0 : 1; part <= segments; part++) {
      sampled.add(Offset.lerp(start, end, part / segments)!);
    }
  }
  return sampled;
}
