import 'dart:math';
import 'dart:ui';

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
