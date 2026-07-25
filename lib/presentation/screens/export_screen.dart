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

class ExportScreen extends ConsumerStatefulWidget {
  const ExportScreen({super.key});

  @override
  ConsumerState<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends ConsumerState<ExportScreen> {
  late RedactionStyle effect;
  late double blurStrength;
  late double pixelSize;
  bool updatingPreview = false;
  bool finalizing = false;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsProvider);
    final session = ref.read(sessionProvider);
    final hasBlur =
        session?.items.any(
          (item) => item.selected && item.style == RedactionStyle.blur,
        ) ??
        false;
    effect = hasBlur ? RedactionStyle.blur : RedactionStyle.pixelate;
    blurStrength = settings.blurStrength;
    pixelSize = settings.pixelSize;
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final imagePath = session?.previewPath ?? session?.exportPath;
    if (session == null || imagePath == null) {
      return const Scaffold(
        body: Center(child: Text('No privacy preview available.')),
      );
    }
    final count =
        session.items.where((item) => item.selected).length +
        session.strokes.length;
    final busy = updatingPreview || finalizing;
    final batch = ref.watch(batchProvider);
    final nextReviewIndex = ref
        .read(sessionProvider.notifier)
        .nextNeedsReviewIndex();

    return Scaffold(
      appBar: adaptiveNavigationBar(
        context,
        title: const Text('Privacy-safe preview'),
        actions: [NewImageAction(enabled: !busy)],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                Expanded(
                  flex: 5,
                  child: Container(
                    color: Colors.black87,
                    width: double.infinity,
                    child: Image.file(
                      File(imagePath),
                      key: ValueKey(imagePath),
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                    ),
                  ),
                ),
                Flexible(
                  flex: 4,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.verified_user_outlined,
                              color: forest,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                '$count items hidden',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Icon(
                              Icons.location_off_outlined,
                              color: forest,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                session.metadataRemoved
                                    ? 'Location and EXIF metadata removed'
                                    : 'Metadata will be removed when saved or shared',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.photo_size_select_large_outlined),
                            const SizedBox(width: 12),
                            Text(
                              'Full-resolution save: '
                              '${session.width} × ${session.height}',
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        if (batch.isBatch) ...[
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Photo ${batch.activeIndex + 1} of ${batch.items.length}',
                              style: const TextStyle(
                                color: forest,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],
                        _strengthCard(),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: AdaptiveButton(
                                onPressed: busy ? null : _save,
                                icon: Icon(
                                  adaptiveIcon(
                                    context,
                                    material: Icons.download_outlined,
                                    cupertino:
                                        CupertinoIcons.arrow_down_to_line,
                                  ),
                                ),
                                child: const Text('Save'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: AdaptiveButton(
                                style: AdaptiveButtonStyle.secondary,
                                onPressed: busy ? null : _share,
                                icon: Icon(
                                  adaptiveIcon(
                                    context,
                                    material: Icons.share_outlined,
                                    cupertino: CupertinoIcons.share,
                                  ),
                                ),
                                child: const Text('Share'),
                              ),
                            ),
                          ],
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            AdaptiveButton(
                              style: AdaptiveButtonStyle.plain,
                              onPressed: busy ? null : () => context.pop(),
                              child: const Text('Edit again'),
                            ),
                            AdaptiveButton(
                              style: AdaptiveButtonStyle.plain,
                              onPressed: busy
                                  ? null
                                  : () async {
                                      if (batch.isBatch) {
                                        context.push('/batch');
                                      } else {
                                        await ref
                                            .read(sessionProvider.notifier)
                                            .clear();
                                        if (context.mounted) {
                                          context.go('/home');
                                        }
                                      }
                                    },
                              child: Text(
                                batch.isBatch ? 'Batch overview' : 'Start over',
                              ),
                            ),
                          ],
                        ),
                        if (batch.isBatch && nextReviewIndex != null)
                          AdaptiveButton(
                            onPressed: busy
                                ? null
                                : () {
                                    ref
                                        .read(sessionProvider.notifier)
                                        .activate(nextReviewIndex);
                                    context.go('/review');
                                  },
                            icon: const Icon(Icons.arrow_forward_rounded),
                            child: const Text('Review next photo'),
                          ),
                      ],
                    ),
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
                      child: PrivacyLoader(
                        label: finalizing
                            ? 'Creating full-resolution copy'
                            : 'Updating preview',
                        detail: finalizing
                            ? 'Applying final redactions and removing metadata'
                            : 'Applying your new effect strength',
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

  Widget _strengthCard() {
    final isBlur = effect == RedactionStyle.blur;
    final value = isBlur ? blurStrength : pixelSize;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: mint.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Adjust effect strength',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                AdaptiveSegmentedControl<RedactionStyle>(
                  value: effect,
                  enabled: !updatingPreview && !finalizing,
                  children: const {
                    RedactionStyle.blur: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 5),
                      child: Text('Blur'),
                    ),
                    RedactionStyle.pixelate: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 5),
                      child: Text('Pixelate'),
                    ),
                  },
                  onChanged: (value) => setState(() => effect = value),
                ),
              ],
            ),
            Row(
              children: [
                Icon(
                  isBlur ? Icons.blur_on_outlined : Icons.grid_4x4_outlined,
                  size: 20,
                ),
                Expanded(
                  child: AdaptiveSlider(
                    value: value,
                    min: isBlur ? 2 : 4,
                    max: isBlur ? 64 : 80,
                    divisions: isBlur ? 31 : 38,
                    label: isBlur
                        ? value.round().toString()
                        : '${value.round()} px',
                    onChanged: updatingPreview || finalizing
                        ? null
                        : (next) => setState(() {
                            if (isBlur) {
                              blurStrength = next;
                            } else {
                              pixelSize = next;
                            }
                          }),
                    onChangeEnd: updatingPreview || finalizing
                        ? null
                        : (_) => _updatePreview(),
                  ),
                ),
                SizedBox(
                  width: 46,
                  child: Text(
                    isBlur ? '${value.round()}' : '${value.round()} px',
                    textAlign: TextAlign.end,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 30),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [Text('Gentle'), Text('Strong')],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _updatePreview() async {
    if (updatingPreview || finalizing) return;
    setState(() => updatingPreview = true);
    try {
      final settings = ref.read(settingsProvider);
      await ref
          .read(settingsProvider.notifier)
          .update(
            settings.copyWith(blurStrength: blurStrength, pixelSize: pixelSize),
          );
      await ref.read(sessionProvider.notifier).preview();
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => updatingPreview = false);
    }
  }

  Future<String> _ensureFullExport() async {
    final existing = ref.read(sessionProvider)?.exportPath;
    if (existing != null) return existing;
    setState(() => finalizing = true);
    try {
      await ref.read(sessionProvider.notifier).export();
      final path = ref.read(sessionProvider)?.exportPath;
      if (path == null) throw StateError('The safe copy could not be created.');
      return path;
    } finally {
      if (mounted) setState(() => finalizing = false);
    }
  }

  Future<void> _save() async {
    try {
      final path = await _ensureFullExport();
      await ref.read(imageIoProvider).saveToGallery(path);
      if (mounted) {
        ref.read(sessionProvider.notifier).markActiveSaved();
        showAdaptiveMessage(context, 'Saved to your photo gallery.');
      }
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _share() async {
    try {
      final path = await _ensureFullExport();
      await SharePlus.instance.share(
        ShareParams(files: [XFile(path)], text: 'Shared from PrivacyCam'),
      );
    } catch (error) {
      _showError(error);
    }
  }

  void _showError(Object error) {
    if (!mounted) return;
    showAdaptiveMessage(context, error.toString(), error: true);
  }
}
