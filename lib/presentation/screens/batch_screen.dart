import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme.dart';
import '../../domain/models.dart';
import '../../state/providers.dart';
import '../widgets/adaptive_ui.dart';
import '../widgets/new_image_action.dart';
import '../widgets/privacy_loader.dart';

class BatchScreen extends ConsumerStatefulWidget {
  const BatchScreen({super.key});

  @override
  ConsumerState<BatchScreen> createState() => _BatchScreenState();
}

class _BatchScreenState extends ConsumerState<BatchScreen> {
  bool busy = false;
  String busyLabel = '';
  int progressCurrent = 0;
  int progressTotal = 0;

  @override
  Widget build(BuildContext context) {
    final batch = ref.watch(batchProvider);
    if (batch.isEmpty) {
      return Scaffold(
        appBar: adaptiveNavigationBar(
          context,
          title: const Text('Photo batch'),
        ),
        body: Center(
          child: AdaptiveButton(
            onPressed: () => context.go('/home'),
            child: const Text('Choose photos'),
          ),
        ),
      );
    }
    if (batch.isBatch && !ref.watch(batchAccessProvider)) {
      return Scaffold(
        appBar: adaptiveNavigationBar(
          context,
          title: const Text('Photo batch'),
        ),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 430),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(color: const Color(0xFFE0E6E2)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.workspace_premium_outlined,
                      color: forest,
                      size: 52,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '${batch.items.length}-photo batch saved',
                      style: Theme.of(context).textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Your photos are still here. Unlock PrivacyCam Pro to continue this batch, or return home and start with one photo.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFF52615D), height: 1.4),
                    ),
                    const SizedBox(height: 22),
                    SizedBox(
                      width: double.infinity,
                      child: AdaptiveButton(
                        onPressed: () => context.push('/pro'),
                        icon: const Icon(Icons.lock_open_rounded),
                        child: const Text('Unlock Pro'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    AdaptiveButton(
                      style: AdaptiveButtonStyle.plain,
                      onPressed: () => context.go('/home'),
                      child: const Text('Back to home'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }
    final hasQueued = batch.items.any(
      (item) => item.status == BatchItemStatus.queued,
    );
    final nextReview = batch.items.indexWhere(
      (item) => item.status == BatchItemStatus.needsReview,
    );
    return Scaffold(
      appBar: adaptiveNavigationBar(
        context,
        title: const Text('Photo batch'),
        actions: [
          NewImageAction(enabled: !busy),
          AdaptiveIconButton(
            tooltip: 'Close batch overview',
            onPressed: busy ? null : () => context.go('/home'),
            icon: Icon(
              adaptiveIcon(
                context,
                material: Icons.home_outlined,
                cupertino: CupertinoIcons.house,
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '${batch.items.length} photos',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${batch.safeCount} safe · ${batch.needsReviewCount} need review'
                        '${batch.failedCount > 0 ? ' · ${batch.failedCount} failed' : ''}',
                        style: const TextStyle(color: Color(0xFF52615D)),
                      ),
                      const SizedBox(height: 13),
                      if (hasQueued)
                        AdaptiveButton(
                          onPressed: busy
                              ? null
                              : () => context.push(
                                  '/scan',
                                  extra: const BatchScanRequest(
                                    paths: [],
                                    append: true,
                                  ),
                                ),
                          icon: const Icon(Icons.play_arrow_rounded),
                          child: const Text('Continue scanning'),
                        )
                      else if (nextReview >= 0)
                        AdaptiveButton(
                          onPressed: busy
                              ? null
                              : () {
                                  ref
                                      .read(sessionProvider.notifier)
                                      .activate(nextReview);
                                  context.push('/review');
                                },
                          icon: const Icon(Icons.visibility_outlined),
                          child: const Text('Review next photo'),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                    itemCount: batch.items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) => _BatchItemCard(
                      index: index,
                      item: batch.items[index],
                      enabled: !busy,
                      onOpen: () => _open(index, batch.items[index]),
                      onToggleSelected: () => ref
                          .read(sessionProvider.notifier)
                          .toggleBatchSelection(index),
                      onRetry: () {
                        ref.read(sessionProvider.notifier).retry(index);
                        context.push(
                          '/scan',
                          extra: const BatchScanRequest(
                            paths: [],
                            append: true,
                          ),
                        );
                      },
                      onSkip: () =>
                          ref.read(sessionProvider.notifier).skip(index),
                      onRemove: () => _remove(index),
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(top: BorderSide(color: Color(0xFFE0E6E2))),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${batch.selectedSafeCount} safe ${batch.selectedSafeCount == 1 ? 'copy' : 'copies'} selected',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          AdaptiveButton(
                            style: AdaptiveButtonStyle.plain,
                            onPressed: busy || batch.safeCount == 0
                                ? null
                                : () => ref
                                      .read(sessionProvider.notifier)
                                      .setAllSafeSelected(
                                        batch.selectedSafeCount !=
                                            batch.safeCount,
                                      ),
                            child: Text(
                              batch.selectedSafeCount == batch.safeCount
                                  ? 'Select none'
                                  : 'Select all',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 9),
                      Row(
                        children: [
                          Expanded(
                            child: AdaptiveButton(
                              onPressed: busy || batch.selectedSafeCount == 0
                                  ? null
                                  : _saveSelected,
                              icon: const Icon(Icons.download_outlined),
                              child: const Text('Save selected'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: AdaptiveButton(
                              style: AdaptiveButtonStyle.secondary,
                              onPressed: busy || batch.selectedSafeCount == 0
                                  ? null
                                  : _shareSelected,
                              icon: const Icon(Icons.share_outlined),
                              child: const Text('Share'),
                            ),
                          ),
                        ],
                      ),
                      AdaptiveButton(
                        style: AdaptiveButtonStyle.plain,
                        onPressed: busy ? null : _discardBatch,
                        child: const Text('Discard batch and start over'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (busy)
              Positioned.fill(
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: .5),
                  child: Center(
                    child: Container(
                      margin: const EdgeInsets.all(24),
                      padding: const EdgeInsets.all(28),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(28),
                      ),
                      child: PrivacyLoader(
                        label: busyLabel,
                        progress: progressTotal > 0
                            ? progressCurrent / progressTotal
                            : null,
                        detail: progressTotal > 0
                            ? 'Photo $progressCurrent of $progressTotal'
                            : 'Everything stays on this device',
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _open(int index, BatchItem item) {
    if (item.session == null) return;
    ref.read(sessionProvider.notifier).activate(index);
    switch (item.status) {
      case BatchItemStatus.safe || BatchItemStatus.saved:
        context.push('/export');
      case BatchItemStatus.needsReview:
        context.push('/review');
      case _:
        break;
    }
  }

  Future<void> _remove(int index) async {
    final confirmed = await showAdaptiveActionSheet<bool>(
      context: context,
      title: 'Remove this photo?',
      message: 'Its PrivacyCam edits and temporary safe copy will be deleted.',
      actions: const [
        AdaptiveAction(
          label: 'Remove photo',
          value: true,
          destructive: true,
          icon: Icons.delete_outline,
        ),
      ],
    );
    if (confirmed != true || !mounted) return;
    await ref.read(sessionProvider.notifier).removeFromBatch(index);
    if (mounted && ref.read(batchProvider).isEmpty) context.go('/home');
  }

  Future<void> _saveSelected() async {
    setState(() {
      busy = true;
      busyLabel = 'Saving safe copies';
      progressCurrent = 0;
      progressTotal = ref.read(batchProvider).selectedSafeCount;
    });
    try {
      final result = await ref
          .read(sessionProvider.notifier)
          .saveSelected(
            onProgress: (current, total) {
              if (mounted) {
                setState(() {
                  progressCurrent = current;
                  progressTotal = total;
                });
              }
            },
          );
      if (!mounted) return;
      final suffix = result.errors.isEmpty
          ? ''
          : ' ${result.errors.length} could not be saved.';
      showAdaptiveMessage(
        context,
        '${result.saved} safe ${result.saved == 1 ? 'copy' : 'copies'} saved.$suffix',
        error: result.errors.isNotEmpty,
      );
    } catch (error) {
      if (mounted) showAdaptiveMessage(context, '$error', error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _shareSelected() async {
    setState(() {
      busy = true;
      busyLabel = 'Preparing safe copies';
      progressCurrent = 0;
      progressTotal = ref.read(batchProvider).selectedSafeCount;
    });
    try {
      final paths = await ref
          .read(sessionProvider.notifier)
          .exportSelected(
            onProgress: (current, total) {
              if (mounted) {
                setState(() {
                  progressCurrent = current;
                  progressTotal = total;
                });
              }
            },
          );
      if (paths.isEmpty) {
        throw StateError('No safe copies are selected.');
      }
      await SharePlus.instance.share(
        ShareParams(
          files: [for (final path in paths) XFile(path)],
          text: 'Shared from PrivacyCam',
        ),
      );
    } catch (error) {
      if (mounted) showAdaptiveMessage(context, '$error', error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _discardBatch() async {
    final confirmed = await showAdaptiveActionSheet<bool>(
      context: context,
      title: 'Discard this batch?',
      message: 'All unsaved PrivacyCam edits in this batch will be removed.',
      actions: const [
        AdaptiveAction(
          label: 'Discard batch',
          value: true,
          destructive: true,
          icon: Icons.delete_forever_outlined,
        ),
      ],
    );
    if (confirmed != true || !mounted) return;
    await ref.read(sessionProvider.notifier).clear();
    if (mounted) context.go('/home');
  }
}

class _BatchItemCard extends StatelessWidget {
  const _BatchItemCard({
    required this.index,
    required this.item,
    required this.enabled,
    required this.onOpen,
    required this.onToggleSelected,
    required this.onRetry,
    required this.onSkip,
    required this.onRemove,
  });

  final int index;
  final BatchItem item;
  final bool enabled;
  final VoidCallback onOpen;
  final VoidCallback onToggleSelected;
  final VoidCallback onRetry;
  final VoidCallback onSkip;
  final VoidCallback onRemove;

  bool get canSelect =>
      item.status == BatchItemStatus.safe ||
      item.status == BatchItemStatus.saved;

  @override
  Widget build(BuildContext context) {
    final path = item.session?.sourcePath ?? item.originalPath;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled ? onOpen : null,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 76,
                  height: 76,
                  child: Image.file(
                    File(path),
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const ColoredBox(
                      color: Color(0xFFE7EBE8),
                      child: Icon(Icons.broken_image_outlined),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Photo ${index + 1}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          _statusIcon(item.status),
                          size: 18,
                          color: _statusColor(item.status),
                        ),
                        const SizedBox(width: 6),
                        Expanded(child: Text(_statusLabel(item.status))),
                      ],
                    ),
                    if (item.error != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        item.error!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.redAccent,
                          fontSize: 12,
                        ),
                      ),
                    ],
                    if (item.status == BatchItemStatus.failed ||
                        item.status == BatchItemStatus.skipped)
                      Wrap(
                        spacing: 4,
                        children: [
                          AdaptiveButton(
                            style: AdaptiveButtonStyle.plain,
                            onPressed: enabled ? onRetry : null,
                            child: const Text('Retry'),
                          ),
                          if (item.status == BatchItemStatus.failed)
                            AdaptiveButton(
                              style: AdaptiveButtonStyle.plain,
                              onPressed: enabled ? onSkip : null,
                              child: const Text('Skip'),
                            ),
                          AdaptiveButton(
                            style: AdaptiveButtonStyle.plain,
                            onPressed: enabled ? onRemove : null,
                            child: const Text('Remove'),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              if (canSelect)
                AdaptiveIconButton(
                  tooltip: item.selected
                      ? 'Exclude from batch actions'
                      : 'Include in batch actions',
                  onPressed: enabled ? onToggleSelected : null,
                  icon: Icon(
                    item.selected
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    color: item.selected ? forest : Colors.black38,
                    size: 28,
                  ),
                )
              else
                AdaptiveIconButton(
                  tooltip: 'Remove photo',
                  onPressed: enabled ? onRemove : null,
                  icon: const Icon(Icons.more_vert),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

String _statusLabel(BatchItemStatus status) => switch (status) {
  BatchItemStatus.queued => 'Waiting to scan',
  BatchItemStatus.scanning => 'Scanning',
  BatchItemStatus.needsReview => 'Needs your review',
  BatchItemStatus.safe => 'Safe copy ready',
  BatchItemStatus.saved => 'Saved to gallery',
  BatchItemStatus.failed => 'Could not process',
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
  BatchItemStatus.safe || BatchItemStatus.saved => forest,
  BatchItemStatus.failed => Colors.redAccent,
  BatchItemStatus.needsReview => const Color(0xFF9A6800),
  _ => Colors.black54,
};
