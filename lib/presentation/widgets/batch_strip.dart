import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../domain/models.dart';
import '../../state/providers.dart';

class BatchStrip extends ConsumerWidget {
  const BatchStrip({super.key, this.onSelected});

  final ValueChanged<int>? onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final batch = ref.watch(batchProvider);
    if (batch.items.length < 2) return const SizedBox.shrink();
    return ColoredBox(
      color: Colors.white,
      child: SizedBox(
        height: 92,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          itemCount: batch.items.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            final item = batch.items[index];
            final active = index == batch.activeIndex;
            final path = item.session?.sourcePath ?? item.originalPath;
            return Semantics(
              button: item.session != null,
              selected: active,
              label: 'Photo ${index + 1}, ${_statusLabel(item.status)}',
              child: GestureDetector(
                onTap: item.session == null
                    ? null
                    : () {
                        ref.read(sessionProvider.notifier).activate(index);
                        onSelected?.call(index);
                      },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 66,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: active ? forest : const Color(0xFFD8DEDA),
                      width: active ? 3 : 1,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.file(
                        File(path),
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const ColoredBox(
                          color: Color(0xFFE7EBE8),
                          child: Icon(Icons.broken_image_outlined),
                        ),
                      ),
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: ColoredBox(
                          color: Colors.black.withValues(alpha: .68),
                          child: SizedBox(
                            height: 22,
                            width: double.infinity,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  _statusIcon(item.status),
                                  size: 13,
                                  color: _statusColor(item.status),
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  '${index + 1}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
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
    );
  }
}

String _statusLabel(BatchItemStatus status) => switch (status) {
  BatchItemStatus.queued => 'Waiting',
  BatchItemStatus.scanning => 'Scanning',
  BatchItemStatus.needsReview => 'Needs review',
  BatchItemStatus.safe => 'Safe copy ready',
  BatchItemStatus.saved => 'Saved',
  BatchItemStatus.failed => 'Failed',
  BatchItemStatus.skipped => 'Skipped',
};

IconData _statusIcon(BatchItemStatus status) => switch (status) {
  BatchItemStatus.queued => Icons.schedule,
  BatchItemStatus.scanning => Icons.sync,
  BatchItemStatus.needsReview => Icons.visibility_outlined,
  BatchItemStatus.safe => Icons.shield_outlined,
  BatchItemStatus.saved => Icons.check_circle,
  BatchItemStatus.failed => Icons.error_outline,
  BatchItemStatus.skipped => Icons.skip_next,
};

Color _statusColor(BatchItemStatus status) => switch (status) {
  BatchItemStatus.safe || BatchItemStatus.saved => const Color(0xFF6FFFC2),
  BatchItemStatus.failed => const Color(0xFFFF8A80),
  BatchItemStatus.needsReview => const Color(0xFFFFD166),
  _ => Colors.white,
};
