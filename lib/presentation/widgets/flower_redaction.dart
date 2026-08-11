import 'dart:math';

import 'package:flutter/material.dart';

/// An opaque decorative privacy cover. The solid base guarantees that the
/// original content stays hidden even between the flower shapes.
class FlowerRedaction extends StatelessWidget {
  const FlowerRedaction({super.key, this.border});

  final Border? border;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(color: const Color(0xFFF7D9E5), border: border),
    child: const CustomPaint(painter: _FlowerPainter()),
  );
}

class _FlowerPainter extends CustomPainter {
  const _FlowerPainter();

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final spacing = min(38.0, max(14.0, size.height * .72));
    final radius = (spacing * .2).clamp(2.5, 7.0);
    final petal = Paint()..color = const Color(0xFFE75480);
    final alternatePetal = Paint()..color = const Color(0xFF8D6BC4);
    final center = Paint()..color = const Color(0xFFFFC83D);
    final leaf = Paint()..color = const Color(0xFF168266);
    var row = 0;
    for (var y = spacing / 2; y < size.height; y += spacing) {
      final start = row.isEven ? spacing / 2 : 0.0;
      for (var x = start; x < size.width; x += spacing) {
        final flowerCenter = Offset(x, y);
        final petals = row.isEven ? petal : alternatePetal;
        canvas.drawOval(
          Rect.fromCenter(
            center: flowerCenter + Offset(radius * 1.55, radius * 1.7),
            width: radius * 1.3,
            height: radius * 2.4,
          ),
          leaf,
        );
        for (var i = 0; i < 6; i++) {
          final angle = i * pi / 3;
          canvas.drawCircle(
            flowerCenter + Offset(cos(angle), sin(angle)) * radius,
            radius * .82,
            petals,
          );
        }
        canvas.drawCircle(flowerCenter, radius * .65, center);
      }
      row++;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
