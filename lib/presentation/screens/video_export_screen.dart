import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../../core/theme.dart';
import '../../domain/video_models.dart';
import '../../state/video_providers.dart';
import '../widgets/adaptive_ui.dart';
import '../widgets/privacy_loader.dart';

class VideoExportScreen extends ConsumerStatefulWidget {
  const VideoExportScreen({super.key});

  @override
  ConsumerState<VideoExportScreen> createState() => _VideoExportScreenState();
}

class _VideoExportScreenState extends ConsumerState<VideoExportScreen> {
  VideoPlayerController? _preview;
  bool _saving = false;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    Future.microtask(_export);
  }

  Future<void> _export() async {
    try {
      await ref.read(videoEditorProvider.notifier).export();
      if (!mounted) return;
      final path = ref.read(videoEditorProvider).session?.exportPath;
      if (path == null) return;
      final preview = VideoPlayerController.file(File(path));
      await preview.initialize();
      preview.setLooping(true);
      preview.addListener(_previewChanged);
      if (!mounted) {
        await preview.dispose();
        return;
      }
      setState(() => _preview = preview);
    } catch (_) {
      // The controller exposes the sanitized error.
    }
  }

  @override
  void dispose() {
    _preview?.removeListener(_previewChanged);
    unawaited(_preview?.dispose());
    super.dispose();
  }

  void _previewChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _save() async {
    final path = ref.read(videoEditorProvider).session?.exportPath;
    if (path == null || _saving) return;
    setState(() => _saving = true);
    try {
      await ref.read(videoServiceProvider).saveToGallery(path);
      if (mounted) showAdaptiveMessage(context, 'Privacy-safe video saved.');
    } catch (error) {
      if (mounted) showAdaptiveMessage(context, error.toString(), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _share() async {
    final path = ref.read(videoEditorProvider).session?.exportPath;
    if (path == null || _saving) return;
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(path)],
        text: 'Shared privately with PrivacyCam',
      ),
    );
  }

  Future<void> _startOver() async {
    await ref.read(videoEditorProvider.notifier).clear();
    if (mounted) context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(videoEditorProvider);
    final session = state.session;
    final failed = state.stage == VideoWorkStage.failed;
    final complete =
        state.stage == VideoWorkStage.complete && session?.exportPath != null;
    return Scaffold(
      appBar: adaptiveNavigationBar(
        context,
        title: Text(complete ? 'Privacy-safe video' : 'Creating safe video'),
        actions: complete
            ? [
                AdaptiveIconButton(
                  tooltip: 'Start over',
                  onPressed: _saving ? null : _startOver,
                  icon: Icon(
                    adaptiveIcon(
                      context,
                      material: Icons.add_circle_outline,
                      cupertino: CupertinoIcons.add_circled,
                    ),
                  ),
                ),
              ]
            : [],
      ),
      body: SafeArea(
        child: failed
            ? _failure(state.error)
            : !complete
            ? _progress(state)
            : _result(session!),
      ),
    );
  }

  Widget _progress(VideoEditorState state) => Padding(
    padding: const EdgeInsets.all(28),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const PrivacyLoader(
            label: 'Creating your privacy-safe video',
            detail: 'Redactions are applied to every frame',
          ),
          const SizedBox(height: 28),
          LinearProgressIndicator(
            value: state.progress.clamp(0, 1),
            minHeight: 9,
          ),
          const SizedBox(height: 12),
          Text(state.detail, textAlign: TextAlign.center),
          const SizedBox(height: 22),
          AdaptiveButton(
            style: AdaptiveButtonStyle.plain,
            onPressed: () async {
              await ref.read(videoEditorProvider.notifier).cancelWork();
              if (mounted) context.pop();
            },
            child: const Text('Cancel export'),
          ),
          const SizedBox(height: 12),
          const Text(
            'Keep PrivacyCam open until export finishes. Longer clips take more time than photos.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.black54),
          ),
        ],
      ),
    ),
  );

  Widget _failure(String? error) => Padding(
    padding: const EdgeInsets.all(28),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 56),
          const SizedBox(height: 16),
          Text(
            'Export stopped',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 10),
          Text(
            error ?? 'The privacy-safe video could not be created.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 22),
          AdaptiveButton(
            onPressed: () => context.pop(),
            child: const Text('Return to editor'),
          ),
        ],
      ),
    ),
  );

  Widget _result(VideoSession session) => Column(
    children: [
      Expanded(
        child: ColoredBox(
          color: Colors.black,
          child: Center(
            child: _preview == null
                ? const AdaptiveProgressIndicator(
                    color: Colors.white,
                    dimension: 32,
                  )
                : GestureDetector(
                    onTap: () => setState(() {
                      _preview!.value.isPlaying
                          ? _preview!.pause()
                          : _preview!.play();
                    }),
                    child: AspectRatio(
                      aspectRatio: _preview!.value.aspectRatio,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          VideoPlayer(_preview!),
                          if (!_preview!.value.isPlaying)
                            const Center(
                              child: Icon(
                                Icons.play_circle_fill_rounded,
                                color: Colors.white,
                                size: 66,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 22),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.verified_user_outlined, color: forest),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${session.tracks.where((track) => track.selected).length} privacy tracks applied',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Row(
              children: [
                Icon(Icons.location_off_outlined, color: forest),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Location and container metadata removed and verified',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(
                  session.hasAudio && !session.resolvedEditPlan.audioMuted
                      ? Icons.volume_up_outlined
                      : Icons.volume_off_outlined,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    session.resolvedEditPlan.audioMuted
                        ? 'Audio removed from the exported video'
                        : session.hasAudio
                        ? 'Original audio kept — audio content was not checked'
                        : 'This video has no audio track',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: AdaptiveButton(
                    onPressed: _saving ? null : _save,
                    icon: const Icon(Icons.download_outlined),
                    child: Text(_saving ? 'Saving…' : 'Save'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: AdaptiveButton(
                    style: AdaptiveButtonStyle.secondary,
                    onPressed: _saving ? null : _share,
                    icon: const Icon(Icons.share_outlined),
                    child: const Text('Share'),
                  ),
                ),
              ],
            ),
            AdaptiveButton(
              style: AdaptiveButtonStyle.plain,
              onPressed: _saving ? null : () => context.pop(),
              child: const Text('Edit again'),
            ),
          ],
        ),
      ),
    ],
  );
}
