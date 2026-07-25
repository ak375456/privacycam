import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models.dart';
import '../domain/video_models.dart';
import '../services/video_analysis_service.dart';
import '../services/video_service.dart';
import 'providers.dart';

final videoServiceProvider = Provider<VideoService>((ref) {
  final service = VideoService();
  ref.onDispose(service.dispose);
  return service;
});

final videoAnalysisProvider = Provider<VideoAnalysisService>(
  (ref) => VideoAnalysisService(
    videoService: ref.read(videoServiceProvider),
    detectionService: ref.read(detectionProvider),
  ),
);

class VideoEditorState {
  const VideoEditorState({
    this.session,
    this.stage = VideoWorkStage.idle,
    this.progress = 0,
    this.detail = '',
    this.error,
    this.selectedTrackId,
    this.canUndoVideoEdit = false,
    this.canRedoVideoEdit = false,
  });

  final VideoSession? session;
  final VideoWorkStage stage;
  final double progress;
  final String detail;
  final String? error;
  final String? selectedTrackId;
  final bool canUndoVideoEdit;
  final bool canRedoVideoEdit;

  bool get isBusy => switch (stage) {
    VideoWorkStage.importing ||
    VideoWorkStage.preparing ||
    VideoWorkStage.detecting ||
    VideoWorkStage.buildingTracks ||
    VideoWorkStage.exporting => true,
    _ => false,
  };

  VideoEditorState copyWith({
    VideoSession? session,
    VideoWorkStage? stage,
    double? progress,
    String? detail,
    String? error,
    String? selectedTrackId,
    bool clearSession = false,
    bool clearError = false,
    bool clearSelection = false,
    bool? canUndoVideoEdit,
    bool? canRedoVideoEdit,
  }) => VideoEditorState(
    session: clearSession ? null : session ?? this.session,
    stage: stage ?? this.stage,
    progress: progress ?? this.progress,
    detail: detail ?? this.detail,
    error: clearError ? null : error ?? this.error,
    selectedTrackId: clearSelection
        ? null
        : selectedTrackId ?? this.selectedTrackId,
    canUndoVideoEdit: canUndoVideoEdit ?? this.canUndoVideoEdit,
    canRedoVideoEdit: canRedoVideoEdit ?? this.canRedoVideoEdit,
  );
}

class VideoEditorController extends Notifier<VideoEditorState> {
  static const _storageKey = 'privacyCamVideoSessionV1';
  var _cancelled = false;
  StreamSubscription<double>? _exportProgress;
  final _videoEditUndo = <VideoEditPlan>[];
  final _videoEditRedo = <VideoEditPlan>[];

  @override
  VideoEditorState build() {
    ref.onDispose(() => _exportProgress?.cancel());
    final raw = ref.read(sharedPreferencesProvider).getString(_storageKey);
    if (raw == null) return const VideoEditorState();
    try {
      final session = VideoSession.fromJson(
        Map<String, Object?>.from(jsonDecode(raw) as Map),
      );
      if (!File(session.sourcePath).existsSync()) {
        unawaited(ref.read(sharedPreferencesProvider).remove(_storageKey));
        return const VideoEditorState();
      }
      var restored = session;
      if (restored.analysisVersion < privacyCamVideoAnalysisVersion) {
        restored = restored.copyWith(
          tracks: const [],
          clearExport: true,
          analysisVersion: privacyCamVideoAnalysisVersion,
        );
        unawaited(
          ref
              .read(sharedPreferencesProvider)
              .setString(_storageKey, jsonEncode(restored.toJson())),
        );
      } else if (restored.exportPath != null &&
          !File(restored.exportPath!).existsSync()) {
        restored = restored.copyWith(clearExport: true);
      }
      return VideoEditorState(
        session: restored,
        stage: restored.tracks.isEmpty
            ? VideoWorkStage.preparing
            : VideoWorkStage.ready,
        detail: restored.tracks.isEmpty
            ? 'Ready to scan again'
            : 'Review every track before export',
      );
    } catch (_) {
      unawaited(ref.read(sharedPreferencesProvider).remove(_storageKey));
      return const VideoEditorState();
    }
  }

  Future<void> importPath(String path) async {
    _cancelled = false;
    _videoEditUndo.clear();
    _videoEditRedo.clear();
    state = const VideoEditorState(
      stage: VideoWorkStage.importing,
      progress: .01,
      detail: 'Reading video securely on this device',
    );
    try {
      final info = await ref.read(videoServiceProvider).inspect(path);
      if (_cancelled) return;
      final session = VideoSession(
        sourcePath: path,
        durationMs: info.durationMs,
        width: info.width,
        height: info.height,
        hasAudio: info.hasAudio,
        frameRate: info.frameRate,
      );
      state = VideoEditorState(
        session: session,
        stage: VideoWorkStage.preparing,
        progress: .02,
        detail: 'Preparing on-device privacy checks',
      );
      await _persist();
    } catch (error) {
      await ref.read(videoServiceProvider).deleteWorkingFile(path);
      state = VideoEditorState(
        stage: VideoWorkStage.failed,
        error: error.toString(),
      );
      rethrow;
    }
  }

  Future<void> scan() async {
    final session = state.session;
    if (session == null ||
        state.isBusy && state.stage != VideoWorkStage.preparing) {
      return;
    }
    _cancelled = false;
    state = state.copyWith(
      stage: VideoWorkStage.detecting,
      progress: .03,
      detail: 'Finding privacy details across the video',
      clearError: true,
    );
    final settings = ref.read(settingsProvider);
    try {
      final tracks = await ref
          .read(videoAnalysisProvider)
          .analyze(
            session,
            autoHideCategories: settings.autoHideCategories,
            faceStyle: settings.faceStyle,
            peopleStyle: settings.peopleStyle,
            sensitiveStyle: settings.sensitiveStyle,
            isCancelled: () => _cancelled,
            onProgress: (progress, detail) {
              if (_cancelled) return;
              state = state.copyWith(
                stage: progress >= .94
                    ? VideoWorkStage.buildingTracks
                    : VideoWorkStage.detecting,
                progress: progress,
                detail: detail,
              );
            },
          );
      if (_cancelled) return;
      final updated = session.copyWith(
        tracks: tracks,
        clearExport: true,
        analysisVersion: privacyCamVideoAnalysisVersion,
      );
      state = state.copyWith(
        session: updated,
        stage: VideoWorkStage.ready,
        progress: 1,
        detail: '${tracks.length} privacy tracks found — review before export',
        clearError: true,
      );
      await _persist();
    } catch (error) {
      if (_cancelled) return;
      state = state.copyWith(
        stage: VideoWorkStage.failed,
        error: error.toString(),
      );
    }
  }

  Future<void> cancelWork() async {
    _cancelled = true;
    final wasExporting = state.stage == VideoWorkStage.exporting;
    if (wasExporting) {
      await ref.read(videoServiceProvider).cancelExport();
    } else {
      await ref.read(videoServiceProvider).cancelAnalysis();
    }
    if (wasExporting && state.session != null) {
      state = state.copyWith(
        stage: VideoWorkStage.ready,
        progress: 0,
        detail: 'Export cancelled — your edits are still here',
      );
    }
  }

  void selectTrack(String? id) {
    state = id == null
        ? state.copyWith(clearSelection: true)
        : state.copyWith(selectedTrackId: id);
  }

  void toggleTrack(String id) =>
      _updateTrack(id, (track) => track.copyWith(selected: !track.selected));

  void setCategorySelected(RedactionCategory category, bool selected) {
    final session = state.session;
    if (session == null) return;
    _commit(
      session.copyWith(
        tracks: [
          for (final track in session.tracks)
            if (track.category == category)
              track.copyWith(selected: selected)
            else
              track,
        ],
        clearExport: true,
      ),
    );
  }

  void setTrackStyle(String id, RedactionStyle style) =>
      _updateTrack(id, (track) => track.copyWith(style: style));

  void holdTrackAt(String id, int timestampMs, {int? durationMs}) {
    final session = state.session;
    if (session == null) return;
    _updateTrack(id, (track) {
      final start = timestampMs.clamp(0, session.durationMs);
      final end = durationMs == null
          ? session.durationMs
          : (start + durationMs).clamp(start, session.durationMs);
      if (end <= start) return track;
      final hold = VideoHold(
        startMs: start,
        endMs: end,
        bounds: _safeBounds(track.boundsAt(start)),
      );
      final holds = [
        for (final existing in track.holds)
          if (existing.endMs < start || existing.startMs > end) existing,
        hold,
      ]..sort((a, b) => a.startMs.compareTo(b.startMs));
      return track.copyWith(
        startMs: min(track.startMs, start),
        endMs: max(track.endMs, end),
        holds: holds,
      );
    });
  }

  void clearTrackHolds(String id) =>
      _updateTrack(id, (track) => track.copyWith(holds: const []));

  void setVideoTrim(int startMs, int endMs) {
    final session = state.session;
    if (session == null) return;
    final minimumDuration = max(
      120,
      (1000 / session.frameRate.clamp(1, 120)).round() * 2,
    );
    final start = startMs.clamp(0, session.durationMs - minimumDuration);
    final end = endMs.clamp(start + minimumDuration, session.durationMs);
    final current = session.resolvedEditPlan;
    _commitVideoEdit(
      current.copyWith(
        trimStartMs: start,
        trimEndMs: end,
        removedRanges: [
          for (final range in current.removedRanges)
            if (range.endMs > start && range.startMs < end) range,
        ],
        splitPointsMs: [
          for (final point in current.splitPointsMs)
            if (point > start && point < end) point,
        ],
      ),
    );
  }

  void splitVideoAt(int timestampMs) {
    final session = state.session;
    if (session == null) return;
    final plan = session.resolvedEditPlan;
    final timestamp = timestampMs.clamp(plan.trimStartMs, plan.trimEndMs);
    if (!plan.includes(timestamp, session.durationMs)) return;
    final tooClose = <int>[
      plan.trimStartMs,
      ...plan.splitPointsMs,
      plan.trimEndMs,
    ].any((point) => (point - timestamp).abs() < 80);
    if (tooClose) return;
    final points = {...plan.splitPointsMs, timestamp}.toList()..sort();
    _commitVideoEdit(plan.copyWith(splitPointsMs: points));
  }

  void deleteVideoSegment(VideoTimeRange segment) {
    final session = state.session;
    if (session == null || segment.durationMs < 80) return;
    final plan = session.resolvedEditPlan;
    if (plan.isSegmentRemoved(segment)) return;
    final candidate = plan.copyWith(
      removedRanges: [...plan.removedRanges, segment],
    );
    if (candidate.outputDurationMs(session.durationMs) < 100) return;
    _commitVideoEdit(candidate, clearSelection: true);
  }

  void toggleVideoAudioMuted() {
    final session = state.session;
    if (session == null || !session.hasAudio) return;
    final plan = session.resolvedEditPlan;
    _commitVideoEdit(plan.copyWith(audioMuted: !plan.audioMuted));
  }

  void removeVideoRange(int startMs, int endMs) {
    final session = state.session;
    if (session == null) return;
    final plan = session.resolvedEditPlan;
    final start = startMs.clamp(plan.trimStartMs, plan.trimEndMs);
    final end = endMs.clamp(start, plan.trimEndMs);
    if (end - start < 100) return;
    final next = [
      ...plan.removedRanges,
      VideoTimeRange(startMs: start, endMs: end),
    ]..sort((a, b) => a.startMs.compareTo(b.startMs));
    final candidate = plan.copyWith(removedRanges: next);
    if (candidate.outputDurationMs(session.durationMs) < 100) return;
    _commitVideoEdit(candidate, clearSelection: true);
  }

  void undoLastVideoCut() {
    undoVideoEdit();
  }

  void undoVideoEdit() {
    final session = state.session;
    if (session == null || _videoEditUndo.isEmpty) return;
    _videoEditRedo.add(session.resolvedEditPlan);
    final previous = _videoEditUndo.removeLast();
    _commit(
      session.copyWith(editPlan: previous, clearExport: true),
      clearSelection: true,
    );
    _refreshVideoEditHistory();
  }

  void redoVideoEdit() {
    final session = state.session;
    if (session == null || _videoEditRedo.isEmpty) return;
    _videoEditUndo.add(session.resolvedEditPlan);
    final next = _videoEditRedo.removeLast();
    _commit(
      session.copyWith(editPlan: next, clearExport: true),
      clearSelection: true,
    );
    _refreshVideoEditHistory();
  }

  void resetVideoEdits() {
    final session = state.session;
    if (session == null) return;
    _commitVideoEdit(VideoEditPlan.full(session.durationMs));
  }

  void deleteTrack(String id) {
    final session = state.session;
    if (session == null) return;
    _commit(
      session.copyWith(
        tracks: session.tracks.where((track) => track.id != id).toList(),
        clearExport: true,
      ),
      clearSelection: state.selectedTrackId == id,
    );
  }

  String addManualTrack({
    required Rect bounds,
    required int startMs,
    required int endMs,
    required RedactionStyle style,
  }) {
    final session = state.session!;
    final id = 'video_manual_${DateTime.now().microsecondsSinceEpoch}';
    final safeStart = startMs.clamp(0, session.durationMs);
    final safeEnd = endMs.clamp(safeStart, session.durationMs);
    final track = VideoRedactionTrack(
      id: id,
      category: RedactionCategory.manual,
      startMs: safeStart,
      endMs: safeEnd,
      keyframes: [
        VideoKeyframe(timestampMs: safeStart, bounds: _safeBounds(bounds)),
        if (safeEnd != safeStart)
          VideoKeyframe(timestampMs: safeEnd, bounds: _safeBounds(bounds)),
      ],
      selected: true,
      style: style,
      source: RedactionSource.manual,
    );
    _commit(
      session.copyWith(tracks: [...session.tracks, track], clearExport: true),
      selectedTrackId: id,
    );
    return id;
  }

  void updateTrackBounds(
    String id,
    int timestampMs,
    Rect bounds, {
    VideoTrackEditScope scope = VideoTrackEditScope.thisMoment,
  }) {
    final session = state.session;
    if (session == null) return;
    _updateTrack(id, (track) {
      final safeTimestamp = timestampMs.clamp(track.startMs, track.endMs);
      final reference = track.boundsAt(safeTimestamp);
      final target = _safeBounds(bounds);
      final frames = [...track.keyframes];
      final replacement = VideoKeyframe(
        timestampMs: safeTimestamp,
        bounds: target,
      );
      final frameToleranceMs = max(
        4,
        (500 / session.frameRate.clamp(1, 120)).round(),
      );
      var holds = [...track.holds];
      switch (scope) {
        case VideoTrackEditScope.thisMoment:
          _insertOrReplaceFrame(
            frames,
            replacement,
            toleranceMs: frameToleranceMs,
          );
          holds = _replaceHoldMoment(
            holds,
            safeTimestamp,
            target,
            toleranceMs: frameToleranceMs,
          );
          break;
        case VideoTrackEditScope.fromHere:
          for (var index = 0; index < frames.length; index++) {
            if (frames[index].timestampMs < safeTimestamp) continue;
            frames[index] = VideoKeyframe(
              timestampMs: frames[index].timestampMs,
              bounds: _transformBounds(frames[index].bounds, reference, target),
            );
          }
          _insertOrReplaceFrame(
            frames,
            replacement,
            toleranceMs: frameToleranceMs,
          );
          holds = _transformHoldsFrom(holds, safeTimestamp, reference, target);
          break;
        case VideoTrackEditScope.entireTrack:
          for (var index = 0; index < frames.length; index++) {
            frames[index] = VideoKeyframe(
              timestampMs: frames[index].timestampMs,
              bounds: _transformBounds(frames[index].bounds, reference, target),
            );
          }
          holds = [
            for (final hold in holds)
              VideoHold(
                startMs: hold.startMs,
                endMs: hold.endMs,
                bounds: _transformBounds(hold.bounds, reference, target),
              ),
          ];
          break;
      }
      frames.sort((a, b) => a.timestampMs.compareTo(b.timestampMs));
      holds.sort((a, b) => a.startMs.compareTo(b.startMs));
      return track.copyWith(keyframes: frames, holds: holds);
    });
  }

  List<VideoHold> _replaceHoldMoment(
    List<VideoHold> holds,
    int timestampMs,
    Rect target, {
    required int toleranceMs,
  }) {
    final activeIndex = holds.lastIndexWhere(
      (hold) => hold.contains(timestampMs),
    );
    if (activeIndex < 0) return holds;
    final active = holds[activeIndex];
    final momentStart = max(active.startMs, timestampMs - toleranceMs);
    final momentEnd = min(active.endMs, timestampMs + toleranceMs);
    return [
      for (var index = 0; index < holds.length; index++)
        if (index != activeIndex)
          holds[index]
        else ...[
          if (active.startMs < momentStart)
            VideoHold(
              startMs: active.startMs,
              endMs: momentStart - 1,
              bounds: active.bounds,
            ),
          VideoHold(startMs: momentStart, endMs: momentEnd, bounds: target),
          if (momentEnd < active.endMs)
            VideoHold(
              startMs: momentEnd + 1,
              endMs: active.endMs,
              bounds: active.bounds,
            ),
        ],
    ];
  }

  List<VideoHold> _transformHoldsFrom(
    List<VideoHold> holds,
    int timestampMs,
    Rect reference,
    Rect target,
  ) => [
    for (final hold in holds)
      if (hold.endMs < timestampMs)
        hold
      else ...[
        if (hold.startMs < timestampMs)
          VideoHold(
            startMs: hold.startMs,
            endMs: timestampMs - 1,
            bounds: hold.bounds,
          ),
        VideoHold(
          startMs: max(hold.startMs, timestampMs),
          endMs: hold.endMs,
          bounds: _transformBounds(hold.bounds, reference, target),
        ),
      ],
  ];

  void _insertOrReplaceFrame(
    List<VideoKeyframe> frames,
    VideoKeyframe replacement, {
    required int toleranceMs,
  }) {
    final nearby = frames.indexWhere(
      (frame) =>
          (frame.timestampMs - replacement.timestampMs).abs() <= toleranceMs,
    );
    if (nearby >= 0) {
      frames[nearby] = replacement;
    } else {
      frames.add(replacement);
    }
  }

  Rect _transformBounds(Rect source, Rect reference, Rect target) {
    final widthScale = reference.width <= 0
        ? 1.0
        : target.width / reference.width;
    final heightScale = reference.height <= 0
        ? 1.0
        : target.height / reference.height;
    return _safeBounds(
      Rect.fromLTWH(
        source.left + target.left - reference.left,
        source.top + target.top - reference.top,
        source.width * widthScale,
        source.height * heightScale,
      ),
    );
  }

  void _updateTrack(
    String id,
    VideoRedactionTrack Function(VideoRedactionTrack track) update,
  ) {
    final session = state.session;
    if (session == null) return;
    _commit(
      session.copyWith(
        tracks: [
          for (final track in session.tracks)
            if (track.id == id) update(track) else track,
        ],
        clearExport: true,
      ),
    );
  }

  Future<void> export() async {
    final session = state.session;
    if (session == null || state.isBusy) return;
    final activeTracks = session.exportTracks().length;
    if (activeTracks > privacyCamVideoMaxExportTracks) {
      const message =
          'This video has more than 48 active privacy tracks. Deselect ordinary text you do not need, or cover nearby details with one manual area.';
      state = state.copyWith(stage: VideoWorkStage.failed, error: message);
      throw const VideoServiceException(message);
    }
    final settings = ref.read(settingsProvider);
    _cancelled = false;
    state = state.copyWith(
      stage: VideoWorkStage.exporting,
      progress: 0,
      detail: 'Preparing secure video export',
      clearError: true,
    );
    await _exportProgress?.cancel();
    _exportProgress = ref.read(videoServiceProvider).exportProgress.listen((
      progress,
    ) {
      if (_cancelled) return;
      state = state.copyWith(
        progress: progress,
        detail: progress < .9
            ? 'Applying redactions to every frame'
            : 'Removing metadata and verifying the copy',
      );
    });
    String? outputPath;
    try {
      final path = await ref
          .read(videoServiceProvider)
          .export(
            session,
            blurStrength: settings.blurStrength,
            pixelSize: settings.pixelSize,
          );
      outputPath = path;
      if (_cancelled) return;
      final detectedCodeTracks = session.tracks.where(
        (track) =>
            track.category == RedactionCategory.qrCode ||
            track.category == RedactionCategory.barcode,
      );
      final verifyCodes =
          detectedCodeTracks.any((track) => track.selected) ||
          detectedCodeTracks.isEmpty &&
              (settings.autoHideCategories.contains(RedactionCategory.qrCode) ||
                  settings.autoHideCategories.contains(
                    RedactionCategory.barcode,
                  ));
      if (verifyCodes) {
        state = state.copyWith(
          progress: .99,
          detail: 'Checking the first and last frames for readable codes',
        );
        await _verifyExportCodeEdges(
          path,
          session.resolvedEditPlan.outputDurationMs(session.durationMs),
        );
      }
      if (_cancelled) return;
      final previousExport = session.exportPath;
      final updated = session.copyWith(exportPath: path, metadataRemoved: true);
      state = state.copyWith(
        session: updated,
        stage: VideoWorkStage.complete,
        progress: 1,
        detail: 'Privacy-safe video ready',
      );
      await _persist();
      if (!settings.keepTemporary && previousExport != path) {
        await ref.read(videoServiceProvider).deleteWorkingFile(previousExport);
      }
    } catch (error) {
      await ref.read(videoServiceProvider).deleteWorkingFile(outputPath);
      if (_cancelled) return;
      state = state.copyWith(
        stage: VideoWorkStage.failed,
        error: error.toString(),
      );
      rethrow;
    } finally {
      await _exportProgress?.cancel();
      _exportProgress = null;
    }
  }

  Future<void> _verifyExportCodeEdges(String path, int durationMs) async {
    final guardMs = min(2200, durationMs);
    final timestamps = <int>{
      0,
      max(0, durationMs - 1),
      max(0, durationMs - 34),
      max(0, durationMs - 67),
    };
    for (var offset = 0; offset <= guardMs; offset += 200) {
      timestamps.add(offset.clamp(0, durationMs));
      timestamps.add((durationMs - offset).clamp(0, durationMs));
    }
    final service = ref.read(videoServiceProvider);
    final frames = await service.extractFrames(
      path,
      timestamps.toList()..sort(),
    );
    try {
      final detector = ref.read(detectionProvider);
      for (final frame in frames) {
        if (_cancelled) return;
        final codes = await detector.detectCodesFast(
          frame.path,
          Size(frame.width.toDouble(), frame.height.toDouble()),
        );
        if (codes.isNotEmpty) {
          throw const VideoServiceException(
            'A readable QR code or barcode remained near the beginning or end of the exported video. Export was stopped so an unsafe copy cannot be saved or shared. Return to the editor, increase pixelation, or add a manual area over the code.',
          );
        }
      }
    } finally {
      await service.deleteFrames(frames);
    }
  }

  Future<void> clear() async {
    _cancelled = true;
    _videoEditUndo.clear();
    _videoEditRedo.clear();
    final session = state.session;
    state = const VideoEditorState();
    await ref.read(sharedPreferencesProvider).remove(_storageKey);
    if (session != null && !ref.read(settingsProvider).keepTemporary) {
      await ref
          .read(videoServiceProvider)
          .deleteWorkingFile(session.sourcePath);
      await ref
          .read(videoServiceProvider)
          .deleteWorkingFile(session.exportPath);
    }
  }

  void _commit(
    VideoSession session, {
    String? selectedTrackId,
    bool clearSelection = false,
  }) {
    state = state.copyWith(
      session: session,
      stage: VideoWorkStage.ready,
      selectedTrackId: selectedTrackId,
      clearSelection: clearSelection,
    );
    unawaited(_persist());
  }

  void _commitVideoEdit(VideoEditPlan plan, {bool clearSelection = false}) {
    final session = state.session;
    if (session == null || plan == session.resolvedEditPlan) return;
    _videoEditUndo.add(session.resolvedEditPlan);
    _videoEditRedo.clear();
    _commit(
      session.copyWith(editPlan: plan, clearExport: true),
      clearSelection: clearSelection,
    );
    _refreshVideoEditHistory();
  }

  void _refreshVideoEditHistory() {
    state = state.copyWith(
      canUndoVideoEdit: _videoEditUndo.isNotEmpty,
      canRedoVideoEdit: _videoEditRedo.isNotEmpty,
    );
  }

  Rect _safeBounds(Rect bounds) {
    const minimum = .02;
    final width = bounds.width.abs().clamp(minimum, 1.0);
    final height = bounds.height.abs().clamp(minimum, 1.0);
    final rawLeft = min(bounds.left, bounds.right);
    final rawTop = min(bounds.top, bounds.bottom);
    final left = rawLeft.clamp(0.0, 1.0 - width);
    final top = rawTop.clamp(0.0, 1.0 - height);
    return Rect.fromLTWH(left, top, width, height);
  }

  Future<void> _persist() async {
    final session = state.session;
    if (session == null) {
      await ref.read(sharedPreferencesProvider).remove(_storageKey);
      return;
    }
    await ref
        .read(sharedPreferencesProvider)
        .setString(_storageKey, jsonEncode(session.toJson()));
  }
}

final videoEditorProvider =
    NotifierProvider<VideoEditorController, VideoEditorState>(
      VideoEditorController.new,
    );
