import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';

import '../../core/theme.dart';
import '../../domain/video_models.dart';
import '../../state/video_providers.dart';
import '../widgets/adaptive_ui.dart';

class VideoClipSelectionScreen extends ConsumerStatefulWidget {
  const VideoClipSelectionScreen({super.key});

  @override
  ConsumerState<VideoClipSelectionScreen> createState() =>
      _VideoClipSelectionScreenState();
}

class _VideoClipSelectionScreenState
    extends ConsumerState<VideoClipSelectionScreen> {
  VideoPlayerController? _player;
  late RangeValues _selection;
  bool _ready = false;
  bool _correctingPlayback = false;

  @override
  void initState() {
    super.initState();
    final session = ref.read(videoEditorProvider).session;
    if (session != null) {
      final plan = session.resolvedEditPlan;
      final outputDuration = plan.outputDurationMs(session.durationMs);
      _selection = outputDuration <= privacyCamVideoFreeMaxDurationMs
          ? RangeValues(plan.trimStartMs.toDouble(), plan.trimEndMs.toDouble())
          : RangeValues(
              0,
              min(
                session.durationMs,
                privacyCamVideoFreeMaxDurationMs,
              ).toDouble(),
            );
      unawaited(_initializePlayer(session));
    } else {
      _selection = const RangeValues(0, 1);
    }
  }

  Future<void> _initializePlayer(VideoSession session) async {
    final player = VideoPlayerController.file(File(session.sourcePath));
    await player.initialize();
    player.addListener(_keepPlaybackInsideSelection);
    await player.seekTo(Duration(milliseconds: _selection.start.round()));
    if (!mounted) {
      await player.dispose();
      return;
    }
    setState(() {
      _player = player;
      _ready = true;
    });
  }

  void _keepPlaybackInsideSelection() {
    final player = _player;
    if (player == null || !player.value.isInitialized) return;
    if (!_correctingPlayback &&
        player.value.position.inMilliseconds >= _selection.end.round()) {
      _correctingPlayback = true;
      unawaited(
        player
            .pause()
            .then(
              (_) => player.seekTo(
                Duration(milliseconds: _selection.start.round()),
              ),
            )
            .whenComplete(() => _correctingPlayback = false),
      );
    }
  }

  @override
  void dispose() {
    _player?.removeListener(_keepPlaybackInsideSelection);
    unawaited(_player?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(videoEditorProvider).session;
    if (session == null) {
      return const Scaffold(body: Center(child: Text('No video selected.')));
    }
    final duration = session.durationMs.toDouble();
    final selectedDuration = (_selection.end - _selection.start).round();
    return Scaffold(
      appBar: adaptiveNavigationBar(
        context,
        title: const Text('Choose a free clip'),
        automaticallyImplyLeading: false,
        leading: AdaptiveIconButton(
          tooltip: 'Discard video',
          onPressed: _discard,
          icon: Icon(
            adaptiveIcon(
              context,
              material: Icons.close_rounded,
              cupertino: CupertinoIcons.xmark,
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: mint,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFB2D8CA)),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.content_cut_rounded, color: forest),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'The free version can protect any section up to 15 seconds. Choose the part you need before on-device analysis starts.',
                      style: TextStyle(height: 1.35),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            AspectRatio(
              aspectRatio: _ready ? _player!.value.aspectRatio : 16 / 9,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: ColoredBox(
                  color: Colors.black,
                  child: _ready
                      ? VideoPlayer(_player!)
                      : const Center(
                          child: AdaptiveProgressIndicator(
                            color: Colors.white,
                            dimension: 30,
                          ),
                        ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${_format(_selection.start.round())} – ${_format(_selection.end.round())}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                Text(
                  '${(selectedDuration / 1000).toStringAsFixed(1)} sec selected',
                  style: const TextStyle(
                    color: forest,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            RangeSlider(
              values: _selection,
              min: 0,
              max: max(1, duration),
              divisions: max(1, session.durationMs ~/ 250),
              labels: RangeLabels(
                _format(_selection.start.round()),
                _format(_selection.end.round()),
              ),
              onChanged: (values) => _updateSelection(values, session),
              onChangeEnd: (_) => _seekToSelectionStart(),
            ),
            const Text(
              'Drag either handle to choose the section. The selection is limited to 15 seconds, but it can start anywhere in the video.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                height: 1.35,
                color: Colors.black54,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: AdaptiveButton(
                    style: AdaptiveButtonStyle.secondary,
                    onPressed: _useFirstFifteenSeconds,
                    icon: const Icon(Icons.first_page_rounded),
                    child: const Text('First 15 sec'),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton.filledTonal(
                  tooltip: _player?.value.isPlaying == true
                      ? 'Pause selected clip'
                      : 'Play selected clip',
                  onPressed: _ready ? _togglePlayback : null,
                  icon: Icon(
                    _player?.value.isPlaying == true
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: AdaptiveButton(
                onPressed: selectedDuration >= 120 ? _continueWithClip : null,
                icon: const Icon(Icons.shield_outlined),
                child: Text(
                  'Protect this ${_shortDuration(selectedDuration)} clip',
                ),
              ),
            ),
            const SizedBox(height: 8),
            AdaptiveButton(
              style: AdaptiveButtonStyle.plain,
              onPressed: _unlockWholeVideo,
              child: const Text('Unlock Pro to protect the full video'),
            ),
          ],
        ),
      ),
    );
  }

  void _updateSelection(RangeValues values, VideoSession session) {
    final maximum = privacyCamVideoFreeMaxDurationMs.toDouble();
    RangeValues next;
    if (values.end - values.start <= maximum) {
      next = values;
    } else {
      final startMoved =
          (values.start - _selection.start).abs() >=
          (values.end - _selection.end).abs();
      next = startMoved
          ? RangeValues(
              values.start,
              min(session.durationMs.toDouble(), values.start + maximum),
            )
          : RangeValues(max(0, values.end - maximum), values.end);
    }
    setState(() => _selection = next);
  }

  void _useFirstFifteenSeconds() {
    final session = ref.read(videoEditorProvider).session;
    if (session == null) return;
    setState(
      () => _selection = RangeValues(
        0,
        min(session.durationMs, privacyCamVideoFreeMaxDurationMs).toDouble(),
      ),
    );
    _seekToSelectionStart();
  }

  Future<void> _seekToSelectionStart() async {
    final player = _player;
    if (player == null) return;
    await player.pause();
    await player.seekTo(Duration(milliseconds: _selection.start.round()));
    if (mounted) setState(() {});
  }

  Future<void> _togglePlayback() async {
    final player = _player;
    if (player == null) return;
    if (player.value.isPlaying) {
      await player.pause();
    } else {
      final position = player.value.position.inMilliseconds;
      if (position < _selection.start || position >= _selection.end) {
        await player.seekTo(Duration(milliseconds: _selection.start.round()));
      }
      await player.play();
    }
    if (mounted) setState(() {});
  }

  void _continueWithClip() {
    ref
        .read(videoEditorProvider.notifier)
        .setVideoTrim(_selection.start.round(), _selection.end.round());
    context.go('/video/scan');
  }

  Future<void> _unlockWholeVideo() async {
    final unlocked = await context.push<bool>('/pro');
    if (!mounted || unlocked != true) return;
    ref.read(videoEditorProvider.notifier).resetVideoEdits();
    context.go('/video/scan');
  }

  Future<void> _discard() async {
    await ref.read(videoEditorProvider.notifier).clear();
    if (mounted) context.go('/home');
  }

  String _format(int milliseconds) {
    final minutes = milliseconds ~/ 60000;
    final seconds = (milliseconds ~/ 1000)
        .remainder(60)
        .toString()
        .padLeft(2, '0');
    final tenths = (milliseconds.remainder(1000) ~/ 100);
    return '$minutes:$seconds.$tenths';
  }

  String _shortDuration(int milliseconds) {
    final seconds = milliseconds / 1000;
    return seconds == seconds.roundToDouble()
        ? '${seconds.round()}s'
        : '${seconds.toStringAsFixed(1)}s';
  }
}
