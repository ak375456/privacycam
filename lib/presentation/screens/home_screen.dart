import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme.dart';
import '../../domain/models.dart';
import '../../domain/video_models.dart';
import '../../domain/pdf_models.dart';
import '../../state/pdf_providers.dart';
import '../../state/providers.dart';
import '../../state/video_providers.dart';
import '../widgets/adaptive_ui.dart';
import '../widgets/privacy_showcase.dart';

enum _HomeAction { camera, gallery, videoCamera, videoGallery, batch, pdf }

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  _HomeAction? _busyAction;

  @override
  void initState() {
    super.initState();
    Future.microtask(_recoverInterruptedVideoPick);
  }

  Future<void> _recoverInterruptedVideoPick() async {
    if (_busyAction != null) return;
    try {
      final path = await ref.read(videoServiceProvider).recoverLostVideo();
      if (path == null || !mounted) return;
      setState(() => _busyAction = _HomeAction.videoGallery);
      await ref.read(sessionProvider.notifier).clear();
      await ref.read(videoEditorProvider.notifier).clear();
      if (mounted) context.go('/video/scan', extra: path);
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _busyAction = null);
    }
  }

  Future<void> _takePhoto() async {
    if (_busyAction != null) return;
    if (!await _confirmNewWork() || !mounted) return;
    setState(() => _busyAction = _HomeAction.camera);
    try {
      final path = await context.push<String>('/camera');
      if (path != null && mounted) {
        await ref.read(videoEditorProvider.notifier).clear();
        await ref.read(pdfSessionProvider.notifier).clear();
        if (!mounted) return;
        context.go('/scan', extra: BatchScanRequest(paths: [path]));
      }
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _busyAction = null);
    }
  }

  Future<void> _chooseFromGallery() async {
    if (_busyAction != null) return;
    if (!await _confirmNewWork() || !mounted) return;
    setState(() => _busyAction = _HomeAction.gallery);
    try {
      final path = await ref.read(imageIoProvider).pickGalleryPath();
      if (path != null && mounted) {
        await ref.read(videoEditorProvider.notifier).clear();
        await ref.read(pdfSessionProvider.notifier).clear();
        if (!mounted) return;
        context.go('/scan', extra: BatchScanRequest(paths: [path]));
      }
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _busyAction = null);
    }
  }

  Future<void> _chooseBatch() async {
    if (_busyAction != null) return;
    if (!ref.read(batchAccessProvider)) {
      final unlocked = await context.push<bool>('/pro');
      if (unlocked != true || !mounted) return;
    }
    if (!await _confirmNewWork() || !mounted) return;
    setState(() => _busyAction = _HomeAction.batch);
    try {
      final paths = await ref.read(imageIoProvider).pickGalleryPaths(limit: 10);
      if (paths.isNotEmpty && mounted) {
        await ref.read(videoEditorProvider.notifier).clear();
        await ref.read(pdfSessionProvider.notifier).clear();
        if (!mounted) return;
        context.go('/scan', extra: BatchScanRequest(paths: paths));
      }
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _busyAction = null);
    }
  }

  void _showError(Object error) =>
      showAdaptiveMessage(context, error.toString(), error: true);

  Future<void> _chooseVideo(ImageSource source) async {
    if (_busyAction != null) return;
    if (!await _confirmNewWork() || !mounted) return;
    final action = source == ImageSource.camera
        ? _HomeAction.videoCamera
        : _HomeAction.videoGallery;
    setState(() => _busyAction = action);
    try {
      final path = await ref.read(videoServiceProvider).pickVideo(source);
      if (path != null && mounted) {
        await ref.read(sessionProvider.notifier).clear();
        await ref.read(videoEditorProvider.notifier).clear();
        await ref.read(pdfSessionProvider.notifier).clear();
        if (!mounted) return;
        context.go('/video/scan', extra: path);
      }
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _busyAction = null);
    }
  }

  Future<bool> _confirmNewWork() async {
    final batch = ref.read(batchProvider);
    final video = ref.read(videoEditorProvider).session;
    final pdf = ref.read(pdfSessionProvider);
    if (batch.isEmpty && video == null && pdf == null) return true;
    final confirmed = await showAdaptiveActionSheet<bool>(
      context: context,
      title: 'Start over?',
      message: pdf != null
          ? 'Your current PDF and any unsaved PrivacyCam edits will be discarded.'
          : video != null
          ? 'Your current video and any unsaved PrivacyCam edits will be discarded.'
          : batch.isBatch
          ? 'Your current batch and any unsaved PrivacyCam edits will be discarded.'
          : 'Your current photo and any unsaved PrivacyCam edits will be discarded.',
      actions: const [
        AdaptiveAction(
          label: 'Discard and start over',
          value: true,
          destructive: true,
          icon: Icons.restart_alt_rounded,
        ),
      ],
      cancelLabel: pdf != null
          ? 'Keep current PDF'
          : video != null
          ? 'Keep current video'
          : batch.isBatch
          ? 'Keep current batch'
          : 'Keep current photo',
    );
    if (confirmed != true) return false;
    return true;
  }

  Future<void> _resumeBatch() async {
    final batch = ref.read(batchProvider);
    if (batch.isBatch && !ref.read(batchAccessProvider)) {
      final unlocked = await context.push<bool>('/pro');
      if (unlocked != true || !mounted) return;
    }
    if (mounted) context.push('/batch');
  }

  Future<void> _resumeVideo() async {
    final session = ref.read(videoEditorProvider).session;
    if (session == null) return;
    if (privacyCamVideoSessionRequiresPro(session) &&
        !ref.read(proAccessProvider)) {
      context.push('/video/trim');
      return;
    }
    if (session.tracks.isEmpty) {
      context.push('/video/scan', extra: session.sourcePath);
    } else {
      context.push('/video/editor');
    }
  }

  Future<void> _choosePdf() async {
    if (_busyAction != null) return;
    if (!await _confirmNewWork() || !mounted) return;
    setState(() => _busyAction = _HomeAction.pdf);
    try {
      final path = await ref.read(pdfServiceProvider).pickPdf();
      if (path == null || !mounted) return;
      final inspection = await ref.read(pdfServiceProvider).inspect(path);
      if (!mounted) return;
      if (inspection.pageCount > pdfFreePageLimit &&
          !ref.read(batchAccessProvider)) {
        final unlocked = await context.push<bool>('/pro');
        if (unlocked != true || !mounted) return;
      }
      await ref.read(sessionProvider.notifier).clear();
      await ref.read(videoEditorProvider.notifier).clear();
      await ref.read(pdfSessionProvider.notifier).clear();
      if (mounted) context.go('/pdf/scan', extra: path);
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _busyAction = null);
    }
  }

  void _resumePdf() {
    final document = ref.read(pdfSessionProvider);
    if (document == null) return;
    context.push(
      document.status == PdfWorkStatus.exported
          ? '/pdf/export'
          : document.status == PdfWorkStatus.ready
          ? '/pdf/editor'
          : '/pdf/review',
    );
  }

  @override
  Widget build(BuildContext context) {
    final batch = ref.watch(batchProvider);
    final video = ref.watch(videoEditorProvider).session;
    final pdf = ref.watch(pdfSessionProvider);
    final hasBatchAccess = ref.watch(batchAccessProvider);
    return Scaffold(
      appBar: adaptiveNavigationBar(
        context,
        title: const Text('PrivacyCam'),
        automaticallyImplyLeading: false,
        actions: [
          AdaptiveIconButton(
            tooltip: 'Settings',
            onPressed: () => context.push('/settings'),
            icon: Icon(
              adaptiveIcon(
                context,
                material: Icons.settings_outlined,
                cupertino: CupertinoIcons.settings,
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            if (!batch.isEmpty) ...[
              _ResumeBatchCard(batch: batch, onPressed: _resumeBatch),
              const SizedBox(height: 18),
            ],
            if (video != null) ...[
              _ResumeVideoCard(session: video, onPressed: _resumeVideo),
              const SizedBox(height: 18),
            ],
            if (pdf != null) ...[
              _ResumePdfCard(document: pdf, onPressed: _resumePdf),
              const SizedBox(height: 18),
            ],
            Text(
              'Share with confidence.',
              style: Theme.of(context).textTheme.displaySmall,
            ),
            const SizedBox(height: 10),
            const Text(
              'Protect photos, short videos, and PDFs before sharing. PrivacyCam checks them on this device.',
              style: TextStyle(
                fontSize: 17,
                height: 1.4,
                color: Color(0xFF52615D),
              ),
            ),
            const SizedBox(height: 20),
            _PhotoActions(
              busyAction: _busyAction,
              onTakePhoto: _takePhoto,
              onChoosePhoto: _chooseFromGallery,
            ),
            const SizedBox(height: 7),
            const Text(
              'Photos and screenshots are available in the same gallery.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.black54),
            ),
            const SizedBox(height: 20),
            _VideoActionsCard(
              busyAction: _busyAction,
              pro: hasBatchAccess,
              onRecord: () => _chooseVideo(ImageSource.camera),
              onChoose: () => _chooseVideo(ImageSource.gallery),
            ),
            const SizedBox(height: 20),
            _PdfActionsCard(
              busy: _busyAction == _HomeAction.pdf,
              enabled: _busyAction == null,
              pro: hasBatchAccess,
              onPressed: _choosePdf,
            ),
            const SizedBox(height: 20),
            const PrivacyShowcase(),
            const SizedBox(height: 18),
            _BatchProCard(
              unlocked: hasBatchAccess,
              busy: _busyAction == _HomeAction.batch,
              enabled: _busyAction == null,
              onPressed: _chooseBatch,
            ),
            const SizedBox(height: 24),
            const _ExpectationCard(),
            const SizedBox(height: 14),
            const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, color: Colors.black45, size: 19),
                SizedBox(width: 9),
                Expanded(
                  child: Text(
                    'Automatic detection can miss details. You always review the result before saving or sharing.',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.black54,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ResumePdfCard extends StatelessWidget {
  const _ResumePdfCard({required this.document, required this.onPressed});

  final PdfSession document;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: mint,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const Color(0xFFB2D8CA)),
    ),
    child: Row(
      children: [
        const Icon(Icons.picture_as_pdf_outlined, color: forest, size: 30),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Resume current PDF',
                style: TextStyle(color: ink, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 3),
              Text(
                '${document.pageCount} pages · ${document.selectedCount} items hidden',
                style: const TextStyle(color: Color(0xFF52615D)),
              ),
            ],
          ),
        ),
        AdaptiveButton(
          style: AdaptiveButtonStyle.plain,
          onPressed: onPressed,
          child: const Text('Open'),
        ),
      ],
    ),
  );
}

class _PdfActionsCard extends StatelessWidget {
  const _PdfActionsCard({
    required this.busy,
    required this.enabled,
    required this.pro,
    required this.onPressed,
  });

  final bool busy;
  final bool enabled;
  final bool pro;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(17),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: const Color(0xFFE0E6E2)),
    ),
    child: Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: mint,
            borderRadius: BorderRadius.circular(15),
          ),
          child: const Icon(Icons.picture_as_pdf_outlined, color: forest),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Protect a PDF',
                style: TextStyle(
                  color: ink,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                pro
                    ? 'Review and flatten every page'
                    : 'Up to 2 pages free · More with Pro',
                style: const TextStyle(color: Color(0xFF52615D)),
              ),
            ],
          ),
        ),
        AdaptiveButton(
          style: AdaptiveButtonStyle.secondary,
          onPressed: enabled ? onPressed : null,
          icon: busy
              ? const AdaptiveProgressIndicator(dimension: 18)
              : const Icon(Icons.file_open_outlined),
          child: const Text('Choose'),
        ),
      ],
    ),
  );
}

class _ResumeBatchCard extends StatelessWidget {
  const _ResumeBatchCard({required this.batch, required this.onPressed});

  final BatchSnapshot batch;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: mint,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const Color(0xFFB2D8CA)),
    ),
    child: Row(
      children: [
        const Icon(Icons.collections_outlined, color: forest, size: 30),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                batch.isBatch
                    ? 'Resume ${batch.items.length}-photo batch'
                    : 'Resume current photo',
                style: const TextStyle(color: ink, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 3),
              Text(
                '${batch.safeCount} safe · ${batch.needsReviewCount} need review',
                style: const TextStyle(color: Color(0xFF52615D)),
              ),
            ],
          ),
        ),
        AdaptiveButton(
          style: AdaptiveButtonStyle.plain,
          onPressed: onPressed,
          child: const Text('Open'),
        ),
      ],
    ),
  );
}

class _ResumeVideoCard extends StatelessWidget {
  const _ResumeVideoCard({required this.session, required this.onPressed});

  final VideoSession session;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: mint,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const Color(0xFFB2D8CA)),
    ),
    child: Row(
      children: [
        const Icon(Icons.video_library_outlined, color: forest, size: 30),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Resume current video',
                style: TextStyle(color: ink, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 3),
              Text(
                '${session.tracks.length} privacy tracks · up to 60 seconds',
                style: const TextStyle(color: Color(0xFF52615D)),
              ),
            ],
          ),
        ),
        AdaptiveButton(
          style: AdaptiveButtonStyle.plain,
          onPressed: onPressed,
          child: const Text('Open'),
        ),
      ],
    ),
  );
}

class _VideoActionsCard extends StatelessWidget {
  const _VideoActionsCard({
    required this.busyAction,
    required this.pro,
    required this.onRecord,
    required this.onChoose,
  });

  final _HomeAction? busyAction;
  final bool pro;
  final VoidCallback onRecord;
  final VoidCallback onChoose;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFFF5F7F6),
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: const Color(0xFFDDE5E1)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.movie_filter_outlined, color: forest),
            SizedBox(width: 9),
            Text(
              'Protect a video',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
          ],
        ),
        const SizedBox(height: 5),
        Text(
          pro
              ? 'Pro unlocked · Protect clips up to 60 seconds.'
              : 'Up to 15 seconds free · Up to 60 seconds with Pro.',
          style: TextStyle(color: Color(0xFF52615D), height: 1.35),
        ),
        const SizedBox(height: 11),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
          decoration: BoxDecoration(
            color: mint.withValues(alpha: .28),
            borderRadius: BorderRadius.circular(13),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.center_focus_strong_outlined, color: forest, size: 20),
              SizedBox(width: 9),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: 'For best tracking: ',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      TextSpan(
                        text:
                            'hold steady, move slowly, use good light, and keep faces fully inside the frame.',
                      ),
                    ],
                  ),
                  style: TextStyle(
                    color: Color(0xFF28443B),
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 13),
        Row(
          children: [
            Expanded(
              child: AdaptiveButton(
                style: AdaptiveButtonStyle.secondary,
                onPressed: busyAction == null ? onRecord : null,
                icon: busyAction == _HomeAction.videoCamera
                    ? const AdaptiveProgressIndicator(dimension: 19)
                    : const Icon(Icons.videocam_outlined),
                child: Text(
                  busyAction == _HomeAction.videoCamera ? 'Opening…' : 'Record',
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: AdaptiveButton(
                style: AdaptiveButtonStyle.secondary,
                onPressed: busyAction == null ? onChoose : null,
                icon: busyAction == _HomeAction.videoGallery
                    ? const AdaptiveProgressIndicator(dimension: 19)
                    : const Icon(Icons.video_library_outlined),
                child: Text(
                  busyAction == _HomeAction.videoGallery
                      ? 'Opening…'
                      : 'Choose',
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _BatchProCard extends StatelessWidget {
  const _BatchProCard({
    required this.unlocked,
    required this.busy,
    required this.enabled,
    required this.onPressed,
  });

  final bool unlocked;
  final bool busy;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(17),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFF2F8F5), Color(0xFFE1F2EB)],
      ),
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: const Color(0xFFB9DCCF)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: forest,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                unlocked
                    ? Icons.collections_outlined
                    : Icons.workspace_premium_outlined,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    unlocked ? 'Batch mode' : 'PrivacyCam Pro',
                    style: const TextStyle(
                      color: ink,
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Process up to 10 photos together',
                    style: TextStyle(color: Color(0xFF52615D)),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: AdaptiveButton(
            style: unlocked
                ? AdaptiveButtonStyle.secondary
                : AdaptiveButtonStyle.primary,
            onPressed: enabled ? onPressed : null,
            icon: busy
                ? const AdaptiveProgressIndicator(dimension: 19)
                : Icon(
                    unlocked
                        ? Icons.photo_library_outlined
                        : Icons.auto_awesome_rounded,
                  ),
            child: Text(
              busy
                  ? 'Opening gallery…'
                  : unlocked
                  ? 'Choose up to 10 photos'
                  : 'See lifetime Pro',
            ),
          ),
        ),
      ],
    ),
  );
}

class _PhotoActions extends StatelessWidget {
  const _PhotoActions({
    required this.busyAction,
    required this.onTakePhoto,
    required this.onChoosePhoto,
  });

  final _HomeAction? busyAction;
  final VoidCallback onTakePhoto;
  final VoidCallback onChoosePhoto;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Expanded(
        child: AdaptiveButton(
          onPressed: busyAction == null ? onTakePhoto : null,
          icon: busyAction == _HomeAction.camera
              ? const AdaptiveProgressIndicator(
                  color: Colors.white,
                  dimension: 19,
                )
              : Icon(
                  adaptiveIcon(
                    context,
                    material: Icons.camera_alt_rounded,
                    cupertino: CupertinoIcons.camera_fill,
                  ),
                ),
          child: Text(
            busyAction == _HomeAction.camera ? 'Opening…' : 'Take photo',
          ),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: AdaptiveButton(
          style: AdaptiveButtonStyle.secondary,
          onPressed: busyAction == null ? onChoosePhoto : null,
          icon: busyAction == _HomeAction.gallery
              ? const AdaptiveProgressIndicator(dimension: 19)
              : Icon(
                  adaptiveIcon(
                    context,
                    material: Icons.photo_library_outlined,
                    cupertino: CupertinoIcons.photo_on_rectangle,
                  ),
                ),
          child: Text(
            busyAction == _HomeAction.gallery ? 'Opening…' : 'Choose photo',
          ),
        ),
      ),
    ],
  );
}

class _ExpectationCard extends StatelessWidget {
  const _ExpectationCard();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(18, 17, 18, 16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: const Color(0xFFE0E6E2)),
    ),
    child: const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'What happens next',
          style: TextStyle(
            color: ink,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
        SizedBox(height: 14),
        _ExpectationRow(
          icon: Icons.auto_awesome_outlined,
          text: 'The photo is scanned on this device.',
        ),
        SizedBox(height: 11),
        _ExpectationRow(
          icon: Icons.visibility_outlined,
          text: 'You review and adjust every hidden area.',
        ),
        SizedBox(height: 11),
        _ExpectationRow(
          icon: Icons.cloud_off_outlined,
          text: 'Nothing is uploaded or shared automatically.',
        ),
      ],
    ),
  );
}

class _ExpectationRow extends StatelessWidget {
  const _ExpectationRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 34,
        height: 34,
        decoration: const BoxDecoration(color: mint, shape: BoxShape.circle),
        child: Icon(icon, color: forest, size: 19),
      ),
      const SizedBox(width: 11),
      Expanded(child: Text(text, style: const TextStyle(height: 1.3))),
    ],
  );
}
