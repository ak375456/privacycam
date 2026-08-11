import 'dart:io';
import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../domain/models.dart';
import '../../state/pdf_providers.dart';
import '../widgets/adaptive_ui.dart';
import '../widgets/image_geometry.dart';
import '../widgets/redaction_style_picker.dart';
import '../widgets/sticker_redaction.dart';

class PdfEditorScreen extends ConsumerStatefulWidget {
  const PdfEditorScreen({super.key});

  @override
  ConsumerState<PdfEditorScreen> createState() => _PdfEditorScreenState();
}

class _PdfEditorScreenState extends ConsumerState<PdfEditorScreen> {
  final TransformationController _transformationController =
      TransformationController();
  final GlobalKey _canvasViewportKey = GlobalKey();

  EditorTool tool = EditorTool.select;
  RedactionStyle style = RedactionStyle.blackout;
  String? activeId;
  Rect? interactionBounds;
  Rect? resizeOrigin;
  Offset? gestureStart;
  Offset? lastImagePoint;
  Rect? draftBounds;
  List<Offset> stroke = [];
  double brushSize = 30;
  double areaScale = 100;
  Offset? brushTouchLocal;
  Offset? eraserTouchLocal;
  bool pinchGesture = false;
  bool eraserGestureHasHistory = false;

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final document = ref.watch(pdfSessionProvider);
    final page = document?.currentPage;
    if (document == null || page == null) {
      return const Scaffold(body: Center(child: Text('No PDF is open.')));
    }
    final image = page.image;
    return Scaffold(
      appBar: adaptiveNavigationBar(
        context,
        title: const Text('Redact PDF'),
        actions: [
          AdaptiveIconButton(
            tooltip: 'Undo',
            onPressed: () => ref.read(pdfSessionProvider.notifier).undo(),
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
            onPressed: () => ref.read(pdfSessionProvider.notifier).redo(),
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
      body: SafeArea(
        child: Column(
          children: [
            _EditorPageStrip(
              count: document.pageCount,
              current: document.currentPageIndex,
              onSelected: (index) {
                ref.read(pdfSessionProvider.notifier).setCurrentPage(index);
                _resetZoom();
                setState(_clearSelection);
              },
            ),
            Expanded(
              child: Container(
                color: Colors.black87,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final geometry = ImageGeometry(
                      Size(constraints.maxWidth, constraints.maxHeight),
                      Size(image.width.toDouble(), image.height.toDouble()),
                    );
                    final content = Stack(
                      children: [
                        Positioned(
                          left: geometry.origin.dx,
                          top: geometry.origin.dy,
                          width: geometry.displayed.width,
                          height: geometry.displayed.height,
                          child: Image.file(
                            File(image.sourcePath),
                            fit: BoxFit.fill,
                          ),
                        ),
                        for (final item in image.items.where(
                          (item) => item.selected,
                        ))
                          _area(geometry, item),
                        if (draftBounds != null)
                          _draftArea(geometry, draftBounds!),
                        for (final savedStroke in image.strokes)
                          _strokeOverlay(geometry, savedStroke),
                        if (stroke.isNotEmpty)
                          _strokeOverlay(
                            geometry,
                            BrushStroke(
                              id: 'live',
                              points: stroke,
                              size: brushSize,
                              style: style,
                            ),
                          ),
                      ],
                    );
                    final canvas = GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (details) => _tapDown(details.globalPosition),
                      onTapUp: (details) =>
                          _tap(geometry, details.localPosition, image),
                      child: content,
                    );
                    return Stack(
                      key: _canvasViewportKey,
                      children: [
                        Positioned.fill(
                          child: InteractiveViewer(
                            transformationController: _transformationController,
                            // A single finger stays dedicated to the active
                            // editing tool. Once a second pointer joins, the
                            // same gesture can pan as well as pinch-zoom.
                            panEnabled: pinchGesture,
                            scaleEnabled: true,
                            minScale: 1,
                            maxScale: 8,
                            boundaryMargin: const EdgeInsets.all(80),
                            clipBehavior: Clip.hardEdge,
                            onInteractionStart: (details) =>
                                _interactionStart(geometry, details, image),
                            onInteractionUpdate: (details) =>
                                _interactionUpdate(geometry, details),
                            onInteractionEnd: (_) => _interactionEnd(geometry),
                            child: SizedBox(
                              width: constraints.maxWidth,
                              height: constraints.maxHeight,
                              child: canvas,
                            ),
                          ),
                        ),
                        if (brushTouchLocal != null)
                          _brushMagnifier(
                            brushTouchLocal!,
                            Size(constraints.maxWidth, constraints.maxHeight),
                          ),
                        if (eraserTouchLocal != null)
                          _eraserCursor(eraserTouchLocal!),
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Semantics(
                            label: 'Pinch to zoom',
                            child: IgnorePointer(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: const Color(0xD91B211F),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white24),
                                ),
                                child: const SizedBox.square(
                                  dimension: 38,
                                  child: Icon(
                                    Icons.pinch_rounded,
                                    size: 20,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: activeId != null
                    ? 360
                    : tool == EditorTool.brush || tool == EditorTool.eraser
                    ? 300
                    : 245,
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
                child: Column(
                  children: [
                    _styleControl(),
                    const SizedBox(height: 8),
                    _toolControl(),
                    if (tool == EditorTool.brush) ...[
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          const Icon(Icons.brush_outlined, color: forest),
                          Expanded(
                            child: AdaptiveSlider(
                              value: brushSize,
                              min: 8,
                              max: 120,
                              onChanged: (value) =>
                                  setState(() => brushSize = value),
                            ),
                          ),
                          Text('${brushSize.round()} px'),
                        ],
                      ),
                      const Text(
                        'Drag to paint. The magnifier shows the exact point below your finger.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                    ],
                    if (tool == EditorTool.eraser) ...[
                      const SizedBox(height: 7),
                      const _ToolHint(
                        icon: Icons.auto_fix_off_outlined,
                        text:
                            'Drag across a brush line to erase only the touched part. Boxes are removed as a whole.',
                      ),
                    ],
                    if (activeId != null && tool == EditorTool.select) ...[
                      const SizedBox(height: 8),
                      _selectedAreaControls(image),
                    ],
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: AdaptiveButton(
                        onPressed: () => context.push('/pdf/export'),
                        icon: const Icon(Icons.picture_as_pdf_outlined),
                        child: Text(
                          'Preview safe PDF · ${document.pageCount} pages',
                        ),
                      ),
                    ),
                    const SizedBox(height: 7),
                    const Text(
                      'The export is flattened. Hidden text cannot be selected or uncovered later.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _styleControl() => RedactionStylePicker(
    value: style,
    onChanged: (value) {
      setState(() => style = value);
      ref.read(pdfSessionProvider.notifier).setAllStyle(value);
    },
  );

  Widget _toolControl() => Wrap(
    alignment: WrapAlignment.center,
    spacing: 3,
    children: [
      _toolButton(EditorTool.select, Icons.near_me_outlined, 'Select'),
      _toolButton(EditorTool.rectangle, Icons.crop_square, 'Rectangle'),
      _toolButton(EditorTool.brush, Icons.brush_outlined, 'Brush'),
      _toolButton(EditorTool.eraser, Icons.auto_fix_off_outlined, 'Eraser'),
    ],
  );

  Widget _toolButton(EditorTool value, IconData icon, String label) =>
      ChoiceChip(
        avatar: Icon(icon, size: 18),
        label: Text(label),
        selected: tool == value,
        onSelected: (_) => setState(() {
          tool = value;
          _clearSelection();
        }),
      );

  Widget _selectedAreaControls(ImageSession image) {
    final item = image.items.where((item) => item.id == activeId).firstOrNull;
    if (item == null) return const SizedBox();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: mint,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFB2D8CA)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${item.category.label} selected',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                tooltip: 'Delete area',
                onPressed: () {
                  ref.read(pdfSessionProvider.notifier).deleteItem(item.id);
                  setState(_clearSelection);
                },
                icon: const Icon(Icons.delete_outline, color: Colors.red),
              ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _nudge(Icons.arrow_left, const Offset(-3, 0), item, image),
              _nudge(Icons.arrow_upward, const Offset(0, -3), item, image),
              _nudge(Icons.arrow_downward, const Offset(0, 3), item, image),
              _nudge(Icons.arrow_right, const Offset(3, 0), item, image),
            ],
          ),
          Row(
            children: [
              const Text('Area size'),
              Expanded(
                child: AdaptiveSlider(
                  value: areaScale,
                  min: 50,
                  max: 200,
                  onChanged: (value) => _previewScale(value, item, image),
                  onChangeEnd: (_) => _commitInteraction(),
                ),
              ),
              Text('${areaScale.round()}%'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _nudge(
    IconData icon,
    Offset delta,
    RedactionItem item,
    ImageSession image,
  ) => IconButton(
    onPressed: () {
      final next = _clampShift(item.bounds, delta, image);
      ref.read(pdfSessionProvider.notifier).updateBounds(item.id, next);
    },
    icon: Icon(icon, color: forest),
  );

  void _previewScale(double value, RedactionItem item, ImageSession image) {
    resizeOrigin ??= item.bounds;
    final origin = resizeOrigin!;
    final factor = value / 100;
    final center = origin.center;
    final width = (origin.width * factor)
        .clamp(12, image.width.toDouble())
        .toDouble();
    final height = (origin.height * factor)
        .clamp(12, image.height.toDouble())
        .toDouble();
    setState(() {
      areaScale = value;
      interactionBounds =
          Rect.fromCenter(
            center: center,
            width: width,
            height: height,
          ).intersect(
            Rect.fromLTWH(
              0,
              0,
              image.width.toDouble(),
              image.height.toDouble(),
            ),
          );
    });
  }

  void _panStart(
    ImageGeometry geometry,
    Offset scenePoint,
    Offset viewportPoint,
    ImageSession image,
  ) {
    final point = geometry.toImage(scenePoint);
    lastImagePoint = point;
    switch (tool) {
      case EditorTool.rectangle:
        setState(() {
          gestureStart = point;
          draftBounds = Rect.fromPoints(point, point);
        });
      case EditorTool.brush:
        setState(() {
          stroke = [point];
          brushTouchLocal = viewportPoint;
        });
      case EditorTool.select:
        final hit = image.items
            .where((item) => item.selected && item.bounds.contains(point))
            .lastOrNull;
        if (hit != null) {
          setState(() {
            activeId = hit.id;
            interactionBounds = hit.bounds;
            resizeOrigin = hit.bounds;
            areaScale = 100;
          });
        }
      case EditorTool.eraser:
        _erase(point, geometry.factor);
        setState(() => eraserTouchLocal = viewportPoint);
      case EditorTool.zoom:
        break;
    }
  }

  void _panUpdate(
    ImageGeometry geometry,
    Offset scenePoint,
    Offset viewportPoint,
  ) {
    final point = geometry.toImage(scenePoint);
    switch (tool) {
      case EditorTool.rectangle:
        final first = gestureStart;
        if (first != null) {
          setState(
            () => draftBounds = geometry.clamp(Rect.fromPoints(first, point)),
          );
        }
      case EditorTool.brush:
        setState(() {
          stroke = [...stroke, point];
          brushTouchLocal = viewportPoint;
        });
      case EditorTool.select:
        if (activeId != null &&
            interactionBounds != null &&
            lastImagePoint != null) {
          final image = ref.read(pdfSessionProvider)!.currentPage!.image;
          final delta = point - lastImagePoint!;
          setState(
            () => interactionBounds = _clampShift(
              interactionBounds!,
              delta,
              image,
            ),
          );
        }
      case EditorTool.eraser:
        _erase(point, geometry.factor);
        setState(() => eraserTouchLocal = viewportPoint);
      case EditorTool.zoom:
        break;
    }
    lastImagePoint = point;
  }

  void _panEnd(ImageGeometry geometry) {
    switch (tool) {
      case EditorTool.rectangle:
        final bounds = draftBounds;
        if (bounds != null && bounds.width >= 8 && bounds.height >= 8) {
          final id = ref
              .read(pdfSessionProvider.notifier)
              .addRectangle(bounds, style);
          setState(() {
            activeId = id;
            interactionBounds = bounds;
          });
        }
      case EditorTool.brush:
        if (stroke.isNotEmpty) {
          final points = stroke.length == 1
              ? [stroke.first, stroke.first + const Offset(.01, .01)]
              : stroke;
          ref
              .read(pdfSessionProvider.notifier)
              .addStroke(
                BrushStroke(
                  id: 'pdf_stroke_${DateTime.now().microsecondsSinceEpoch}',
                  points: points,
                  size: brushSize,
                  style: style,
                ),
              );
        }
      case EditorTool.select:
        _commitInteraction();
      case EditorTool.eraser || EditorTool.zoom:
        break;
    }
    setState(() {
      gestureStart = null;
      lastImagePoint = null;
      draftBounds = null;
      stroke = [];
      brushTouchLocal = null;
      eraserTouchLocal = null;
      eraserGestureHasHistory = false;
    });
  }

  void _interactionStart(
    ImageGeometry geometry,
    ScaleStartDetails details,
    ImageSession image,
  ) {
    pinchGesture = details.pointerCount > 1;
    eraserGestureHasHistory = false;
    if (pinchGesture) {
      _cancelGesture();
      return;
    }
    _panStart(
      geometry,
      _transformationController.toScene(details.localFocalPoint),
      details.localFocalPoint,
      image,
    );
  }

  void _interactionUpdate(ImageGeometry geometry, ScaleUpdateDetails details) {
    if (details.pointerCount > 1 || details.scale != 1) {
      if (!pinchGesture) {
        pinchGesture = true;
        _cancelGesture();
      }
      return;
    }
    if (pinchGesture) return;
    _panUpdate(
      geometry,
      _transformationController.toScene(details.localFocalPoint),
      details.localFocalPoint,
    );
  }

  void _interactionEnd(ImageGeometry geometry) {
    if (pinchGesture) {
      pinchGesture = false;
      _cancelGesture();
      return;
    }
    _panEnd(geometry);
  }

  void _tap(ImageGeometry geometry, Offset local, ImageSession image) {
    final point = geometry.toImage(local);
    if (tool == EditorTool.eraser) {
      eraserGestureHasHistory = false;
      _erase(point, geometry.factor);
      setState(() => eraserTouchLocal = null);
      return;
    }
    if (tool == EditorTool.brush) {
      ref
          .read(pdfSessionProvider.notifier)
          .addStroke(
            BrushStroke(
              id: 'pdf_stroke_${DateTime.now().microsecondsSinceEpoch}',
              points: [point, point + const Offset(.01, .01)],
              size: brushSize,
              style: style,
            ),
          );
      setState(() => brushTouchLocal = null);
      return;
    }
    if (tool != EditorTool.select) return;
    final hit = image.items
        .where((item) => item.selected && item.bounds.contains(point))
        .lastOrNull;
    setState(() {
      activeId = hit?.id;
      interactionBounds = hit?.bounds;
      resizeOrigin = hit?.bounds;
      areaScale = 100;
    });
  }

  void _tapDown(Offset global) {
    final local = _viewportLocal(global);
    if (local == null) return;
    if (tool == EditorTool.brush) {
      setState(() => brushTouchLocal = local);
    } else if (tool == EditorTool.eraser) {
      setState(() => eraserTouchLocal = local);
    }
  }

  void _erase(Offset point, double geometryFactor) {
    final zoom = _transformationController.value.getMaxScaleOnAxis();
    final changed = ref
        .read(pdfSessionProvider.notifier)
        .eraseAt(
          point,
          radius: 22 / (geometryFactor * zoom),
          recordHistory: !eraserGestureHasHistory,
        );
    if (changed) eraserGestureHasHistory = true;
  }

  Offset? _viewportLocal(Offset global) {
    final renderObject =
        _canvasViewportKey.currentContext?.findRenderObject() as RenderBox?;
    return renderObject?.globalToLocal(global);
  }

  void _cancelGesture() {
    if (!mounted) return;
    setState(() {
      gestureStart = null;
      lastImagePoint = null;
      draftBounds = null;
      stroke = [];
      brushTouchLocal = null;
      eraserTouchLocal = null;
      eraserGestureHasHistory = false;
    });
  }

  void _commitInteraction() {
    if (activeId != null && interactionBounds != null) {
      ref
          .read(pdfSessionProvider.notifier)
          .updateBounds(activeId!, interactionBounds!);
      resizeOrigin = interactionBounds;
      areaScale = 100;
    }
  }

  Rect _clampShift(Rect bounds, Offset delta, ImageSession image) {
    final dx = delta.dx.clamp(-bounds.left, image.width - bounds.right);
    final dy = delta.dy.clamp(-bounds.top, image.height - bounds.bottom);
    return bounds.shift(Offset(dx, dy));
  }

  Widget _area(ImageGeometry geometry, RedactionItem item) {
    final bounds = item.id == activeId && interactionBounds != null
        ? interactionBounds!
        : item.bounds;
    return Positioned.fromRect(
      rect: geometry.toLocalRect(bounds),
      child: IgnorePointer(
        child: _isSticker(item.style)
            ? StickerRedaction(
                style: item.style,
                border: Border.all(
                  color: item.id == activeId
                      ? const Color(0xFF6FFFC2)
                      : Colors.white,
                  width: item.id == activeId ? 3 : 1.5,
                ),
              )
            : DecoratedBox(
                decoration: BoxDecoration(
                  color: switch (item.style) {
                    RedactionStyle.blur => const Color(
                      0xFF8C8175,
                    ).withValues(alpha: .72),
                    RedactionStyle.pixelate => Colors.blueGrey.withValues(
                      alpha: .72,
                    ),
                    RedactionStyle.blackout => Colors.black.withValues(
                      alpha: .88,
                    ),
                    RedactionStyle.emoji => Colors.transparent,
                    RedactionStyle.flowers => Colors.transparent,
                  },
                  border: Border.all(
                    color: item.id == activeId
                        ? const Color(0xFF6FFFC2)
                        : Colors.white,
                    width: item.id == activeId ? 3 : 1.5,
                  ),
                ),
              ),
      ),
    );
  }

  Widget _draftArea(ImageGeometry geometry, Rect bounds) => Positioned.fromRect(
    rect: geometry.toLocalRect(bounds),
    child: IgnorePointer(
      child: _isSticker(style)
          ? StickerRedaction(
              style: style,
              border: Border.all(color: Colors.amber, width: 2.5),
            )
          : DecoratedBox(
              decoration: BoxDecoration(
                color: forest.withValues(alpha: .3),
                border: Border.all(color: Colors.amber, width: 2.5),
              ),
            ),
    ),
  );

  Widget _strokeOverlay(ImageGeometry geometry, BrushStroke value) =>
      Positioned.fill(
        child: IgnorePointer(
          child: CustomPaint(
            painter: _PdfStrokePainter(
              points: [
                for (final point in value.points)
                  geometry.origin + point * geometry.factor,
              ],
              width: value.size * geometry.factor,
              style: value.style,
            ),
          ),
        ),
      );

  Widget _brushMagnifier(Offset focal, Size viewport) {
    const lensSize = 104.0;
    const gap = 28.0;
    final left = (focal.dx - lensSize / 2)
        .clamp(8.0, max(8.0, viewport.width - lensSize - 8))
        .toDouble();
    final desiredTop = focal.dy > lensSize + gap + 12
        ? focal.dy - lensSize - gap
        : focal.dy + gap;
    final top = desiredTop
        .clamp(8.0, max(8.0, viewport.height - lensSize - 8))
        .toDouble();
    final lensCenter = Offset(left + lensSize / 2, top + lensSize / 2);
    return Positioned(
      left: left,
      top: top,
      child: IgnorePointer(
        child: RawMagnifier(
          size: const Size.square(lensSize),
          magnificationScale: 2.4,
          focalPointOffset: focal - lensCenter,
          clipBehavior: Clip.hardEdge,
          decoration: const MagnifierDecoration(
            shape: CircleBorder(side: BorderSide(color: forest, width: 3)),
            shadows: [
              BoxShadow(
                color: Color(0x55000000),
                blurRadius: 12,
                offset: Offset(0, 5),
              ),
            ],
          ),
          child: const Center(
            child: Icon(Icons.add, size: 24, color: Color(0xFFD32F2F)),
          ),
        ),
      ),
    );
  }

  Widget _eraserCursor(Offset point) => Positioned(
    left: point.dx - 22,
    top: point.dy - 22,
    child: IgnorePointer(
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: .08),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.redAccent, width: 2),
        ),
        child: const Icon(
          Icons.auto_fix_off_outlined,
          size: 19,
          color: Colors.redAccent,
        ),
      ),
    ),
  );

  void _resetZoom() {
    _transformationController.value = Matrix4.identity();
  }

  void _clearSelection() {
    activeId = null;
    interactionBounds = null;
    resizeOrigin = null;
    areaScale = 100;
    gestureStart = null;
    lastImagePoint = null;
    draftBounds = null;
    stroke = [];
    brushTouchLocal = null;
    eraserTouchLocal = null;
  }
}

class _ToolHint extends StatelessWidget {
  const _ToolHint({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(12, 9, 10, 9),
    decoration: BoxDecoration(
      color: mint,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFFB2D8CA)),
    ),
    child: Row(
      children: [
        Icon(icon, color: forest, size: 22),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.3,
              color: Color(0xFF44514D),
            ),
          ),
        ),
      ],
    ),
  );
}

bool _isSticker(RedactionStyle style) =>
    style == RedactionStyle.emoji || style == RedactionStyle.flowers;

class _EditorPageStrip extends StatelessWidget {
  const _EditorPageStrip({
    required this.count,
    required this.current,
    required this.onSelected,
  });

  final int count;
  final int current;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 46,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      itemCount: count,
      separatorBuilder: (_, _) => const SizedBox(width: 6),
      itemBuilder: (context, index) => ChoiceChip(
        label: Text('${index + 1}'),
        selected: index == current,
        onSelected: (_) => onSelected(index),
      ),
    ),
  );
}

class _PdfStrokePainter extends CustomPainter {
  const _PdfStrokePainter({
    required this.points,
    required this.width,
    required this.style,
  });

  final List<Offset> points;
  final double width;
  final RedactionStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    final paint = Paint()
      ..strokeWidth = max(1, width)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..color = switch (style) {
        RedactionStyle.blur => const Color(0xCC8C8175),
        RedactionStyle.pixelate => const Color(0xCC607D8B),
        RedactionStyle.blackout => Colors.black,
        RedactionStyle.emoji => const Color(0xFFFFC928),
        RedactionStyle.flowers => const Color(0xFFF7A9C4),
      };
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _PdfStrokePainter oldDelegate) =>
      oldDelegate.points != points ||
      oldDelegate.width != width ||
      oldDelegate.style != style;
}
