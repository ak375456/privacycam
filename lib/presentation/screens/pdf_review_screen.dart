import 'dart:io';
import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/models.dart';
import '../../state/pdf_providers.dart';
import '../widgets/adaptive_ui.dart';
import '../widgets/image_geometry.dart';
import '../widgets/pdf_review_outline.dart';

class PdfReviewScreen extends ConsumerWidget {
  const PdfReviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final document = ref.watch(pdfSessionProvider);
    final page = document?.currentPage;
    if (document == null || page == null) {
      return const Scaffold(body: Center(child: Text('No PDF is open.')));
    }
    final image = page.image;
    final counts = <RedactionCategory, int>{};
    for (final item in image.items) {
      counts[item.category] = (counts[item.category] ?? 0) + 1;
    }
    final selected = image.items.where((item) => item.selected).length;
    return Scaffold(
      appBar: adaptiveNavigationBar(
        context,
        title: const Text('Review PDF'),
        leading: AdaptiveIconButton(
          tooltip: 'Close PDF',
          onPressed: () => _close(context, ref),
          icon: Icon(
            adaptiveIcon(
              context,
              material: Icons.close,
              cupertino: CupertinoIcons.xmark,
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            _PageStrip(
              count: document.pageCount,
              current: document.currentPageIndex,
              onSelected: (index) =>
                  ref.read(pdfSessionProvider.notifier).setCurrentPage(index),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 8),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${image.items.length} possible details on page ${page.pageNumber}',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      AdaptiveButton(
                        style: AdaptiveButtonStyle.plain,
                        onPressed: () =>
                            ref.read(pdfSessionProvider.notifier).selectAll(),
                        child: const Text('Hide all'),
                      ),
                    ],
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 14,
                      runSpacing: 5,
                      children: [
                        _ReviewLegend(
                          color: const Color(0xFF008866),
                          icon: Icons.check_rounded,
                          label: '$selected will be hidden',
                        ),
                        const _ReviewLegend(
                          color: Color(0xFFD58A00),
                          icon: Icons.add_rounded,
                          label: 'Tap an outline to hide it',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Ordinary text outlines appear as you zoom in, keeping the page readable.',
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => _showDetectedDetails(context),
                          icon: const Icon(Icons.format_list_bulleted_rounded),
                          label: Text('Review ${image.items.length} details'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _editPrivateData(context, ref),
                          icon: const Icon(Icons.person_search_outlined),
                          label: Text(
                            document.customTerms.isEmpty
                                ? 'Find exact text'
                                : '${document.customTerms.length} exact terms',
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 45,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                children: [
                  for (final entry in counts.entries)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: FilterChip(
                        avatar: Icon(_categoryIcon(entry.key), size: 17),
                        label: Text('${entry.key.label} ${entry.value}'),
                        selected: image.items.any(
                          (item) => item.category == entry.key && item.selected,
                        ),
                        onSelected: (value) => ref
                            .read(pdfSessionProvider.notifier)
                            .setCategorySelected(entry.key, value),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: _ReviewCanvas(
                key: ValueKey(image.sourcePath),
                image: image,
                onToggle: (id) =>
                    ref.read(pdfSessionProvider.notifier).toggle(id),
              ),
            ),
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
              child: Column(
                children: [
                  const Text(
                    'Check every page. Automatic detection can miss details, especially in low-quality scans.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12.5, color: Colors.black54),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: AdaptiveButton(
                      onPressed: () => context.push('/pdf/editor'),
                      icon: const Icon(Icons.edit_outlined),
                      child: const Text('Continue to PDF editor'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _close(BuildContext context, WidgetRef ref) async {
    final discard = await showAdaptiveActionSheet<bool>(
      context: context,
      title: 'Close this PDF?',
      message: 'Unsaved PDF edits will be discarded.',
      actions: const [
        AdaptiveAction(
          label: 'Discard PDF',
          value: true,
          destructive: true,
          icon: Icons.delete_outline,
        ),
      ],
      cancelLabel: 'Keep editing',
    );
    if (discard != true) return;
    await ref.read(pdfSessionProvider.notifier).clear();
    if (context.mounted) context.go('/home');
  }

  Future<void> _editPrivateData(BuildContext context, WidgetRef ref) async {
    final current = ref.read(pdfSessionProvider)?.customTerms ?? const [];
    final result = await showDialog<({List<String> terms, bool remember})>(
      context: context,
      builder: (_) => _PrivateDataDialog(initialTerms: current),
    );
    if (result == null || !context.mounted) return;
    await ref
        .read(pdfSessionProvider.notifier)
        .setCustomTerms(result.terms, remember: result.remember);
  }

  Future<void> _showDetectedDetails(BuildContext context) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        builder: (_) => const _DetectedDetailsSheet(),
      );
}

class _ReviewCanvas extends StatefulWidget {
  const _ReviewCanvas({super.key, required this.image, required this.onToggle});

  final ImageSession image;
  final ValueChanged<String> onToggle;

  @override
  State<_ReviewCanvas> createState() => _ReviewCanvasState();
}

class _ReviewCanvasState extends State<_ReviewCanvas> {
  final TransformationController _controller = TransformationController();
  Offset _doubleTapPosition = Offset.zero;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: const Color(0xFF191B1A),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final viewport = Size(constraints.maxWidth, constraints.maxHeight);
        final geometry = ImageGeometry(
          viewport,
          Size(widget.image.width.toDouble(), widget.image.height.toDouble()),
        );
        return Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                transformationController: _controller,
                minScale: 1,
                maxScale: 8,
                boundaryMargin: const EdgeInsets.all(90),
                child: SizedBox.fromSize(
                  size: viewport,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onDoubleTapDown: (details) =>
                        _doubleTapPosition = details.localPosition,
                    onDoubleTap: _toggleZoom,
                    onTapUp: (details) =>
                        _toggleNearest(geometry, details.localPosition),
                    child: AnimatedBuilder(
                      animation: _controller,
                      builder: (context, _) {
                        final viewerScale = _controller.value
                            .getMaxScaleOnAxis()
                            .clamp(1.0, 8.0);
                        return Stack(
                          children: [
                            Positioned(
                              left: geometry.origin.dx,
                              top: geometry.origin.dy,
                              width: geometry.displayed.width,
                              height: geometry.displayed.height,
                              child: Image.file(
                                File(widget.image.sourcePath),
                                fit: BoxFit.fill,
                                filterQuality: FilterQuality.high,
                              ),
                            ),
                            for (final item in widget.image.items)
                              if (PdfReviewOutlineLayout.isVisible(
                                item,
                                viewerScale,
                              ))
                                _DetectionBox(
                                  geometry: geometry,
                                  item: item,
                                  viewerScale: viewerScale,
                                ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
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
  );

  void _toggleZoom() {
    if (_controller.value.getMaxScaleOnAxis() > 1.05) {
      _resetZoom();
      return;
    }
    const scale = 2.8;
    _controller.value = Matrix4.identity()
      ..translateByDouble(
        (1 - scale) * _doubleTapPosition.dx,
        (1 - scale) * _doubleTapPosition.dy,
        0,
        1,
      )
      ..scaleByDouble(scale, scale, 1, 1);
  }

  void _resetZoom() => _controller.value = Matrix4.identity();

  void _toggleNearest(ImageGeometry geometry, Offset localPoint) {
    final point = geometry.toImage(localPoint);
    final scale = _controller.value.getMaxScaleOnAxis().clamp(1.0, 8.0);
    final imagePadding = 25 / (geometry.factor * scale);
    final exact =
        widget.image.items
            .where(
              (item) =>
                  PdfReviewOutlineLayout.isVisible(item, scale) &&
                  item.bounds.contains(point),
            )
            .toList()
          ..sort((a, b) => _area(a.bounds).compareTo(_area(b.bounds)));
    if (exact.isNotEmpty) {
      widget.onToggle(exact.first.id);
      return;
    }
    final nearby =
        widget.image.items
            .where(
              (item) =>
                  PdfReviewOutlineLayout.isVisible(item, scale) &&
                  item.bounds.inflate(imagePadding).contains(point),
            )
            .toList()
          ..sort((a, b) {
            final distance = _distanceToRect(
              point,
              a.bounds,
            ).compareTo(_distanceToRect(point, b.bounds));
            return distance != 0
                ? distance
                : _area(a.bounds).compareTo(_area(b.bounds));
          });
    if (nearby.isNotEmpty) widget.onToggle(nearby.first.id);
  }

  double _area(Rect rect) => rect.width * rect.height;

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
}

class _DetectionBox extends StatelessWidget {
  const _DetectionBox({
    required this.geometry,
    required this.item,
    required this.viewerScale,
  });

  final ImageGeometry geometry;
  final RedactionItem item;
  final double viewerScale;

  @override
  Widget build(BuildContext context) => Positioned.fromRect(
    rect: PdfReviewOutlineLayout.rectFor(geometry, item, viewerScale),
    child: IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(2 / viewerScale),
          border: Border.all(
            color: item.selected
                ? const Color(0xFF008866)
                : const Color(0xFFB96F00),
            width: PdfReviewOutlineLayout.strokeWidth(item, viewerScale),
          ),
        ),
      ),
    ),
  );
}

class _DetectedDetailsSheet extends ConsumerWidget {
  const _DetectedDetailsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final document = ref.watch(pdfSessionProvider);
    final page = document?.currentPage;
    if (page == null) return const SizedBox.shrink();
    final items = [...page.image.items]
      ..sort((a, b) {
        final aOther = a.category == RedactionCategory.otherText ? 1 : 0;
        final bOther = b.category == RedactionCategory.otherText ? 1 : 0;
        final categoryOrder = aOther.compareTo(bOther);
        if (categoryOrder != 0) return categoryOrder;
        if (a.selected != b.selected) return a.selected ? -1 : 1;
        return a.bounds.top.compareTo(b.bounds.top);
      });
    final selected = items.where((item) => item.selected).length;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.82,
      minChildSize: 0.48,
      maxChildSize: 0.96,
      builder: (context, scrollController) => Material(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 42,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(9),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 10, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Detected details on page ${page.pageNumber}',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '$selected of ${items.length} will be hidden. Read each result, then choose Hide or Keep.',
                            style: const TextStyle(color: Colors.black54),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        ref.read(pdfSessionProvider.notifier).selectAll(),
                    icon: const Icon(Icons.visibility_off_outlined),
                    label: const Text('Hide every detected detail'),
                  ),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.separated(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 18),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final text = item.label
                        ?.replaceAll(RegExp(r'\s+'), ' ')
                        .trim();
                    final readable = text == null || text.isEmpty
                        ? 'Detected ${item.category.label.toLowerCase()}'
                        : text;
                    final color = item.selected
                        ? const Color(0xFF008866)
                        : const Color(0xFFD58A00);
                    return Material(
                      color: color.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => ref
                            .read(pdfSessionProvider.notifier)
                            .toggle(item.id),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                          child: Row(
                            children: [
                              Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.12),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  _categoryIcon(item.category),
                                  color: color,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      readable,
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 15.5,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${item.category.label} · ${item.selected ? 'Will be hidden' : 'Kept visible'}',
                                      style: TextStyle(
                                        color: color,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Semantics(
                                label: item.selected
                                    ? 'Keep this detail visible'
                                    : 'Hide this detail',
                                child: Switch.adaptive(
                                  value: item.selected,
                                  onChanged: (_) => ref
                                      .read(pdfSessionProvider.notifier)
                                      .toggle(item.id),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PrivateDataDialog extends StatefulWidget {
  const _PrivateDataDialog({required this.initialTerms});

  final List<String> initialTerms;

  @override
  State<_PrivateDataDialog> createState() => _PrivateDataDialogState();
}

class _PrivateDataDialogState extends State<_PrivateDataDialog> {
  late final TextEditingController _controller;
  bool _remember = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialTerms.join('\n'));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Find exact private text'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Enter your name, account number, address, or another exact term. Put each term on a new line. PrivacyCam finds matching detected text across this PDF.',
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _controller,
            minLines: 3,
            maxLines: 7,
            textInputAction: TextInputAction.newline,
            decoration: const InputDecoration(
              labelText: 'Private terms',
              hintText: 'Aftab Fazal Qayum\nAccount 123456',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _remember,
            onChanged: (value) => setState(() => _remember = value ?? false),
            title: const Text('Remember securely on this device'),
            subtitle: const Text('You can remove saved terms later.'),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          final terms = _controller.text
              .split('\n')
              .map((value) => value.trim())
              .where((value) => value.length >= 2)
              .toList();
          Navigator.of(context).pop((terms: terms, remember: _remember));
        },
        child: const Text('Find and hide matches'),
      ),
    ],
  );
}

class _ReviewLegend extends StatelessWidget {
  const _ReviewLegend({
    required this.color,
    required this.icon,
    required this.label,
  });

  final Color color;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 21,
        height: 18,
        decoration: BoxDecoration(
          border: Border.all(color: color, width: 2),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Icon(icon, color: color, size: 14),
      ),
      const SizedBox(width: 5),
      Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w700),
      ),
    ],
  );
}

class _PageStrip extends StatelessWidget {
  const _PageStrip({
    required this.count,
    required this.current,
    required this.onSelected,
  });

  final int count;
  final int current;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 47,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      itemCount: count,
      separatorBuilder: (_, _) => const SizedBox(width: 6),
      itemBuilder: (context, index) => ChoiceChip(
        label: Text('Page ${index + 1}'),
        selected: index == current,
        onSelected: (_) => onSelected(index),
      ),
    ),
  );
}

IconData _categoryIcon(RedactionCategory category) => switch (category) {
  RedactionCategory.face => Icons.face_outlined,
  RedactionCategory.person => Icons.accessibility_new_rounded,
  RedactionCategory.email => Icons.alternate_email,
  RedactionCategory.phone => Icons.phone_outlined,
  RedactionCategory.address => Icons.location_on_outlined,
  RedactionCategory.card => Icons.credit_card,
  RedactionCategory.cardSecurityCode => Icons.password_outlined,
  RedactionCategory.url => Icons.link,
  RedactionCategory.qrCode => Icons.qr_code,
  RedactionCategory.barcode => Icons.view_week_outlined,
  RedactionCategory.numberPlate => Icons.directions_car_outlined,
  RedactionCategory.otherText => Icons.text_fields,
  RedactionCategory.manual => Icons.crop_square,
};
