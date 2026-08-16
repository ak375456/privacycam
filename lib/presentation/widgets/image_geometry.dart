import 'dart:math';
import 'dart:ui';

import '../../domain/models.dart';

class ImageGeometry {
  ImageGeometry(Size viewport, Size image) : imageSize = image {
    final scale = min(
      viewport.width / image.width,
      viewport.height / image.height,
    );
    displayed = Size(image.width * scale, image.height * scale);
    origin = Offset(
      (viewport.width - displayed.width) / 2,
      (viewport.height - displayed.height) / 2,
    );
    factor = scale;
  }
  final Size imageSize;
  late final Size displayed;
  late final Offset origin;
  late final double factor;
  Rect toLocalRect(Rect r) => Rect.fromLTWH(
    origin.dx + r.left * factor,
    origin.dy + r.top * factor,
    r.width * factor,
    r.height * factor,
  );
  Offset toImage(Offset p) => Offset(
    ((p.dx - origin.dx) / factor).clamp(0, imageSize.width),
    ((p.dy - origin.dy) / factor).clamp(0, imageSize.height),
  );
  Rect clamp(Rect r) => Rect.fromLTRB(
    r.left.clamp(0, imageSize.width),
    r.top.clamp(0, imageSize.height),
    r.right.clamp(0, imageSize.width),
    r.bottom.clamp(0, imageSize.height),
  );
}

/// Finds the most useful redaction target near [point].
///
/// Automatic detections can be only a few screen pixels wide (for example, a
/// distant number plate). The visible outline must remain accurate, but its
/// invisible touch target should still meet a comfortable minimum size.
RedactionItem? hitTestRedactionItems(
  Iterable<RedactionItem> items,
  Offset point, {
  required double displayScale,
  double minimumScreenTarget = 48,
}) {
  final safeScale = displayScale.isFinite && displayScale > 0
      ? displayScale
      : 1.0;
  final minimumImageTarget = minimumScreenTarget / safeScale;
  final matches = items.where((item) {
    final bounds = item.bounds;
    return Rect.fromCenter(
      center: bounds.center,
      width: max(bounds.width, minimumImageTarget),
      height: max(bounds.height, minimumImageTarget),
    ).contains(point);
  }).toList();
  matches.sort((a, b) {
    final aContains = a.bounds.contains(point);
    final bContains = b.bounds.contains(point);
    if (aContains != bContains) return aContains ? -1 : 1;
    final distance = _distanceToRect(
      point,
      a.bounds,
    ).compareTo(_distanceToRect(point, b.bounds));
    if (distance != 0) return distance;
    return (a.bounds.width * a.bounds.height).compareTo(
      b.bounds.width * b.bounds.height,
    );
  });
  return matches.firstOrNull;
}

double _distanceToRect(Offset point, Rect rect) {
  final dx = point.dx < rect.left
      ? rect.left - point.dx
      : point.dx > rect.right
      ? point.dx - rect.right
      : 0.0;
  final dy = point.dy < rect.top
      ? rect.top - point.dy
      : point.dy > rect.bottom
      ? point.dy - rect.bottom
      : 0.0;
  return sqrt(dx * dx + dy * dy);
}
