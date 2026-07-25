import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/models.dart';
import '../../state/providers.dart';
import 'adaptive_ui.dart';

enum _NewImageSource { camera, gallery }

class NewImageAction extends ConsumerWidget {
  const NewImageAction({super.key, this.enabled = true});

  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) => AdaptiveIconButton(
    tooltip: 'Start over with another image',
    onPressed: enabled ? () => _chooseAnother(context, ref) : null,
    icon: Icon(
      adaptiveIcon(
        context,
        material: Icons.add_photo_alternate_outlined,
        cupertino: CupertinoIcons.add_circled,
      ),
    ),
  );

  Future<void> _chooseAnother(BuildContext context, WidgetRef ref) async {
    final batch = ref.read(batchProvider);
    final source = await showAdaptiveActionSheet<_NewImageSource>(
      context: context,
      title: batch.isEmpty ? 'Choose an image' : 'Start over?',
      message: batch.isEmpty
          ? 'Take a photo or choose one from your gallery.'
          : 'Choose a new photo to replace your current ${batch.isBatch ? 'batch' : 'photo'}. Nothing is discarded unless you finish choosing or taking a new photo.',
      cancelLabel: 'Keep editing this image',
      actions: const [
        AdaptiveAction(
          label: 'Take a new photo',
          value: _NewImageSource.camera,
          icon: Icons.camera_alt_rounded,
        ),
        AdaptiveAction(
          label: 'Choose one photo',
          value: _NewImageSource.gallery,
          icon: Icons.photo_library_outlined,
        ),
      ],
    );
    if (source == null || !context.mounted) return;

    try {
      final router = GoRouter.of(context);
      final path = switch (source) {
        _NewImageSource.camera => await router.push<String>('/camera'),
        _NewImageSource.gallery =>
          await ref.read(imageIoProvider).pickGalleryPath(),
      };
      if (path != null && context.mounted) {
        router.go('/scan', extra: BatchScanRequest(paths: [path]));
      }
    } catch (error) {
      if (!context.mounted) return;
      showAdaptiveMessage(context, error.toString(), error: true);
    }
  }
}
