import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../domain/models.dart';
import '../../domain/video_models.dart';
import 'flower_redaction.dart';

class VideoRedactionOverlay extends StatelessWidget {
  const VideoRedactionOverlay({
    super.key,
    required this.tracks,
    required this.timestampMs,
    required this.selectedTrackId,
    required this.blurStrength,
    required this.pixelSize,
    this.pixelProgram,
    this.draftBounds,
  });

  final List<VideoRedactionTrack> tracks;
  final int timestampMs;
  final String? selectedTrackId;
  final double blurStrength;
  final double pixelSize;
  final ui.FragmentProgram? pixelProgram;
  final Rect? draftBounds;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final size = constraints.biggest;
      final visibleTracks =
          tracks.where((track) => track.existsAt(timestampMs)).toList()
            ..sort((a, b) => _paintOrder(a).compareTo(_paintOrder(b)));
      return Stack(
        fit: StackFit.expand,
        children: [
          for (final track in visibleTracks)
            _Region(
              bounds: _denormalize(track.boundsAt(timestampMs), size),
              style: track.style,
              enabled: track.selected,
              focused: track.id == selectedTrackId,
              blurStrength: blurStrength,
              pixelSize: pixelSize,
              pixelProgram: pixelProgram,
            ),
          if (draftBounds != null)
            Positioned.fromRect(
              rect: _denormalize(draftBounds!, size),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: mint.withValues(alpha: .18),
                  border: Border.all(color: Colors.white, width: 2),
                ),
              ),
            ),
        ],
      );
    },
  );

  Rect _denormalize(Rect bounds, Size size) => Rect.fromLTRB(
    bounds.left * size.width,
    bounds.top * size.height,
    bounds.right * size.width,
    bounds.bottom * size.height,
  );

  int _paintOrder(VideoRedactionTrack track) {
    final categoryLayer = switch (track.category) {
      RedactionCategory.person => 0,
      RedactionCategory.face => 20,
      _ => 10,
    };
    // Keep focus borders visible among tracks in the same category without
    // allowing a selected full-body effect to cover a face effect.
    return categoryLayer + (track.id == selectedTrackId ? 1 : 0);
  }
}

class _Region extends StatelessWidget {
  const _Region({
    required this.bounds,
    required this.style,
    required this.enabled,
    required this.focused,
    required this.blurStrength,
    required this.pixelSize,
    required this.pixelProgram,
  });

  final Rect bounds;
  final RedactionStyle style;
  final bool enabled;
  final bool focused;
  final double blurStrength;
  final double pixelSize;
  final ui.FragmentProgram? pixelProgram;

  @override
  Widget build(BuildContext context) {
    final filter = !enabled
        ? null
        : switch (style) {
            RedactionStyle.blur => ui.ImageFilter.blur(
              sigmaX: blurStrength.clamp(10, 50),
              sigmaY: blurStrength.clamp(10, 50),
              tileMode: TileMode.decal,
            ),
            RedactionStyle.pixelate => _pixelFilter(),
            RedactionStyle.blackout => null,
            RedactionStyle.flowers => null,
          };
    return Positioned.fromRect(
      rect: bounds,
      child: IgnorePointer(
        child: Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.none,
          children: [
            ClipRect(
              child: !enabled
                  ? const ColoredBox(color: Colors.transparent)
                  : style == RedactionStyle.flowers
                  ? const FlowerRedaction()
                  : filter == null
                  ? const ColoredBox(color: Colors.black)
                  : BackdropFilter(
                      filter: filter,
                      child: ColoredBox(
                        color:
                            style == RedactionStyle.pixelate &&
                                pixelProgram == null
                            ? Colors.black.withValues(alpha: .88)
                            : Colors.transparent,
                      ),
                    ),
            ),
            if (!enabled)
              DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFFFFB020).withValues(alpha: .08),
                  border: Border.all(color: const Color(0xFFFFB020), width: 2),
                ),
              ),
            if (!enabled)
              const Center(
                child: Icon(
                  Icons.add_box_outlined,
                  color: Color(0xFFFFB020),
                  size: 20,
                ),
              ),
            if (focused)
              DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: const [
                    BoxShadow(color: forest, spreadRadius: 1.5, blurRadius: 0),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  ui.ImageFilter _pixelFilter() {
    final program = pixelProgram;
    if (program == null || !ui.ImageFilter.isShaderFilterSupported) {
      return ui.ImageFilter.blur(sigmaX: .7, sigmaY: .7);
    }
    try {
      final shader = program.fragmentShader()
        ..setFloat(2, pixelSize.clamp(8, 48));
      return ui.ImageFilter.shader(shader);
    } catch (_) {
      return ui.ImageFilter.blur(sigmaX: .7, sigmaY: .7);
    }
  }
}
