import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme.dart';

class PrivacyLoader extends StatefulWidget {
  const PrivacyLoader({
    super.key,
    required this.label,
    this.progress,
    this.detail = 'Everything stays on this device',
  });

  final String label;
  final double? progress;
  final String detail;

  @override
  State<PrivacyLoader> createState() => _PrivacyLoaderState();
}

class _PrivacyLoaderState extends State<PrivacyLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: widget.progress == null
        ? widget.label
        : '${widget.label}, ${(widget.progress! * 100).round()} percent',
    liveRegion: true,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final pulse = .96 + math.sin(_controller.value * math.pi * 2) * .04;
            return SizedBox(
              width: 112,
              height: 112,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CustomPaint(
                    size: const Size.square(112),
                    painter: _OrbitPainter(_controller.value),
                  ),
                  Transform.scale(
                    scale: pulse,
                    child: Container(
                      width: 62,
                      height: 62,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: forest.withValues(alpha: .2),
                            blurRadius: 22,
                            spreadRadius: 3,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.shield_outlined,
                        color: forest,
                        size: 31,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 22),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 350),
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween(
                begin: const Offset(0, .15),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          ),
          child: Text(
            widget.label,
            key: ValueKey(widget.label),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        const SizedBox(height: 9),
        Text(
          widget.detail,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.black54, fontSize: 13),
        ),
        const SizedBox(height: 20),
        if (widget.progress == null)
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: SizedBox(
              width: 220,
              child: const LinearProgressIndicator(minHeight: 7),
            ),
          )
        else
          TweenAnimationBuilder<double>(
            tween: Tween(end: widget.progress!.clamp(0, 1)),
            duration: const Duration(milliseconds: 550),
            curve: Curves.easeOutCubic,
            builder: (context, value, _) => ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: SizedBox(
                width: 220,
                child: LinearProgressIndicator(
                  value: value,
                  minHeight: 7,
                  backgroundColor: mint,
                  color: forest,
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class _OrbitPainter extends CustomPainter {
  const _OrbitPainter(this.value);
  final double value;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..color = mint;
    canvas.drawCircle(center, 48, track);
    final active = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..shader = const SweepGradient(
        colors: [forest, Color(0xFF65C9A6), forest],
      ).createShader(Offset.zero & size);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: 48),
      value * math.pi * 2,
      math.pi * .8,
      false,
      active,
    );
    final angle = value * math.pi * 2 + math.pi * .8;
    final dot = center + Offset(math.cos(angle), math.sin(angle)) * 48;
    canvas.drawCircle(dot, 4.5, Paint()..color = const Color(0xFF65C9A6));
  }

  @override
  bool shouldRepaint(covariant _OrbitPainter oldDelegate) =>
      oldDelegate.value != value;
}
