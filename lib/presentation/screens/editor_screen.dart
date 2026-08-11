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
import '../widgets/flower_redaction.dart';
import '../widgets/image_geometry.dart';
import '../widgets/new_image_action.dart';
import '../widgets/privacy_loader.dart';

class EditorScreen extends ConsumerStatefulWidget {
  const EditorScreen({super.key});
  @override
  ConsumerState<EditorScreen> createState() => _EditorState();
}

class _EditorState extends ConsumerState<EditorScreen> {
  EditorTool tool = EditorTool.select;
  RedactionStyle style = RedactionStyle.blackout;
  String? active;
  Offset? start;
  Offset? lastPoint;
  Rect? draftBounds;
  Rect? interactionBounds;
  _RectHandle activeHandle = _RectHandle.move;
  List<Offset> stroke = [];
  double brush = 28;
  bool exporting = false;

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(sessionProvider);
    if (s == null) return const SizedBox();
    return Scaffold(
      appBar: adaptiveNavigationBar(
        context,
        title: const Text('Redact image'),
        actions: [
          NewImageAction(enabled: !exporting),
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
                  stroke = [];
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
                        onPanStart: (d) => _start(g, d.localPosition, s),
                        onPanUpdate: (d) => _update(g, d.localPosition, s),
                        onPanEnd: (_) => _end(g, s),
                        onTapUp: (d) => tool == EditorTool.eraser
                            ? ref
                                  .read(sessionProvider.notifier)
                                  .eraseNearest(g.toImage(d.localPosition))
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
                      return tool == EditorTool.zoom
                          ? InteractiveViewer(
                              minScale: .5,
                              maxScale: 6,
                              child: SizedBox(
                                width: c.maxWidth,
                                height: c.maxHeight,
                                child: content,
                              ),
                            )
                          : content;
                    },
                  ),
                ),
              ),
              _styles(),
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
                child: AdaptiveSegmentedControl<RedactionStyle>(
                  value: style,
                  children: {
                    for (final value in RedactionStyle.values)
                      value: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Text(
                          value.name[0].toUpperCase() + value.name.substring(1),
                        ),
                      ),
                  },
                  onChanged: (value) {
                    setState(() => style = value);
                    ref.read(sessionProvider.notifier).setAllStyle(value);
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
        _tool(EditorTool.zoom, Icons.zoom_in, 'Zoom'),
        _action(
          Icons.restart_alt,
          'Reset',
          () => ref.read(sessionProvider.notifier).resetEdits(),
        ),
      ],
    ),
  );
  Widget _tool(EditorTool t, IconData i, String l) => _action(i, l, () {
    setState(() => tool = t);
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
    }
  }

  void _update(ImageGeometry g, Offset local, ImageSession s) {
    final p = g.toImage(local);
    lastPoint = p;
    if (tool == EditorTool.brush) {
      setState(() => stroke.add(p));
    } else if (tool == EditorTool.rectangle && start != null) {
      setState(() => draftBounds = g.clamp(Rect.fromPoints(start!, p)));
    }
  }

  void _end(ImageGeometry g, ImageSession s) {
    String? createdRectangleId;
    if (tool == EditorTool.rectangle && start != null) {
      final box = draftBounds ?? Rect.fromPoints(start!, lastPoint ?? start!);
      if (box.width >= 12 && box.height >= 12) {
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
    }
    setState(() {
      start = null;
      lastPoint = null;
      draftBounds = null;
      stroke = [];
      if (createdRectangleId != null) {
        active = createdRectangleId;
        tool = EditorTool.select;
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
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: tool == EditorTool.select
            ? () => setState(() => active = item.id)
            : null,
        onPanStart: tool == EditorTool.select
            ? (details) =>
                  _startItemGesture(item, details.localPosition, r.size)
            : null,
        onPanUpdate: tool == EditorTool.select
            ? (details) => _updateItemGesture(g, details.delta)
            : null,
        onPanEnd: tool == EditorTool.select ? (_) => _endItemGesture() : null,
        onLongPress: () => _itemMenu(item),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (item.style == RedactionStyle.flowers)
              FlowerRedaction(
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
                    RedactionStyle.flowers => Colors.transparent,
                  },
                  border: Border.all(
                    color: showHandles ? Colors.amber : Colors.white,
                    width: showHandles ? 3 : 2,
                  ),
                ),
              ),
            if (showHandles) ...[
              const _CornerHandle(alignment: Alignment.topLeft),
              const _CornerHandle(alignment: Alignment.topRight),
              const _CornerHandle(alignment: Alignment.bottomLeft),
              const _CornerHandle(alignment: Alignment.bottomRight),
              const _MoveHandle(),
            ],
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
            if (style == RedactionStyle.flowers)
              FlowerRedaction(
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

  void _startItemGesture(RedactionItem item, Offset local, Size size) {
    const hit = 30.0;
    activeHandle = switch ((local.dx, local.dy)) {
      (final x, final y) when x <= hit && y <= hit => _RectHandle.topLeft,
      (final x, final y) when x >= size.width - hit && y <= hit =>
        _RectHandle.topRight,
      (final x, final y) when x <= hit && y >= size.height - hit =>
        _RectHandle.bottomLeft,
      (final x, final y) when x >= size.width - hit && y >= size.height - hit =>
        _RectHandle.bottomRight,
      _ => _RectHandle.move,
    };
    setState(() {
      active = item.id;
      interactionBounds = item.bounds;
    });
    HapticFeedback.selectionClick();
  }

  void _updateItemGesture(ImageGeometry g, Offset screenDelta) {
    final current = interactionBounds;
    if (current == null) return;
    final delta = screenDelta / g.factor;
    const minimum = 12.0;
    Rect next;
    switch (activeHandle) {
      case _RectHandle.move:
        final dx = delta.dx.clamp(
          -current.left,
          g.imageSize.width - current.right,
        );
        final dy = delta.dy.clamp(
          -current.top,
          g.imageSize.height - current.bottom,
        );
        next = current.shift(Offset(dx, dy));
      case _RectHandle.topLeft:
        next = Rect.fromLTRB(
          (current.left + delta.dx).clamp(0, current.right - minimum),
          (current.top + delta.dy).clamp(0, current.bottom - minimum),
          current.right,
          current.bottom,
        );
      case _RectHandle.topRight:
        next = Rect.fromLTRB(
          current.left,
          (current.top + delta.dy).clamp(0, current.bottom - minimum),
          (current.right + delta.dx).clamp(
            current.left + minimum,
            g.imageSize.width,
          ),
          current.bottom,
        );
      case _RectHandle.bottomLeft:
        next = Rect.fromLTRB(
          (current.left + delta.dx).clamp(0, current.right - minimum),
          current.top,
          current.right,
          (current.bottom + delta.dy).clamp(
            current.top + minimum,
            g.imageSize.height,
          ),
        );
      case _RectHandle.bottomRight:
        next = Rect.fromLTRB(
          current.left,
          current.top,
          (current.right + delta.dx).clamp(
            current.left + minimum,
            g.imageSize.width,
          ),
          (current.bottom + delta.dy).clamp(
            current.top + minimum,
            g.imageSize.height,
          ),
        );
    }
    setState(() => interactionBounds = next);
  }

  void _endItemGesture() {
    final id = active;
    final bounds = interactionBounds;
    if (id != null && bounds != null) {
      ref.read(sessionProvider.notifier).updateBounds(id, bounds);
    }
    setState(() => interactionBounds = null);
    HapticFeedback.lightImpact();
  }

  Widget _strokePaint(ImageGeometry g, BrushStroke s) =>
      CustomPaint(size: Size.infinite, painter: _StrokePainter(g, s));
  Future<void> _itemMenu(RedactionItem item) async {
    final choice = await showAdaptiveActionSheet<_ItemMenuChoice>(
      context: context,
      title: 'Rectangle options',
      actions: const [
        AdaptiveAction(
          label: 'Use blur',
          value: _ItemMenuChoice.blur,
          icon: Icons.blur_on_outlined,
        ),
        AdaptiveAction(
          label: 'Use pixelate',
          value: _ItemMenuChoice.pixelate,
          icon: Icons.grid_4x4_outlined,
        ),
        AdaptiveAction(
          label: 'Use blackout',
          value: _ItemMenuChoice.blackout,
          icon: Icons.crop_square,
        ),
        AdaptiveAction(
          label: 'Use flowers',
          value: _ItemMenuChoice.flowers,
          icon: Icons.local_florist_outlined,
        ),
        AdaptiveAction(
          label: 'Delete rectangle',
          value: _ItemMenuChoice.delete,
          icon: Icons.delete_outline,
          destructive: true,
        ),
      ],
    );
    if (!mounted || choice == null) return;
    final notifier = ref.read(sessionProvider.notifier);
    switch (choice) {
      case _ItemMenuChoice.blur:
        notifier.setStyle(item.id, RedactionStyle.blur);
      case _ItemMenuChoice.pixelate:
        notifier.setStyle(item.id, RedactionStyle.pixelate);
      case _ItemMenuChoice.blackout:
        notifier.setStyle(item.id, RedactionStyle.blackout);
      case _ItemMenuChoice.flowers:
        notifier.setStyle(item.id, RedactionStyle.flowers);
      case _ItemMenuChoice.delete:
        notifier.deleteItem(item.id);
    }
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

enum _RectHandle { move, topLeft, topRight, bottomLeft, bottomRight }

enum _ItemMenuChoice { blur, pixelate, blackout, flowers, delete }

class _CornerHandle extends StatelessWidget {
  const _CornerHandle({required this.alignment});
  final Alignment alignment;

  @override
  Widget build(BuildContext context) => Align(
    alignment: alignment,
    child: Container(
      width: 18,
      height: 18,
      margin: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.black87, width: 2),
        boxShadow: const [
          BoxShadow(color: Colors.black38, blurRadius: 3, offset: Offset(0, 1)),
        ],
      ),
    ),
  );
}

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
