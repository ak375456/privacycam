import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../domain/models.dart';
import '../../state/providers.dart';
import '../widgets/adaptive_ui.dart';
import '../widgets/batch_strip.dart';
import '../widgets/image_geometry.dart';
import '../widgets/new_image_action.dart';

class ReviewScreen extends ConsumerStatefulWidget {
  const ReviewScreen({super.key});
  @override
  ConsumerState<ReviewScreen> createState() => _ReviewState();
}

class _ReviewState extends ConsumerState<ReviewScreen> {
  IconData icon(RedactionCategory c) => switch (c) {
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
  @override
  Widget build(BuildContext context) {
    final s = ref.watch(sessionProvider);
    if (s == null) return const SizedBox();
    final counts = <RedactionCategory, int>{};
    for (final i in s.items) {
      counts[i.category] = (counts[i.category] ?? 0) + 1;
    }
    final selectedCount = s.items.where((item) => item.selected).length;
    return Scaffold(
      appBar: adaptiveNavigationBar(
        context,
        title: const Text('Choose what to hide'),
        actions: const [NewImageAction()],
      ),
      body: Column(
        children: [
          const BatchStrip(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${s.items.length} possible details found',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    AdaptiveButton(
                      style: AdaptiveButtonStyle.plain,
                      onPressed: () =>
                          ref.read(sessionProvider.notifier).selectAll(),
                      icon: Icon(
                        adaptiveIcon(
                          context,
                          material: Icons.visibility_off_outlined,
                          cupertino: CupertinoIcons.eye_slash,
                        ),
                        size: 19,
                      ),
                      child: const Text('Hide all'),
                    ),
                  ],
                ),
                Text(
                  '$selectedCount will be hidden',
                  style: const TextStyle(
                    color: forest,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                const Text(
                  'Tap any outlined area—even ordinary text—to hide it. Tap again to keep it visible.',
                  style: TextStyle(height: 1.35),
                ),
                const SizedBox(height: 10),
                const _SelectionLegend(),
              ],
            ),
          ),
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                const Center(
                  child: Padding(
                    padding: EdgeInsets.only(right: 5),
                    child: Text(
                      'Hide:',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                for (final e in counts.entries)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: _categoryChip(s, e.key, e.value),
                  ),
              ],
            ),
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
                  return Stack(
                    children: [
                      Positioned(
                        left: g.origin.dx,
                        top: g.origin.dy,
                        width: g.displayed.width,
                        height: g.displayed.height,
                        child: Image.file(File(s.sourcePath), fit: BoxFit.fill),
                      ),
                      for (final item in s.items) _box(g, item),
                    ],
                  );
                },
              ),
            ),
          ),
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
            child: Column(
              children: [
                const Text(
                  'Automatic detection can miss private details. Review the image carefully before sharing.',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (ref.watch(batchProvider).isBatch) ...[
                      AdaptiveButton(
                        style: AdaptiveButtonStyle.secondary,
                        onPressed: () => context.push('/batch'),
                        child: const Text('Overview'),
                      ),
                      const SizedBox(width: 10),
                    ],
                    AdaptiveButton(
                      onPressed: () => context.push('/editor'),
                      child: const Text('Continue to editor'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _categoryChip(
    ImageSession session,
    RedactionCategory category,
    int total,
  ) {
    final selected = session.items
        .where((item) => item.category == category && item.selected)
        .length;
    final label = selected == 0
        ? '${category.label} off'
        : selected == total
        ? '${category.label} $total'
        : '${category.label} $selected/$total';
    final tooltip = selected == 0
        ? 'Hide all ${category.label.toLowerCase()}'
        : 'Keep all ${category.label.toLowerCase()} visible';
    if (usesCupertinoUi(context)) {
      return Tooltip(
        message: tooltip,
        child: CupertinoButton(
          sizeStyle: CupertinoButtonSize.small,
          color: selected > 0 ? mint : CupertinoColors.systemGrey6,
          foregroundColor: selected > 0 ? forest : ink,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          borderRadius: BorderRadius.circular(10),
          onPressed: () => ref
              .read(sessionProvider.notifier)
              .setCategorySelected(category, selected == 0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon(category), size: 17),
              const SizedBox(width: 6),
              Text(label),
            ],
          ),
        ),
      );
    }
    return Tooltip(
      message: tooltip,
      child: FilterChip(
        avatar: Icon(icon(category), size: 18),
        label: Text(label),
        selected: selected > 0,
        onSelected: (hide) => ref
            .read(sessionProvider.notifier)
            .setCategorySelected(category, hide),
      ),
    );
  }

  Widget _box(ImageGeometry g, RedactionItem item) {
    final r = g.toLocalRect(item.bounds);
    return Positioned.fromRect(
      rect: r,
      child: Semantics(
        label: item.selected
            ? '${item.category.label}. Will be hidden. Tap to keep visible.'
            : '${item.category.label}. Not hidden. Tap to hide.',
        button: true,
        child: GestureDetector(
          onTap: () => ref.read(sessionProvider.notifier).toggle(item.id),
          child: Container(
            decoration: BoxDecoration(
              color: item.selected
                  ? forest.withValues(alpha: .26)
                  : const Color(0xFFFFC857).withValues(alpha: .08),
              border: Border.all(
                color: item.selected
                    ? const Color(0xFF6FFFC2)
                    : const Color(0xFFFFC857),
                width: item.selected ? 3 : 2,
              ),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact =
                    constraints.maxWidth < 78 || constraints.maxHeight < 28;
                return Align(
                  alignment: compact ? Alignment.center : Alignment.topLeft,
                  child: Container(
                    color: item.selected
                        ? forest
                        : const Color(0xFF6A4A00).withValues(alpha: .9),
                    padding: EdgeInsets.symmetric(
                      horizontal: compact ? 3 : 6,
                      vertical: 2,
                    ),
                    child: Text(
                      compact
                          ? (item.selected ? '✓' : '+')
                          : item.selected
                          ? '✓ Will hide'
                          : 'Tap to hide',
                      maxLines: 1,
                      overflow: TextOverflow.fade,
                      softWrap: false,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _SelectionLegend extends StatelessWidget {
  const _SelectionLegend();

  @override
  Widget build(BuildContext context) => const Wrap(
    spacing: 16,
    runSpacing: 6,
    children: [
      _LegendItem(
        color: Color(0xFF6FFFC2),
        icon: Icons.check,
        label: 'Will be hidden',
      ),
      _LegendItem(
        color: Color(0xFFFFC857),
        icon: Icons.add,
        label: 'Tap to hide',
      ),
    ],
  );
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({
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
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          color: Colors.black87,
          border: Border.all(color: color, width: 2),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Icon(icon, size: 13, color: color),
      ),
      const SizedBox(width: 6),
      Text(label, style: const TextStyle(fontSize: 12)),
    ],
  );
}
