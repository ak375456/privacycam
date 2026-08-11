import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';

import '../../core/theme.dart';
import '../../domain/models.dart';
import '../../domain/video_models.dart';
import '../../state/providers.dart';
import '../../state/video_providers.dart';
import '../widgets/adaptive_ui.dart';
import '../widgets/redaction_style_picker.dart';
import '../widgets/video_redaction_overlay.dart';
import '../widgets/video_timeline_editor.dart';

enum _VideoTool { select, rectangle }

enum _TrackRange { wholeVideo, fromHere, aroundHere }

bool _hasStrength(RedactionStyle style) =>
    style == RedactionStyle.blur || style == RedactionStyle.pixelate;

class VideoEditorScreen extends ConsumerStatefulWidget {
  const VideoEditorScreen({super.key});

  @override
  ConsumerState<VideoEditorScreen> createState() => _VideoEditorScreenState();
}

class _VideoEditorScreenState extends ConsumerState<VideoEditorScreen> {
  VideoPlayerController? _player;
  ui.FragmentProgram? _pixelProgram;
  _VideoTool _tool = _VideoTool.select;
  RedactionStyle _style = RedactionStyle.pixelate;
  VideoTrackEditScope _editScope = VideoTrackEditScope.thisMoment;
  int _timestampMs = 0;
  int _lastUiUpdateMs = -100;
  Rect? _draft;
  Offset? _gestureStart;
  Rect? _initialBounds;
  Rect? _editingBounds;
  List<VideoFrame> _timelineFrames = const [];
  bool _correctingPlayback = false;
  bool _clipEditorOpen = false;
  bool _edgeHoldOpen = false;
  final ScrollController _controlsScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    Future.microtask(_initialize);
  }

  Future<void> _initialize() async {
    final session = ref.read(videoEditorProvider).session;
    if (session == null) return;
    final player = VideoPlayerController.file(File(session.sourcePath));
    await player.initialize();
    await player.setVolume(session.resolvedEditPlan.audioMuted ? 0 : 1);
    player.addListener(_playerChanged);
    try {
      _pixelProgram = await ui.FragmentProgram.fromAsset(
        'shaders/video_pixelate.frag',
      );
    } catch (_) {
      _pixelProgram = null;
    }
    if (!mounted) {
      await player.dispose();
      return;
    }
    setState(() => _player = player);
    unawaited(_loadTimelineFrames(session));
  }

  Future<void> _loadTimelineFrames(VideoSession session) async {
    final count = (session.durationMs / 2500).ceil().clamp(8, 24);
    final timestamps = [
      for (var index = 0; index < count; index++)
        (session.durationMs * index / max(1, count - 1)).round(),
    ];
    try {
      final frames = await ref
          .read(videoServiceProvider)
          .extractFrames(session.sourcePath, timestamps, maximumDimension: 220);
      if (!mounted) {
        await ref.read(videoServiceProvider).deleteFrames(frames);
        return;
      }
      final previous = _timelineFrames;
      setState(() => _timelineFrames = frames);
      if (previous.isNotEmpty) {
        await ref.read(videoServiceProvider).deleteFrames(previous);
      }
    } catch (_) {
      // The editor remains fully usable with a plain timeline if thumbnails
      // cannot be decoded on a particular device.
    }
  }

  void _playerChanged() {
    final player = _player;
    if (!mounted || player == null || !player.value.isInitialized) return;
    final next = player.value.position.inMilliseconds;
    final session = ref.read(videoEditorProvider).session;
    if (session != null && player.value.isPlaying && !_correctingPlayback) {
      final plan = session.resolvedEditPlan;
      if (!plan.includes(next, session.durationMs)) {
        final target = plan.nextIncludedTimestamp(next, session.durationMs);
        if (target == null) {
          unawaited(player.pause());
        } else {
          _correctingPlayback = true;
          unawaited(
            player.seekTo(Duration(milliseconds: target)).whenComplete(() {
              _correctingPlayback = false;
            }),
          );
        }
      }
    }
    if ((next - _lastUiUpdateMs).abs() < 50 && player.value.isPlaying) return;
    _lastUiUpdateMs = next;
    setState(() => _timestampMs = next);
  }

  @override
  void dispose() {
    _player?.removeListener(_playerChanged);
    unawaited(_player?.dispose());
    if (_timelineFrames.isNotEmpty) {
      unawaited(ref.read(videoServiceProvider).deleteFrames(_timelineFrames));
    }
    _controlsScroll.dispose();
    super.dispose();
  }

  Future<void> _startOver() async {
    final confirmed = await showAdaptiveActionSheet<bool>(
      context: context,
      title: 'Start over?',
      message: 'This video and its unsaved privacy edits will be discarded.',
      actions: const [
        AdaptiveAction(
          label: 'Discard video',
          value: true,
          destructive: true,
          icon: Icons.restart_alt_rounded,
        ),
      ],
      cancelLabel: 'Keep editing',
    );
    if (confirmed != true || !mounted) return;
    await ref.read(videoEditorProvider.notifier).clear();
    if (mounted) context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(videoEditorProvider);
    final session = state.session;
    if (session == null) {
      return const Scaffold(body: Center(child: Text('No video selected.')));
    }
    final settings = ref.watch(settingsProvider);
    final selected = session.tracks
        .where((track) => track.id == state.selectedTrackId)
        .firstOrNull;
    final activeTrackCount = session.tracks
        .where((track) => track.selected)
        .length;
    final exportMaskCount = session.exportTracks().length;
    final player = _player;
    return Scaffold(
      appBar: adaptiveNavigationBar(
        context,
        title: const Text('Redact video'),
        actions: [
          AdaptiveIconButton(
            tooltip: 'Start over',
            onPressed: _startOver,
            icon: Icon(
              adaptiveIcon(
                context,
                material: Icons.add_circle_outline,
                cupertino: CupertinoIcons.add_circled,
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ColoredBox(
                color: const Color(0xFF151817),
                child: Center(
                  child: player == null || !player.value.isInitialized
                      ? const AdaptiveProgressIndicator(
                          color: Colors.white,
                          dimension: 34,
                        )
                      : AspectRatio(
                          aspectRatio: player.value.aspectRatio,
                          child: LayoutBuilder(
                            builder: (context, constraints) => GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTapUp: (details) => _tapTrack(
                                details.localPosition,
                                constraints.biggest,
                                session,
                              ),
                              onPanStart: (details) => _panStart(
                                details.localPosition,
                                constraints.biggest,
                                session,
                              ),
                              onPanUpdate: (details) => _panUpdate(
                                details.localPosition,
                                constraints.biggest,
                                session,
                              ),
                              onPanEnd: (_) => _panEnd(session),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  VideoPlayer(player),
                                  VideoRedactionOverlay(
                                    tracks: _previewTracks(session),
                                    timestampMs: _timestampMs,
                                    selectedTrackId: state.selectedTrackId,
                                    blurStrength: settings.blurStrength,
                                    pixelSize: settings.pixelSize,
                                    pixelProgram: _pixelProgram,
                                    draftBounds: _draft,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                ),
              ),
            ),
            if (!_clipEditorOpen) _timeline(session),
            Flexible(
              child: SingleChildScrollView(
                controller: _controlsScroll,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: Column(
                    key: ValueKey(
                      selected != null
                          ? 'mask-${selected.id}'
                          : _clipEditorOpen
                          ? 'clip'
                          : _tool == _VideoTool.rectangle
                          ? 'manual'
                          : 'review',
                    ),
                    children: [
                      if (selected != null)
                        _maskPanel(selected, settings)
                      else if (_clipEditorOpen)
                        _clipPanel(session, state)
                      else if (_tool == _VideoTool.rectangle)
                        _manualAreaPanel(settings)
                      else
                        _reviewPanel(session, activeTrackCount),
                      const SizedBox(height: 14),
                      _exportAction(
                        session: session,
                        activeTrackCount: activeTrackCount,
                        exportMaskCount: exportMaskCount,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _reviewPanel(VideoSession session, int activeTrackCount) => Column(
    key: const ValueKey('review-panel'),
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(
            child: _toolButton(
              label: 'Edit clip',
              icon: Icons.content_cut_rounded,
              active: false,
              onTap: () {
                _player?.pause();
                ref.read(videoEditorProvider.notifier).selectTrack(null);
                setState(() {
                  _clipEditorOpen = true;
                  _tool = _VideoTool.select;
                });
              },
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _toolButton(
              label: 'Add mask',
              icon: Icons.crop_square_rounded,
              active: false,
              onTap: () {
                _player?.pause();
                ref.read(videoEditorProvider.notifier).selectTrack(null);
                setState(() {
                  _clipEditorOpen = false;
                  _tool = _VideoTool.rectangle;
                });
              },
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
      _categoryPicker(session),
      const SizedBox(height: 9),
      Row(
        children: [
          const Icon(Icons.shield_outlined, size: 18, color: forest),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              '$activeTrackCount active privacy ${activeTrackCount == 1 ? 'mask' : 'masks'}',
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: Color(0xFF52615D),
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 5),
      const Text(
        'Tap a mask in the video to move it, resize it, change its style, or keep it covered when detection briefly disappears.',
        style: TextStyle(fontSize: 12, height: 1.35, color: Color(0xFF52615D)),
      ),
    ],
  );

  Widget _clipPanel(VideoSession session, VideoEditorState state) => Column(
    key: const ValueKey('clip-panel'),
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          const Icon(Icons.video_settings_outlined, color: forest, size: 21),
          const SizedBox(width: 7),
          const Expanded(
            child: Text(
              'Edit clip',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
          ),
          AdaptiveButton(
            style: AdaptiveButtonStyle.plain,
            onPressed: () => setState(() => _clipEditorOpen = false),
            child: const Text('Done'),
          ),
        ],
      ),
      const SizedBox(height: 4),
      const Text(
        'Move the filmstrip beneath the white line, then tap Split. Tap a piece to select and delete it.',
        style: TextStyle(fontSize: 12, height: 1.35, color: Color(0xFF52615D)),
      ),
      const SizedBox(height: 9),
      VideoTimelineEditor(
        session: session,
        timestampMs: _timestampMs,
        thumbnails: _timelineFrames,
        canUndo: state.canUndoVideoEdit,
        canRedo: state.canRedoVideoEdit,
        onSeek: (timestamp) => _seekAbsolute(session, timestamp),
        onSplit: (timestamp) => _performClipEdit(
          () => ref.read(videoEditorProvider.notifier).splitVideoAt(timestamp),
        ),
        onDeleteSegment: (segment) => _performClipEdit(
          () => ref
              .read(videoEditorProvider.notifier)
              .deleteVideoSegment(segment),
        ),
        onUndo: () => _performClipEdit(
          ref.read(videoEditorProvider.notifier).undoVideoEdit,
        ),
        onRedo: () => _performClipEdit(
          ref.read(videoEditorProvider.notifier).redoVideoEdit,
        ),
        onToggleMute: () => _performClipEdit(
          ref.read(videoEditorProvider.notifier).toggleVideoAudioMuted,
        ),
        onTrimChanged: (start, end) => _performClipEdit(
          () => ref.read(videoEditorProvider.notifier).setVideoTrim(start, end),
        ),
      ),
      const SizedBox(height: 8),
      _precisionSeekControls(session),
      const SizedBox(height: 7),
      const Text(
        'Edits are non-destructive. PrivacyCam keeps the original video unchanged.',
        style: TextStyle(fontSize: 11.5, color: Color(0xFF52615D)),
      ),
    ],
  );

  void _performClipEdit(VoidCallback edit) {
    _player?.pause();
    edit();
    final updated = ref.read(videoEditorProvider).session;
    if (updated != null) {
      final plan = updated.resolvedEditPlan;
      unawaited(_player?.setVolume(plan.audioMuted ? 0 : 1));
      if (!plan.includes(_timestampMs, updated.durationMs)) {
        final ranges = plan.keptRanges(updated.durationMs);
        if (ranges.isNotEmpty) {
          final outputOffset = plan.outputOffsetForSourceTimestamp(
            _timestampMs,
            updated.durationMs,
          );
          var target = plan.sourceTimestampForOutputOffset(
            outputOffset,
            updated.durationMs,
          );
          final last = ranges.last;
          if (target >= last.endMs) {
            final frameMs = (1000 / updated.frameRate.clamp(1, 120))
                .round()
                .clamp(8, 1000);
            target = max(last.startMs, last.endMs - frameMs);
          }
          unawaited(_seekAbsolute(updated, target));
        }
      }
    }
  }

  Widget _manualAreaPanel(AppSettings settings) => Column(
    key: const ValueKey('manual-panel'),
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          const Icon(Icons.crop_square_rounded, color: forest, size: 21),
          const SizedBox(width: 7),
          const Expanded(
            child: Text(
              'Add a privacy mask',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
          ),
          AdaptiveButton(
            style: AdaptiveButtonStyle.plain,
            onPressed: () => setState(() => _tool = _VideoTool.select),
            child: const Text('Cancel'),
          ),
        ],
      ),
      const SizedBox(height: 3),
      const Text(
        'Drag over the video to draw an area. You can choose how long it stays and adjust it afterward.',
        style: TextStyle(fontSize: 12, height: 1.35, color: Color(0xFF52615D)),
      ),
      const SizedBox(height: 10),
      RedactionStylePicker(
        value: _style,
        onChanged: (value) => setState(() => _style = value),
      ),
      if (_hasStrength(_style)) ...[
        const SizedBox(height: 9),
        _effectStrengthControl(_style, settings),
      ],
    ],
  );

  Widget _maskPanel(VideoRedactionTrack track, AppSettings settings) => Column(
    key: ValueKey('mask-panel-${track.id}'),
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        decoration: BoxDecoration(
          color: const Color(0xFFE7F4EF),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF9BCDBB)),
        ),
        child: Row(
          children: [
            Icon(_categoryIcon(track.category), color: forest, size: 21),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Editing ${track.category == RedactionCategory.person ? 'full body' : track.category.label.toLowerCase()} mask',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            AdaptiveButton(
              style: AdaptiveButtonStyle.plain,
              onPressed: () =>
                  ref.read(videoEditorProvider.notifier).selectTrack(null),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
      const SizedBox(height: 9),
      RedactionStylePicker(
        value: track.style,
        onChanged: (value) => ref
            .read(videoEditorProvider.notifier)
            .setTrackStyle(track.id, value),
      ),
      if (_hasStrength(track.style)) ...[
        const SizedBox(height: 9),
        _effectStrengthControl(track.style, settings),
      ],
      const SizedBox(height: 9),
      _selectedTrackCard(track),
    ],
  );

  Widget _exportAction({
    required VideoSession session,
    required int activeTrackCount,
    required int exportMaskCount,
  }) => Column(
    children: [
      if (exportMaskCount > 48) ...[
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF1F0),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFFFC7C2)),
          ),
          child: Text(
            '$exportMaskCount masks are active. Turn off unnecessary masks for a faster export.',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFFB3261E),
            ),
          ),
        ),
        const SizedBox(height: 10),
      ],
      SizedBox(
        width: double.infinity,
        child: AdaptiveButton(
          style: AdaptiveButtonStyle.primary,
          onPressed: activeTrackCount == 0 ? null : () => _openExport(session),
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 5),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.shield_outlined),
                SizedBox(width: 8),
                Text('Create privacy-safe video'),
              ],
            ),
          ),
        ),
      ),
    ],
  );

  Future<void> _openExport(VideoSession session) async {
    if (privacyCamVideoRequiresPro(session.durationMs) &&
        !ref.read(proAccessProvider)) {
      final unlocked = await context.push<bool>('/pro');
      if (!mounted || unlocked != true) return;
    }
    if (mounted) context.push('/video/export');
  }

  Widget _effectStrengthControl(RedactionStyle style, AppSettings settings) {
    final isBlur = style == RedactionStyle.blur;
    final value = isBlur
        ? settings.blurStrength.clamp(10, 50).toDouble()
        : settings.pixelSize.clamp(8, 48).toDouble();
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
      decoration: BoxDecoration(
        color: mint.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(
            isBlur ? Icons.blur_on_outlined : Icons.grid_4x4_outlined,
            color: forest,
            size: 21,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: AdaptiveSlider(
              value: value,
              min: isBlur ? 10 : 8,
              max: isBlur ? 50 : 48,
              divisions: isBlur ? 20 : 20,
              label: isBlur ? '${value.round()}' : '${value.round()} px',
              onChanged: (next) {
                final controller = ref.read(settingsProvider.notifier);
                if (isBlur) {
                  controller.setBlurStrength(next);
                } else {
                  controller.setPixelSize(next);
                }
              },
            ),
          ),
          SizedBox(
            width: 50,
            child: Text(
              isBlur ? '${value.round()}' : '${value.round()} px',
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _timeline(VideoSession session) => ColoredBox(
    color: Theme.of(context).scaffoldBackgroundColor,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 5, 12, 4),
      child: Column(
        children: [
          Builder(
            builder: (context) {
              final plan = session.resolvedEditPlan;
              final outputDuration = plan.outputDurationMs(session.durationMs);
              final outputPosition = plan.outputOffsetForSourceTimestamp(
                _timestampMs,
                session.durationMs,
              );
              return Row(
                children: [
                  IconButton(
                    tooltip: _player?.value.isPlaying == true
                        ? 'Pause'
                        : 'Play',
                    onPressed: _player == null
                        ? null
                        : () => _togglePlayback(session),
                    icon: Icon(
                      _player?.value.isPlaying == true
                          ? Icons.pause_circle_filled_rounded
                          : Icons.play_circle_fill_rounded,
                      color: forest,
                      size: 34,
                    ),
                  ),
                  Expanded(
                    child: Slider(
                      value: outputPosition.clamp(0, outputDuration).toDouble(),
                      min: 0,
                      max: outputDuration.toDouble().clamp(1, double.infinity),
                      onChanged: (value) {
                        final source = plan.sourceTimestampForOutputOffset(
                          value.round(),
                          session.durationMs,
                        );
                        unawaited(_seekAbsolute(session, source));
                      },
                    ),
                  ),
                  SizedBox(
                    width: 105,
                    child: Text(
                      '${_formatPreciseTime(outputPosition)} / ${_formatTime(outputDuration)}',
                      textAlign: TextAlign.end,
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ),
                ],
              );
            },
          ),
          _precisionSeekControls(session),
        ],
      ),
    ),
  );

  Widget _precisionSeekControls(VideoSession session) => Container(
    decoration: BoxDecoration(
      color: const Color(0xFFF3F6F5),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFDDE5E1)),
    ),
    child: Row(
      children: [
        _precisionSeekButton(
          label: '−1 sec',
          onPressed: _player == null ? null : () => _seekBy(session, -1000),
        ),
        _precisionSeekButton(
          label: '‹ frame',
          onPressed: _player == null ? null : () => _seekFrame(session, -1),
        ),
        _precisionSeekButton(
          label: 'frame ›',
          onPressed: _player == null ? null : () => _seekFrame(session, 1),
        ),
        _precisionSeekButton(
          label: '+1 sec',
          onPressed: _player == null ? null : () => _seekBy(session, 1000),
        ),
      ],
    ),
  );

  Widget _precisionSeekButton({
    required String label,
    required VoidCallback? onPressed,
  }) => Expanded(
    child: AdaptiveButton(
      style: AdaptiveButtonStyle.plain,
      onPressed: onPressed,
      child: Text(label, style: const TextStyle(fontSize: 13)),
    ),
  );

  Future<void> _seekFrame(VideoSession session, int direction) {
    final frameMs = (1000 / session.frameRate.clamp(1, 120)).round().clamp(
      8,
      1000,
    );
    return _seekBy(session, frameMs * direction);
  }

  Future<void> _seekBy(VideoSession session, int deltaMs) async {
    final player = _player;
    if (player == null) return;
    await player.pause();
    final plan = session.resolvedEditPlan;
    final outputPosition = plan.outputOffsetForSourceTimestamp(
      _timestampMs,
      session.durationMs,
    );
    final outputTarget = (outputPosition + deltaMs).clamp(
      0,
      plan.outputDurationMs(session.durationMs),
    );
    final target = plan.sourceTimestampForOutputOffset(
      outputTarget,
      session.durationMs,
    );
    await player.seekTo(Duration(milliseconds: target));
    if (mounted) setState(() => _timestampMs = target);
  }

  Future<void> _seekAbsolute(VideoSession session, int timestampMs) async {
    final player = _player;
    if (player == null) return;
    final target = timestampMs.clamp(0, session.durationMs);
    await player.pause();
    await player.seekTo(Duration(milliseconds: target));
    if (mounted) setState(() => _timestampMs = target);
  }

  Future<void> _togglePlayback(VideoSession session) async {
    final player = _player;
    if (player == null) return;
    if (player.value.isPlaying) {
      await player.pause();
      return;
    }
    final plan = session.resolvedEditPlan;
    var target = plan.nextIncludedTimestamp(_timestampMs, session.durationMs);
    if (target == null || _timestampMs >= plan.trimEndMs - 20) {
      target = plan.keptRanges(session.durationMs).firstOrNull?.startMs;
    }
    if (target == null) return;
    if (target != _timestampMs) {
      await player.seekTo(Duration(milliseconds: target));
      if (mounted) setState(() => _timestampMs = target!);
    }
    await player.play();
  }

  Widget _toolButton({
    required String label,
    required IconData icon,
    required bool active,
    required VoidCallback onTap,
  }) => InkWell(
    borderRadius: BorderRadius.circular(14),
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: BoxDecoration(
        color: active ? mint : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: active ? const Color(0xFF9BCDBB) : Colors.black12,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: forest),
          const SizedBox(width: 7),
          Text(label),
        ],
      ),
    ),
  );

  Widget _categoryPicker(VideoSession session) {
    final counts = <RedactionCategory, int>{};
    final selectedCounts = <RedactionCategory, int>{};
    for (final track in session.tracks.where(
      (track) => track.source == RedactionSource.automatic,
    )) {
      counts[track.category] = (counts[track.category] ?? 0) + 1;
      if (track.selected) {
        selectedCounts[track.category] =
            (selectedCounts[track.category] ?? 0) + 1;
      }
    }
    if (counts.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F8F7),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFFDDE5E1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.visibility_off_outlined, size: 19, color: forest),
              SizedBox(width: 7),
              Text(
                'Choose what to hide',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 3),
          const Text(
            'Tap a category to hide or show every detected track. Faces and full bodies are separate choices.',
            style: TextStyle(
              fontSize: 12,
              height: 1.3,
              color: Color(0xFF52615D),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 42,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: counts.length,
              separatorBuilder: (_, _) => const SizedBox(width: 7),
              itemBuilder: (context, index) {
                final category = counts.keys.elementAt(index);
                final total = counts[category]!;
                final selected = selectedCounts[category] ?? 0;
                final enabled = selected > 0;
                final label = category == RedactionCategory.person
                    ? 'Full bodies'
                    : category.label;
                final countLabel = selected == 0
                    ? 'off'
                    : selected == total
                    ? '$total'
                    : '$selected/$total';
                return Semantics(
                  button: true,
                  selected: enabled,
                  label:
                      '$label, $countLabel. ${enabled ? 'Tap to keep visible' : 'Tap to hide'}',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(11),
                    onTap: () => ref
                        .read(videoEditorProvider.notifier)
                        .setCategorySelected(category, !enabled),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      padding: const EdgeInsets.symmetric(horizontal: 11),
                      decoration: BoxDecoration(
                        color: enabled ? mint : Colors.white,
                        borderRadius: BorderRadius.circular(11),
                        border: Border.all(
                          color: enabled
                              ? const Color(0xFF9BCDBB)
                              : const Color(0xFFD6DEDA),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _categoryIcon(category),
                            size: 17,
                            color: enabled ? forest : const Color(0xFF52615D),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '$label $countLabel',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: enabled ? forest : const Color(0xFF52615D),
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
    );
  }

  IconData _categoryIcon(RedactionCategory category) => switch (category) {
    RedactionCategory.face => Icons.face_outlined,
    RedactionCategory.person => Icons.accessibility_new_rounded,
    RedactionCategory.email => Icons.alternate_email_rounded,
    RedactionCategory.phone => Icons.phone_outlined,
    RedactionCategory.address => Icons.location_on_outlined,
    RedactionCategory.card => Icons.credit_card_outlined,
    RedactionCategory.cardSecurityCode => Icons.password_outlined,
    RedactionCategory.url => Icons.link_rounded,
    RedactionCategory.qrCode => Icons.qr_code_rounded,
    RedactionCategory.barcode => Icons.view_week_outlined,
    RedactionCategory.numberPlate => Icons.directions_car_outlined,
    RedactionCategory.otherText => Icons.text_fields_rounded,
    RedactionCategory.manual => Icons.crop_square_rounded,
  };

  Widget _selectedTrackCard(VideoRedactionTrack track) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: mint,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                track.category == RedactionCategory.person
                    ? 'Full body'
                    : track.category.label,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            AdaptiveSwitch(
              value: track.selected,
              onChanged: (_) =>
                  ref.read(videoEditorProvider.notifier).toggleTrack(track.id),
            ),
            IconButton(
              tooltip: 'Delete track',
              onPressed: () =>
                  ref.read(videoEditorProvider.notifier).deleteTrack(track.id),
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
            ),
          ],
        ),
        Text(
          '${_formatTime(track.startMs)}–${_formatTime(track.endMs)} · Drag or use the arrows to move',
          style: const TextStyle(fontSize: 12.5, color: Color(0xFF52615D)),
        ),
        if (track.holds.any((hold) => hold.contains(_timestampMs))) ...[
          const SizedBox(height: 5),
          const Row(
            children: [
              Icon(Icons.security_rounded, size: 16, color: forest),
              SizedBox(width: 5),
              Expanded(
                child: Text(
                  'Safety hold active — you can still drag, resize, or nudge this mask.',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.25,
                    fontWeight: FontWeight.w700,
                    color: forest,
                  ),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 8),
        const Text(
          'Move applies to',
          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 5),
        AdaptiveSegmentedControl<VideoTrackEditScope>(
          value: _editScope,
          onChanged: (value) => setState(() => _editScope = value),
          children: const {
            VideoTrackEditScope.thisMoment: Text('This frame'),
            VideoTrackEditScope.fromHere: Text('From here'),
            VideoTrackEditScope.entireTrack: Text('All frames'),
          },
        ),
        const SizedBox(height: 7),
        Row(
          children: [
            const Expanded(
              child: Text(
                'Fine position',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
              ),
            ),
            _nudgeButton(
              track,
              Icons.arrow_upward_rounded,
              const Offset(0, -.006),
              'Move up',
            ),
            _nudgeButton(
              track,
              Icons.arrow_downward_rounded,
              const Offset(0, .006),
              'Move down',
            ),
            _nudgeButton(
              track,
              Icons.arrow_back_rounded,
              const Offset(-.006, 0),
              'Move left',
            ),
            _nudgeButton(
              track,
              Icons.arrow_forward_rounded,
              const Offset(.006, 0),
              'Move right',
            ),
          ],
        ),
        const SizedBox(height: 5),
        _areaSizeControl(track),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: AdaptiveButton(
            style: AdaptiveButtonStyle.secondary,
            onPressed: () => setState(() => _edgeHoldOpen = !_edgeHoldOpen),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.security_rounded, size: 18),
                const SizedBox(width: 7),
                Text(
                  track.holds.isEmpty
                      ? 'Cover a brief tracking gap'
                      : 'Tracking gap cover · ${track.holds.length}',
                ),
                const SizedBox(width: 4),
                Icon(
                  _edgeHoldOpen
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
        if (_edgeHoldOpen) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Keep this position covered for',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
                ),
              ),
              if (track.holds.isNotEmpty)
                AdaptiveButton(
                  style: AdaptiveButtonStyle.plain,
                  onPressed: () => ref
                      .read(videoEditorProvider.notifier)
                      .clearTrackHolds(track.id),
                  child: const Text('Clear', style: TextStyle(fontSize: 12)),
                ),
            ],
          ),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _holdButton(track, '0.5 sec', 500),
              _holdButton(track, '1 sec', 1000),
              _holdButton(track, '2 sec', 2000),
              _holdButton(track, 'To end', null),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Pause on the last safe frame near an edge, then choose a duration. The mask stays here if detection briefly disappears.',
            style: TextStyle(
              fontSize: 12,
              height: 1.3,
              color: Color(0xFF52615D),
            ),
          ),
        ],
      ],
    ),
  );

  Widget _holdButton(
    VideoRedactionTrack track,
    String label,
    int? durationMs,
  ) => AdaptiveButton(
    style: AdaptiveButtonStyle.secondary,
    onPressed: track.existsAt(_timestampMs)
        ? () {
            _player?.pause();
            ref
                .read(videoEditorProvider.notifier)
                .holdTrackAt(track.id, _timestampMs, durationMs: durationMs);
            showAdaptiveMessage(
              context,
              durationMs == null
                  ? 'Mask held here to the end of the clip.'
                  : 'Mask held here for $label.',
            );
          }
        : null,
    child: Text(label, style: const TextStyle(fontSize: 12)),
  );

  Widget _nudgeButton(
    VideoRedactionTrack track,
    IconData icon,
    Offset delta,
    String tooltip,
  ) => IconButton(
    tooltip: tooltip,
    visualDensity: VisualDensity.compact,
    onPressed: track.existsAt(_timestampMs)
        ? () => _nudgeTrack(track, delta)
        : null,
    icon: Icon(icon, color: forest, size: 21),
  );

  void _nudgeTrack(VideoRedactionTrack track, Offset delta) {
    _player?.pause();
    ref
        .read(videoEditorProvider.notifier)
        .updateTrackBounds(
          track.id,
          _timestampMs,
          track.boundsAt(_timestampMs).shift(delta),
          scope: _editScope,
        );
  }

  Widget _areaSizeControl(VideoRedactionTrack track) {
    final bounds = track.boundsAt(_timestampMs);
    final aspectRatio = bounds.width <= 0 ? 1.0 : bounds.height / bounds.width;
    final minWidth = (0.02 / aspectRatio).clamp(0.02, 1.0);
    final maxWidth = (1.0 / aspectRatio).clamp(0.02, 1.0);
    final value = bounds.width.clamp(minWidth, maxWidth);
    return Row(
      children: [
        const Text(
          'Area size',
          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: AdaptiveSlider(
            value: value,
            min: minWidth,
            max: maxWidth,
            divisions: 50,
            label: '${(value * 100).round()}%',
            onChanged: track.existsAt(_timestampMs) && maxWidth > minWidth
                ? (next) => _resizeTrack(track, next)
                : null,
          ),
        ),
        SizedBox(
          width: 42,
          child: Text(
            '${(value * 100).round()}%',
            textAlign: TextAlign.end,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }

  void _resizeTrack(VideoRedactionTrack track, double width) {
    _player?.pause();
    final current = track.boundsAt(_timestampMs);
    final aspectRatio = current.width <= 0
        ? 1.0
        : current.height / current.width;
    final target = Rect.fromCenter(
      center: current.center,
      width: width,
      height: width * aspectRatio,
    );
    ref
        .read(videoEditorProvider.notifier)
        .updateTrackBounds(track.id, _timestampMs, target, scope: _editScope);
  }

  void _tapTrack(Offset position, Size size, VideoSession session) {
    if (_tool != _VideoTool.select) return;
    final point = Offset(position.dx / size.width, position.dy / size.height);
    var matches = session.tracks
        .where(
          (track) =>
              track.existsAt(_timestampMs) &&
              track.boundsAt(_timestampMs).contains(point),
        )
        .toList();
    if (matches.isEmpty) {
      matches = session.tracks
          .where(
            (track) =>
                track.existsAt(_timestampMs) &&
                track.boundsAt(_timestampMs).inflate(.02).contains(point),
          )
          .toList();
    }
    final hitId = _preferredTrack(matches)?.id;
    final selectedId = ref.read(videoEditorProvider).selectedTrackId;
    _selectTrackAndReveal(hitId == selectedId ? null : hitId);
  }

  void _selectTrackAndReveal(String? id) {
    final previous = ref.read(videoEditorProvider).selectedTrackId;
    ref.read(videoEditorProvider.notifier).selectTrack(id);
    if (id == null) return;
    setState(() {
      _clipEditorOpen = false;
      _tool = _VideoTool.select;
      if (previous != id) _edgeHoldOpen = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controlsScroll.hasClients) return;
      unawaited(
        _controlsScroll.animateTo(
          0,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        ),
      );
    });
  }

  void _panStart(Offset position, Size size, VideoSession session) {
    _player?.pause();
    final point = Offset(position.dx / size.width, position.dy / size.height);
    _gestureStart = point;
    if (_tool == _VideoTool.rectangle) {
      setState(() => _draft = Rect.fromPoints(point, point));
      return;
    }
    final selectedId = ref.read(videoEditorProvider).selectedTrackId;
    var selected = session.tracks
        .where((track) => track.id == selectedId)
        .firstOrNull;
    final nearby = session.tracks.where(
      (track) =>
          track.existsAt(_timestampMs) &&
          track.boundsAt(_timestampMs).inflate(.018).contains(point),
    );
    final preferred = _preferredTrack(nearby);
    if (selected == null ||
        !selected.existsAt(_timestampMs) ||
        !selected.boundsAt(_timestampMs).inflate(.025).contains(point) ||
        selected.category == RedactionCategory.person &&
            preferred?.category == RedactionCategory.face) {
      selected = preferred;
      _selectTrackAndReveal(selected?.id);
    }
    if (selected == null) return;
    _initialBounds = selected.boundsAt(_timestampMs);
    _editingBounds = _initialBounds;
  }

  VideoRedactionTrack? _preferredTrack(
    Iterable<VideoRedactionTrack> candidates,
  ) {
    final sorted = candidates.toList()
      ..sort((a, b) {
        final priority = _hitPriority(
          b.category,
        ).compareTo(_hitPriority(a.category));
        if (priority != 0) return priority;
        final areaA = a.boundsAt(_timestampMs);
        final areaB = b.boundsAt(_timestampMs);
        return (areaA.width * areaA.height).compareTo(
          areaB.width * areaB.height,
        );
      });
    return sorted.firstOrNull;
  }

  int _hitPriority(RedactionCategory category) => switch (category) {
    RedactionCategory.face => 3,
    RedactionCategory.person => 1,
    _ => 2,
  };

  void _panUpdate(Offset position, Size size, VideoSession session) {
    final start = _gestureStart;
    if (start == null) return;
    final point = Offset(
      (position.dx / size.width).clamp(0, 1),
      (position.dy / size.height).clamp(0, 1),
    );
    if (_tool == _VideoTool.rectangle) {
      setState(() => _draft = Rect.fromPoints(start, point));
      return;
    }
    final initial = _initialBounds;
    final id = ref.read(videoEditorProvider).selectedTrackId;
    if (initial == null || id == null) return;
    final next = initial.shift(point - start);
    setState(() => _editingBounds = next);
  }

  Future<void> _panEnd(VideoSession session) async {
    final editedId = ref.read(videoEditorProvider).selectedTrackId;
    final editedBounds = _editingBounds;
    _gestureStart = null;
    _initialBounds = null;
    _editingBounds = null;
    final draft = _draft;
    if (_tool != _VideoTool.rectangle || draft == null) {
      if (editedId != null && editedBounds != null) {
        if (mounted) setState(() {});
        ref
            .read(videoEditorProvider.notifier)
            .updateTrackBounds(
              editedId,
              _timestampMs,
              editedBounds,
              scope: _editScope,
            );
      }
      return;
    }
    setState(() => _draft = null);
    if (draft.width.abs() < .025 || draft.height.abs() < .025) return;
    final range = await showAdaptiveActionSheet<_TrackRange>(
      context: context,
      title: 'How long should this area stay hidden?',
      message: 'You can move and resize it later at any point in the video.',
      actions: const [
        AdaptiveAction(
          label: 'Whole video',
          value: _TrackRange.wholeVideo,
          icon: Icons.all_inclusive,
        ),
        AdaptiveAction(
          label: 'From here to the end',
          value: _TrackRange.fromHere,
          icon: Icons.last_page,
        ),
        AdaptiveAction(
          label: 'Around this moment (5 seconds)',
          value: _TrackRange.aroundHere,
          icon: Icons.timer_outlined,
        ),
      ],
    );
    if (range == null || !mounted) return;
    final (start, end) = switch (range) {
      _TrackRange.wholeVideo => (0, session.durationMs),
      _TrackRange.fromHere => (_timestampMs, session.durationMs),
      _TrackRange.aroundHere => (
        (_timestampMs - 2500).clamp(0, session.durationMs),
        (_timestampMs + 2500).clamp(0, session.durationMs),
      ),
    };
    final id = ref
        .read(videoEditorProvider.notifier)
        .addManualTrack(
          bounds: Rect.fromLTRB(
            draft.left.clamp(0, 1),
            draft.top.clamp(0, 1),
            draft.right.clamp(0, 1),
            draft.bottom.clamp(0, 1),
          ),
          startMs: start,
          endMs: end,
          style: _style,
        );
    _selectTrackAndReveal(id);
  }

  List<VideoRedactionTrack> _previewTracks(VideoSession session) {
    final id = ref.read(videoEditorProvider).selectedTrackId;
    final bounds = _editingBounds;
    if (id == null || bounds == null) return session.tracks;
    return [
      for (final track in session.tracks)
        if (track.id == id)
          track.copyWith(
            keyframes: [
              VideoKeyframe(timestampMs: _timestampMs, bounds: bounds),
            ],
            holds: [
              for (final hold in track.holds)
                if (hold.contains(_timestampMs))
                  VideoHold(
                    startMs: hold.startMs,
                    endMs: hold.endMs,
                    bounds: bounds,
                  )
                else
                  hold,
            ],
          )
        else
          track,
    ];
  }

  String _formatTime(int milliseconds) {
    final duration = Duration(milliseconds: milliseconds);
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  String _formatPreciseTime(int milliseconds) {
    final safe = milliseconds.clamp(0, 3599999);
    final minutes = safe ~/ 60000;
    final seconds = (safe ~/ 1000).remainder(60).toString().padLeft(2, '0');
    final fraction = safe.remainder(1000).toString().padLeft(3, '0');
    return '$minutes:$seconds.$fraction';
  }
}
