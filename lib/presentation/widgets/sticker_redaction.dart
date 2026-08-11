import 'dart:math';

import 'package:flutter/material.dart';

import '../../domain/models.dart';

/// Draws large sticker-style privacy masks similar to an emoji placed over a
/// face. Wide areas receive multiple stickers so text remains covered.
class StickerRedaction extends StatelessWidget {
  const StickerRedaction({super.key, required this.style, this.border});

  final RedactionStyle style;
  final Border? border;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(border: border),
    child: CustomPaint(painter: _StickerPainter(style)),
  );
}

class _StickerPainter extends CustomPainter {
  const _StickerPainter(this.style);

  final RedactionStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final stickerSize = min(size.height * .94, size.width);
    final count = size.width <= stickerSize * 1.35
        ? 1
        : max(1, (size.width / max(1, stickerSize * .82)).ceil());
    final spacing = size.width / count;
    for (var i = 0; i < count; i++) {
      final center = Offset(spacing * (i + .5), size.height / 2);
      if (style == RedactionStyle.emoji) {
        _drawHeart(canvas, center, stickerSize);
      } else {
        _drawFlower(canvas, center, stickerSize, alternate: i.isOdd);
      }
    }
  }

  void _drawHeart(Canvas canvas, Offset center, double size) {
    final path = Path();
    final top = center.dy - size * .35;
    path.moveTo(center.dx, center.dy + size * .42);
    path.cubicTo(
      center.dx - size * .58,
      center.dy + size * .08,
      center.dx - size * .48,
      top,
      center.dx - size * .22,
      top,
    );
    path.cubicTo(
      center.dx - size * .07,
      top,
      center.dx,
      top + size * .13,
      center.dx,
      top + size * .13,
    );
    path.cubicTo(
      center.dx,
      top + size * .13,
      center.dx + size * .07,
      top,
      center.dx + size * .22,
      top,
    );
    path.cubicTo(
      center.dx + size * .48,
      top,
      center.dx + size * .58,
      center.dy + size * .08,
      center.dx,
      center.dy + size * .42,
    );
    path.close();
    canvas.drawShadow(path, Colors.black45, max(1, size * .035), false);
    canvas.drawPath(path, Paint()..color = const Color(0xFFFFC928));
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(1, size * .025)
        ..color = const Color(0xFFE8A900),
    );
  }

  void _drawFlower(
    Canvas canvas,
    Offset center,
    double size, {
    required bool alternate,
  }) {
    final radius = size * .25;
    final petal = Paint()
      ..color = alternate ? const Color(0xFFE75480) : const Color(0xFFFF5A1F);
    final middle = Paint()..color = const Color(0xFFFFE4A8);
    canvas.drawShadow(
      Path()..addOval(Rect.fromCircle(center: center, radius: size * .48)),
      Colors.black38,
      max(1, size * .035),
      false,
    );
    for (var i = 0; i < 6; i++) {
      final angle = i * pi / 3;
      canvas.drawCircle(
        center + Offset(cos(angle), sin(angle)) * radius,
        radius * .88,
        petal,
      );
    }
    canvas.drawCircle(center, radius * .74, middle);
  }

  @override
  bool shouldRepaint(covariant _StickerPainter oldDelegate) =>
      oldDelegate.style != style;
}
