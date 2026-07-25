import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_handler/share_handler.dart';

import 'core/router.dart';
import 'core/theme.dart';
import 'domain/models.dart';
import 'state/pdf_providers.dart';
import 'state/providers.dart';
import 'state/video_providers.dart';

class PrivacyCamApp extends ConsumerWidget {
  const PrivacyCamApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    ref.watch(proPurchaseProvider);
    ref.listen(incomingShareProvider, (_, next) {
      next.whenData((media) async {
        final files =
            media.attachments?.whereType<SharedAttachment>().toList() ?? [];
        if (files.isEmpty || files.length > 10) return;
        if (files.length == 1 &&
            files.single.type == SharedAttachmentType.file &&
            files.single.path.toLowerCase().endsWith('.pdf')) {
          await ShareHandler.instance.resetInitialSharedMedia();
          await ref.read(sessionProvider.notifier).clear();
          await ref.read(videoEditorProvider.notifier).clear();
          await ref.read(pdfSessionProvider.notifier).clear();
          router.go('/pdf/scan', extra: files.single.path);
          return;
        }
        if (files.any((file) => file.type != SharedAttachmentType.image)) {
          return;
        }
        await ShareHandler.instance.resetInitialSharedMedia();
        await ref.read(pdfSessionProvider.notifier).clear();
        final batch = ref.read(batchProvider);
        final remaining = 10 - batch.items.length;
        if (remaining <= 0) {
          router.go('/batch');
          return;
        }
        final request = BatchScanRequest(
          paths: [for (final file in files.take(remaining)) file.path],
          append: !batch.isEmpty,
        );
        final wouldCreateBatch = batch.items.length + request.paths.length > 1;
        router.go(
          wouldCreateBatch && !ref.read(batchAccessProvider) ? '/pro' : '/scan',
          extra: request,
        );
      });
    });
    return MaterialApp.router(
      title: 'PrivacyCam',
      debugShowCheckedModeBanner: false,
      theme: privacyCamTheme(defaultTargetPlatform),
      routerConfig: router,
    );
  }
}
