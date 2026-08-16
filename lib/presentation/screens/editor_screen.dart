import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../domain/models.dart';
import '../../state/providers.dart';
import '../widgets/adaptive_ui.dart';
import '../widgets/batch_strip.dart';
import '../widgets/image_geometry.dart';
import '../widgets/privacy_loader.dart';
import '../widgets/redaction_style_picker.dart';
import '../widgets/sticker_redaction.dart';

class EditorScreen extends ConsumerStatefulWidget {
  const EditorScreen({super.key});
  @override
  ConsumerState<EditorScreen> createState() => _EditorState();
}

class _EditorState extends ConsumerState<EditorScreen> {
  final TransformationController _transformationController =
      TransformationController();
  EditorTool tool = EditorTool.select;
  RedactionStyle style = RedactionStyle.blackout;
  String? active;
  Offset? start;
  Offset? lastPoint;
  Rect? draftBounds;
  Rect? interactionBounds;
  Rect? resizeOrigin;
  List<Offset> stroke = [];
  double brush = 28;
  double areaScale = 100;
  bool pinchGesture = false;
  bool exporting = false;

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  Future<void> _discardImage() async {
    final batch = ref.read(batchProvider);
    final isBatch = batch.isBatch;
    final confirmed = await showAdaptiveActionSheet<bool>(
      context: context,
      title: isBatch ? 'Discard batch?' : 'Discard image?',
      message: isBatch
          ? 'These images and their unsaved privacy edits will be discarded.'
          : 'This image and its unsaved privacy edits will be discarded.',
      actions: [
        AdaptiveAction(
          label: isBatch ? 'Discard batch' : 'Discard image',
          value: true,
          destructive: true,
          icon: Icons.delete_outline_rounded,
        ),
      ],
      cancelLabel: 'Keep editing',
    );
    if (confirmed != true || !mounted) return;
    await ref.read(sessionProvider.notifier).clear();
    if (mounted) context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(sessionProvider);
    final batch = ref.watch(batchProvider);
    if (s == null) return const SizedBox();
    return Scaffold(
      appBar: adaptiveNavigationBar(
        context,
        title: const Text('Redact image'),
        actions: [
          AdaptiveIconButton(
            tooltip: batch.isBatch ? 'Discard batch' : 'Discard image',
            onPressed: exporting ? null : _discardImage,
            icon: Icon(
              adaptiveIcon(
                context,
                material: Icons.delete_outline_rounded,
                cupertino: CupertinoIcons.delete,
              ),
            ),
          ),
          AdaptiveIconButton(
            tooltip: 'Undo',
            onPressed: () => ref.read(sessionProvider.notifier).undo(),
            icon: Icon(
              adaptiveIcon(
                context,
                material: Icons.undo,
                cupertino: CupertinoIcons.arrow_uturn_left,
              ),
            ),
          ),
          AdaptiveIconButton(
            tooltip: 'Redo',
            onPressed: () => ref.read(sessionProvider.notifier).redo(),
            icon: Icon(
              adaptiveIcon(
                context,
                material: Icons.redo,
                cupertino: CupertinoIcons.arrow_uturn_right,
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              BatchStrip(
                onSelected: (_) => setState(() {
                  active = null;
                  draftBounds = null;
                  interactionBounds = null;
                  resizeOrigin = null;
                  areaScale = 100;
                  stroke = [];
                  _transformationController.value = Matrix4.identity();
                }),
              ),
              Expanded(
                child: Container(
                  color: Colors.black87,
                  child: LayoutBuilder(
                    builder: (context, c) {
                      final g = ImageGeometry(
                        Size(c.maxWidth, c.maxHeight),
                        Size(s.width.toDouble(), s.height.toDouble()),
                      );
                      final content = GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapUp: (d) => tool == EditorTool.eraser
                            ? ref
                                  .read(sessionProvider.notifier)
                                  .eraseNearest(g.toImage(d.localPosition))
                            : tool == EditorTool.select
                            ? _selectNearest(g, d.localPosition, s)
                            : null,
                        child: Stack(
                          children: [
                            Positioned(
                              left: g.origin.dx,
                              top: g.origin.dy,
                              width: g.displayed.width,
                              height: g.displayed.height,
                              child: Image.file(
                                File(s.sourcePath),
                                fit: BoxFit.fill,
                              ),
                            ),
                            for (final item in s.items.where((i) => i.selected))
                              _redaction(g, item),
                            if (draftBounds != null) _draftRectangle(g),
                            for (final bs in s.strokes) _strokePaint(g, bs),
                            if (stroke.isNotEmpty)
                              _strokePaint(
                                g,
                                BrushStroke(
                                  id: 'live',
                                  points: stroke,
                                  size: brush,
                                  style: style,
                                ),
                              ),
                          ],
                        ),
                      );
                      return Stack(
                        children: [
                          Positioned.fill(
                            child: InteractiveViewer(
                              transformationController:
                                  _transformationController,
                              // One finger edits. A second finger turns the
                              // same gesture into pan + pinch zoom.
                              panEnabled: pinchGesture,
                              scaleEnabled: true,
                              minScale: 1,
                              maxScale: 8,
                              boundaryMargin: const EdgeInsets.all(80),
                              clipBehavior: Clip.hardEdge,
                              onInteractionStart: (details) =>
                                  _interactionStart(g, details, s),
                              onInteractionUpdate: (details) =>
                                  _interactionUpdate(g, details, s),
                              onInteractionEnd: (_) => _interactionEnd(g, s),
                              child: SizedBox(
                                width: c.maxWidth,
                                height: c.maxHeight,
                                child: content,
                              ),
                            ),
                          ),
                          const Positioned(
                            top: 8,
                            right: 8,
                            child: _EditorPinchHint(),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
              _styles(),
              if (active != null && tool == EditorTool.select)
                _selectedAreaControls(s),
              _tools(),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: AdaptiveButton(
                  onPressed: exporting ? null : _export,
                  icon: Icon(
                    adaptiveIcon(
                      context,
                      material: Icons.visibility_outlined,
                      cupertino: CupertinoIcons.eye,
                    ),
                  ),
                  child: const Text('Preview safe copy'),
                ),
              ),
            ],
          ),
          Positioned.fill(
            child: IgnorePointer(
              ignoring: !exporting,
              child: AnimatedOpacity(
                opacity: exporting ? 1 : 0,
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: .5),
                  child: Center(
                    child: Container(
                      margin: const EdgeInsets.all(24),
                      padding: const EdgeInsets.fromLTRB(30, 28, 30, 30),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(30),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black26,
                            blurRadius: 32,
                            offset: Offset(0, 14),
                          ),
                        ],
                      ),
                      child: const PrivacyLoader(
                        label: 'Preparing your preview',
                        detail: 'Creating a quick privacy-safe preview',
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _export() async {
    setState(() => exporting = true);
    try {
      await ref.read(sessionProvider.notifier).preview();
      if (mounted) {
        setState(() => exporting = false);
        context.push('/export');
      }
    } catch (e) {
      if (mounted) {
        setState(() => exporting = false);
        showAdaptiveMessage(context, e.toString(), error: true);
      }
    }
  }

  Widget _styles() => Container(
    color: Colors.white,
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              const Text(
                'Style',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: RedactionStylePicker(
                  value: style,
                  onChanged: (value) {
                    setState(() => style = value);
                    final selectedId = active;
                    if (selectedId != null && tool == EditorTool.select) {
                      ref
                          .read(sessionProvider.notifier)
                          .setStyle(selectedId, value);
                    } else {
                      ref.read(sessionProvider.notifier).setAllStyle(value);
                    }
                  },
                ),
              ),
            ],
          ),
        ),
        if (tool == EditorTool.brush)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 2, 12, 0),
            child: Row(
              children: [
                const Icon(Icons.brush_outlined, size: 18),
                const SizedBox(width: 8),
                Text('Brush size · ${brush.round()} px'),
                const SizedBox(width: 8),
                Expanded(
                  child: AdaptiveSlider(
                    value: brush,
                    min: 8,
                    max: 100,
                    onChanged: (v) => setState(() => brush = v),
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
  Widget _tools() => Container(
    color: Colors.white,
    height: 72,
    child: ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      children: [
        _tool(EditorTool.select, Icons.near_me_outlined, 'Select'),
        _tool(EditorTool.rectangle, Icons.crop_square, 'Rectangle'),
        _tool(EditorTool.brush, Icons.brush_outlined, 'Brush'),
        _tool(EditorTool.eraser, Icons.auto_fix_normal, 'Eraser'),
        _action(
          Icons.restart_alt,
          'Reset',
          () => ref.read(sessionProvider.notifier).resetEdits(),
        ),
      ],
    ),
  );
  Widget _tool(EditorTool t, IconData i, String l) => _action(i, l, () {
    setState(() {
      tool = t;
      if (t != EditorTool.select) _clearSelection();
    });
    HapticFeedback.selectionClick();
  }, selected: tool == t);
  Widget _action(
    IconData i,
    String l,
    VoidCallback tap, {
    bool selected = false,
  }) {
    final content = Container(
      width: 76,
      margin: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: selected ? mint : null,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(i, color: selected ? forest : null),
          Text(l, style: const TextStyle(fontSize: 11)),
        ],
      ),
    );
    if (usesCupertinoUi(context)) {
      return CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: const Size(76, 64),
        onPressed: tap,
        child: content,
      );
    }
    return InkWell(
      onTap: tap,
      borderRadius: BorderRadius.circular(12),
      child: content,
    );
  }

  void _start(ImageGeometry g, Offset local, ImageSession s) {
    final p = g.toImage(local);
    lastPoint = p;
    if (tool == EditorTool.rectangle) {
      start = p;
      setState(() => draftBounds = Rect.fromPoints(p, p));
    } else if (tool == EditorTool.brush) {
      stroke = [p];
      setState(() {});
    } else if (tool == EditorTool.select) {
      final hit = hitTestRedactionItems(
        s.items.where((item) => item.selected),
        p,
        displayScale:
            g.factor * _transformationController.value.getMaxScaleOnAxis(),
      );
      setState(() {
        active = hit?.id;
        interactionBounds = hit?.bounds;
        resizeOrigin = hit?.bounds;
        areaScale = 100;
        if (hit != null) style = hit.style;
      });
    }
  }

  void _update(ImageGeometry g, Offset local, ImageSession s) {
    final p = g.toImage(local);
    if (tool == EditorTool.brush) {
      setState(() => stroke.add(p));
    } else if (tool == EditorTool.rectangle && start != null) {
      setState(() => draftBounds = g.clamp(Rect.fromPoints(start!, p)));
    } else if (tool == EditorTool.select && interactionBounds != null) {
      final previous = lastPoint;
      if (previous != null) {
        setState(
          () => interactionBounds = _clampShift(
            interactionBounds!,
            p - previous,
            s,
          ),
        );
      }
    }
    lastPoint = p;
  }

  void _end(ImageGeometry g, ImageSession s) {
    String? createdRectangleId;
    Rect? createdRectangleBounds;
    if (tool == EditorTool.rectangle && start != null) {
      final box = draftBounds ?? Rect.fromPoints(start!, lastPoint ?? start!);
      if (box.width >= 12 && box.height >= 12) {
        createdRectangleBounds = box;
        createdRectangleId = ref
            .read(sessionProvider.notifier)
            .addRectangle(box, style);
      }
    } else if (tool == EditorTool.brush && stroke.length > 1) {
      ref
          .read(sessionProvider.notifier)
          .addStroke(
            BrushStroke(
              id: 'stroke_${DateTime.now().microsecondsSinceEpoch}',
              points: [...stroke],
              size: brush,
              style: style,
            ),
          );
    } else if (tool == EditorTool.select) {
      _commitInteraction();
    }
    setState(() {
      start = null;
      lastPoint = null;
      draftBounds = null;
      stroke = [];
      if (createdRectangleId != null) {
        active = createdRectangleId;
        tool = EditorTool.select;
        interactionBounds = createdRectangleBounds;
        resizeOrigin = createdRectangleBounds;
        areaScale = 100;
      }
    });
    HapticFeedback.lightImpact();
  }

  Widget _redaction(ImageGeometry g, RedactionItem item) {
    final bounds = active == item.id && interactionBounds != null
        ? interactionBounds!
        : item.bounds;
    final r = g.toLocalRect(bounds);
    final showHandles = active == item.id && tool == EditorTool.select;
    return Positioned.fromRect(
      rect: r,
      child: IgnorePointer(
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_isSticker(item.style))
              StickerRedaction(
                style: item.style,
                border: Border.all(
                  color: showHandles ? Colors.amber : Colors.white,
                  width: showHandles ? 3 : 2,
                ),
              )
            else
              DecoratedBox(
                decoration: BoxDecoration(
                  color: switch (item.style) {
                    RedactionStyle.blackout => Colors.black,
                    RedactionStyle.blur => forest.withValues(alpha: .62),
                    RedactionStyle.pixelate => Colors.blueGrey.withValues(
                      alpha: .75,
                    ),
                    RedactionStyle.emoji => Colors.transparent,
                    RedactionStyle.flowers => Colors.transparent,
                  },
                  border: Border.all(
                    color: showHandles ? Colors.amber : Colors.white,
                    width: showHandles ? 3 : 2,
                  ),
                ),
              ),
            if (showHandles) ...[const _MoveHandle()],
          ],
        ),
      ),
    );
  }

  Widget _draftRectangle(ImageGeometry g) {
    final r = g.toLocalRect(draftBounds!);
    return Positioned.fromRect(
      rect: r,
      child: IgnorePointer(
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_isSticker(style))
              StickerRedaction(
                style: style,
                border: Border.all(color: Colors.amber, width: 2.5),
              )
            else
              DecoratedBox(
                decoration: BoxDecoration(
                  color: switch (style) {
                    RedactionStyle.blur => forest.withValues(alpha: .28),
                    RedactionStyle.pixelate => Colors.blueGrey.withValues(
                      alpha: .3,
                    ),
                    RedactionStyle.blackout => Colors.black.withValues(
                      alpha: .42,
                    ),
                    RedactionStyle.emoji => Colors.transparent,
                    RedactionStyle.flowers => Colors.transparent,
                  },
                  border: Border.all(color: Colors.amber, width: 2.5),
                ),
              ),
            const Center(
              child: Icon(Icons.open_in_full, color: Colors.white70, size: 18),
            ),
          ],
        ),
      ),
    );
  }

  Widget _strokePaint(ImageGeometry g, BrushStroke s) =>
      CustomPaint(size: Size.infinite, painter: _StrokePainter(g, s));

  Widget _selectedAreaControls(ImageSession session) {
    final item = session.items.where((item) => item.id == active).firstOrNull;
    if (item == null) return const SizedBox.shrink();
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        decoration: BoxDecoration(
          color: mint,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFB2D8CA)),
        ),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.open_with_rounded, color: forest, size: 19),
                const SizedBox(width: 7),
                const Expanded(
                  child: Text(
                    'Drag the mask to move it',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Delete mask',
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    ref.read(sessionProvider.notifier).deleteItem(item.id);
                    setState(_clearSelection);
                  },
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                ),
              ],
            ),
            Row(
              children: [
                const Icon(Icons.photo_size_select_large_rounded, size: 19),
                const SizedBox(width: 7),
                const Text(
                  'Mask size',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
                ),
                Expanded(
                  child: AdaptiveSlider(
                    value: areaScale,
                    min: 40,
                    max: 300,
                    onChanged: (value) => _previewScale(value, item, session),
                    onChangeEnd: (_) => _commitInteraction(),
                  ),
                ),
                SizedBox(
                  width: 44,
                  child: Text(
                    '${areaScale.round()}%',
                    textAlign: TextAlign.end,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _previewScale(double value, RedactionItem item, ImageSession session) {
    resizeOrigin ??= interactionBounds ?? item.bounds;
    final origin = resizeOrigin!;
    final factor = value / 100;
    final width = (origin.width * factor)
        .clamp(12, session.width.toDouble())
        .toDouble();
    final height = (origin.height * factor)
        .clamp(12, session.height.toDouble())
        .toDouble();
    final imageRect = Rect.fromLTWH(
      0,
      0,
      session.width.toDouble(),
      session.height.toDouble(),
    );
    setState(() {
      areaScale = value;
      interactionBounds = Rect.fromCenter(
        center: origin.center,
        width: width,
        height: height,
      ).intersect(imageRect);
    });
  }

  void _interactionStart(
    ImageGeometry geometry,
    ScaleStartDetails details,
    ImageSession session,
  ) {
    pinchGesture = details.pointerCount > 1;
    if (pinchGesture) {
      _cancelGesture();
      return;
    }
    _start(
      geometry,
      _transformationController.toScene(details.localFocalPoint),
      session,
    );
  }

  void _interactionUpdate(
    ImageGeometry geometry,
    ScaleUpdateDetails details,
    ImageSession session,
  ) {
    if (details.pointerCount > 1 || details.scale != 1) {
      if (!pinchGesture) {
        pinchGesture = true;
        _cancelGesture();
      }
      return;
    }
    if (pinchGesture) return;
    _update(
      geometry,
      _transformationController.toScene(details.localFocalPoint),
      session,
    );
  }

  void _interactionEnd(ImageGeometry geometry, ImageSession session) {
    if (pinchGesture) {
      pinchGesture = false;
      _cancelGesture();
      return;
    }
    _end(geometry, session);
  }

  void _selectNearest(
    ImageGeometry geometry,
    Offset local,
    ImageSession session,
  ) {
    final item = hitTestRedactionItems(
      session.items.where((item) => item.selected),
      geometry.toImage(local),
      displayScale:
          geometry.factor * _transformationController.value.getMaxScaleOnAxis(),
    );
    setState(() {
      active = item?.id;
      interactionBounds = item?.bounds;
      resizeOrigin = item?.bounds;
      areaScale = 100;
      if (item != null) style = item.style;
    });
  }

  Rect _clampShift(Rect bounds, Offset delta, ImageSession session) {
    final dx = delta.dx.clamp(-bounds.left, session.width - bounds.right);
    final dy = delta.dy.clamp(-bounds.top, session.height - bounds.bottom);
    return bounds.shift(Offset(dx, dy));
  }

  void _commitInteraction() {
    final id = active;
    final bounds = interactionBounds;
    if (id == null || bounds == null) return;
    ref.read(sessionProvider.notifier).updateBounds(id, bounds);
    if (mounted) {
      setState(() {
        resizeOrigin = bounds;
        areaScale = 100;
      });
    }
  }

  void _cancelGesture() {
    if (!mounted) return;
    setState(() {
      start = null;
      lastPoint = null;
      draftBounds = null;
      stroke = [];
    });
  }

  void _clearSelection() {
    active = null;
    interactionBounds = null;
    resizeOrigin = null;
    areaScale = 100;
  }
}

class _StrokePainter extends CustomPainter {
  _StrokePainter(this.g, this.s);
  final ImageGeometry g;
  final BrushStroke s;
  @override
  void paint(Canvas c, Size z) {
    if (s.points.isEmpty) return;
    final p = Paint()
      ..color = switch (s.style) {
        RedactionStyle.blur => forest.withValues(alpha: .7),
        RedactionStyle.pixelate => Colors.blueGrey,
        RedactionStyle.blackout => Colors.black,
        RedactionStyle.emoji => const Color(0xFFFFC928),
        RedactionStyle.flowers => const Color(0xFFF7A9C4),
      }
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = s.size * g.factor
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..moveTo(
        g.origin.dx + s.points.first.dx * g.factor,
        g.origin.dy + s.points.first.dy * g.factor,
      );
    for (final x in s.points.skip(1)) {
      path.lineTo(g.origin.dx + x.dx * g.factor, g.origin.dy + x.dy * g.factor);
    }
    c.drawPath(path, p);
  }

  @override
  bool shouldRepaint(covariant _StrokePainter old) => old.s != s;
}

bool _isSticker(RedactionStyle style) =>
    style == RedactionStyle.emoji || style == RedactionStyle.flowers;

class _MoveHandle extends StatelessWidget {
  const _MoveHandle();

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .94),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.black87, width: 2),
        boxShadow: const [
          BoxShadow(color: Colors.black38, blurRadius: 4, offset: Offset(0, 1)),
        ],
      ),
      child: const Icon(Icons.open_with, size: 20, color: Colors.black87),
    ),
  );
}

class _EditorPinchHint extends StatelessWidget {
  const _EditorPinchHint();

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Pinch to zoom',
    child: IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xD91B211F),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white24),
        ),
        child: const SizedBox.square(
          dimension: 40,
          child: Icon(Icons.pinch_rounded, size: 21, color: Colors.white),
        ),
      ),
    ),
  );
}
