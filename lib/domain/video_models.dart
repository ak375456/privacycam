import 'dart:ui';

import 'models.dart';

const int privacyCamVideoFreeMaxDurationMs = 15 * 1000;
const int privacyCamVideoMaxDurationMs = 60 * 1000;
const int privacyCamVideoMaxBytes = 600 * 1024 * 1024;
const int privacyCamVideoMaxExportTracks = 48;
const int privacyCamVideoAnalysisVersion = 11;

bool privacyCamVideoRequiresPro(int durationMs) =>
    durationMs > privacyCamVideoFreeMaxDurationMs;

class VideoProRequiredException implements Exception {
  const VideoProRequiredException();

  @override
  String toString() => 'Videos longer than 15 seconds require PrivacyCam Pro.';
}

enum VideoWorkStage {
  idle,
  importing,
  preparing,
  detecting,
  buildingTracks,
  ready,
  exporting,
  complete,
  failed,
}

enum VideoTrackEditScope { thisMoment, fromHere, entireTrack }

class VideoInfo {
  const VideoInfo({
    required this.durationMs,
    required this.width,
    required this.height,
    required this.hasAudio,
    required this.fileSize,
    required this.frameRate,
  });

  final int durationMs;
  final int width;
  final int height;
  final bool hasAudio;
  final int fileSize;
  final double frameRate;

  factory VideoInfo.fromMap(Map<Object?, Object?> map) => VideoInfo(
    durationMs: (map['durationMs'] as num).round(),
    width: (map['width'] as num).round(),
    height: (map['height'] as num).round(),
    hasAudio: map['hasAudio'] as bool? ?? false,
    fileSize: (map['fileSize'] as num?)?.round() ?? 0,
    frameRate: ((map['frameRate'] as num?)?.toDouble() ?? 30).clamp(1, 120),
  );
}

class VideoFrame {
  const VideoFrame({
    required this.timestampMs,
    required this.path,
    required this.width,
    required this.height,
  });

  final int timestampMs;
  final String path;
  final int width;
  final int height;

  factory VideoFrame.fromMap(Map<Object?, Object?> map) => VideoFrame(
    timestampMs: (map['timestampMs'] as num).round(),
    path: map['path']! as String,
    width: (map['width'] as num).round(),
    height: (map['height'] as num).round(),
  );
}

class VideoKeyframe {
  const VideoKeyframe({required this.timestampMs, required this.bounds});

  final int timestampMs;
  final Rect bounds;

  Map<String, Object?> toJson() => {
    'timestampMs': timestampMs,
    'bounds': [bounds.left, bounds.top, bounds.right, bounds.bottom],
  };

  factory VideoKeyframe.fromJson(Map<String, Object?> json) {
    final values = (json['bounds']! as List).cast<num>();
    return VideoKeyframe(
      timestampMs: json['timestampMs']! as int,
      bounds: Rect.fromLTRB(
        values[0].toDouble(),
        values[1].toDouble(),
        values[2].toDouble(),
        values[3].toDouble(),
      ),
    );
  }
}

class VideoHold {
  const VideoHold({
    required this.startMs,
    required this.endMs,
    required this.bounds,
  });

  final int startMs;
  final int endMs;
  final Rect bounds;

  bool contains(int timestampMs) =>
      timestampMs >= startMs && timestampMs <= endMs;

  Map<String, Object?> toJson() => {
    'startMs': startMs,
    'endMs': endMs,
    'bounds': [bounds.left, bounds.top, bounds.right, bounds.bottom],
  };

  factory VideoHold.fromJson(Map<String, Object?> json) {
    final values = (json['bounds']! as List).cast<num>();
    return VideoHold(
      startMs: (json['startMs']! as num).round(),
      endMs: (json['endMs']! as num).round(),
      bounds: Rect.fromLTRB(
        values[0].toDouble(),
        values[1].toDouble(),
        values[2].toDouble(),
        values[3].toDouble(),
      ),
    );
  }
}

class VideoTimeRange {
  const VideoTimeRange({required this.startMs, required this.endMs});

  final int startMs;
  final int endMs;

  int get durationMs => endMs - startMs;

  bool contains(int timestampMs) =>
      timestampMs >= startMs && timestampMs < endMs;

  bool overlaps(VideoTimeRange other) =>
      startMs < other.endMs && endMs > other.startMs;

  Map<String, Object?> toJson() => {'startMs': startMs, 'endMs': endMs};

  factory VideoTimeRange.fromJson(Map<String, Object?> json) => VideoTimeRange(
    startMs: (json['startMs']! as num).round(),
    endMs: (json['endMs']! as num).round(),
  );
}

class VideoEditPlan {
  const VideoEditPlan({
    required this.trimStartMs,
    required this.trimEndMs,
    this.removedRanges = const [],
    this.splitPointsMs = const [],
    this.audioMuted = false,
  });

  final int trimStartMs;
  final int trimEndMs;
  final List<VideoTimeRange> removedRanges;
  final List<int> splitPointsMs;
  final bool audioMuted;

  factory VideoEditPlan.full(int durationMs) =>
      VideoEditPlan(trimStartMs: 0, trimEndMs: durationMs);

  List<VideoTimeRange> keptRanges(int durationMs) {
    final start = trimStartMs.clamp(0, durationMs);
    final end = trimEndMs.clamp(start, durationMs);
    final cuts =
        removedRanges
            .map(
              (range) => VideoTimeRange(
                startMs: range.startMs.clamp(start, end),
                endMs: range.endMs.clamp(start, end),
              ),
            )
            .where((range) => range.durationMs > 0)
            .toList()
          ..sort((a, b) => a.startMs.compareTo(b.startMs));
    final merged = <VideoTimeRange>[];
    for (final range in cuts) {
      if (merged.isEmpty || range.startMs > merged.last.endMs) {
        merged.add(range);
      } else {
        final previous = merged.removeLast();
        merged.add(
          VideoTimeRange(
            startMs: previous.startMs,
            endMs: range.endMs > previous.endMs ? range.endMs : previous.endMs,
          ),
        );
      }
    }
    final kept = <VideoTimeRange>[];
    var cursor = start;
    for (final cut in merged) {
      if (cut.startMs > cursor) {
        kept.add(VideoTimeRange(startMs: cursor, endMs: cut.startMs));
      }
      if (cut.endMs > cursor) cursor = cut.endMs;
    }
    if (cursor < end) {
      kept.add(VideoTimeRange(startMs: cursor, endMs: end));
    }
    return kept;
  }

  int outputDurationMs(int durationMs) => keptRanges(
    durationMs,
  ).fold(0, (total, range) => total + range.durationMs);

  int outputOffsetForSourceTimestamp(int timestampMs, int durationMs) {
    final safe = timestampMs.clamp(0, durationMs);
    var outputOffset = 0;
    for (final range in keptRanges(durationMs)) {
      if (safe < range.startMs) return outputOffset;
      if (safe < range.endMs) {
        return outputOffset + safe - range.startMs;
      }
      outputOffset += range.durationMs;
    }
    return outputOffset;
  }

  int sourceTimestampForOutputOffset(int outputOffsetMs, int durationMs) {
    final ranges = keptRanges(durationMs);
    if (ranges.isEmpty) return trimStartMs.clamp(0, durationMs);
    final safe = outputOffsetMs.clamp(0, outputDurationMs(durationMs));
    var cursor = 0;
    for (var index = 0; index < ranges.length; index++) {
      final range = ranges[index];
      final next = cursor + range.durationMs;
      if (safe < next || index == ranges.length - 1) {
        return (range.startMs + safe - cursor).clamp(
          range.startMs,
          range.endMs,
        );
      }
      cursor = next;
    }
    return ranges.last.endMs;
  }

  bool includes(int timestampMs, int durationMs) =>
      keptRanges(durationMs).any((range) => range.contains(timestampMs));

  int? nextIncludedTimestamp(int timestampMs, int durationMs) {
    for (final range in keptRanges(durationMs)) {
      if (range.contains(timestampMs)) return timestampMs;
      if (range.startMs > timestampMs) return range.startMs;
    }
    return null;
  }

  List<VideoTimeRange> segments(int durationMs) {
    final start = trimStartMs.clamp(0, durationMs);
    final end = trimEndMs.clamp(start, durationMs);
    final points =
        splitPointsMs
            .where((point) => point > start && point < end)
            .toSet()
            .toList()
          ..sort();
    final boundaries = <int>[start, ...points, end];
    return [
      for (var index = 1; index < boundaries.length; index++)
        VideoTimeRange(
          startMs: boundaries[index - 1],
          endMs: boundaries[index],
        ),
    ];
  }

  List<VideoTimeRange> keptSegments(int durationMs) {
    final points = splitPointsMs.toSet().toList()..sort();
    return [
      for (final kept in keptRanges(durationMs))
        ...() {
          final inside = points.where(
            (point) => point > kept.startMs && point < kept.endMs,
          );
          final boundaries = <int>[kept.startMs, ...inside, kept.endMs];
          return [
            for (var index = 1; index < boundaries.length; index++)
              VideoTimeRange(
                startMs: boundaries[index - 1],
                endMs: boundaries[index],
              ),
          ];
        }(),
    ];
  }

  bool isSegmentRemoved(VideoTimeRange segment) => removedRanges.any(
    (range) => range.startMs <= segment.startMs && range.endMs >= segment.endMs,
  );

  VideoEditPlan copyWith({
    int? trimStartMs,
    int? trimEndMs,
    List<VideoTimeRange>? removedRanges,
    List<int>? splitPointsMs,
    bool? audioMuted,
  }) => VideoEditPlan(
    trimStartMs: trimStartMs ?? this.trimStartMs,
    trimEndMs: trimEndMs ?? this.trimEndMs,
    removedRanges: removedRanges ?? this.removedRanges,
    splitPointsMs: splitPointsMs ?? this.splitPointsMs,
    audioMuted: audioMuted ?? this.audioMuted,
  );

  Map<String, Object?> toJson() => {
    'trimStartMs': trimStartMs,
    'trimEndMs': trimEndMs,
    'removedRanges': [for (final range in removedRanges) range.toJson()],
    'splitPointsMs': splitPointsMs,
    'audioMuted': audioMuted,
  };

  factory VideoEditPlan.fromJson(Map<String, Object?> json) => VideoEditPlan(
    trimStartMs: (json['trimStartMs']! as num).round(),
    trimEndMs: (json['trimEndMs']! as num).round(),
    removedRanges: [
      for (final value in json['removedRanges'] as List? ?? const [])
        VideoTimeRange.fromJson(Map<String, Object?>.from(value as Map)),
    ],
    splitPointsMs: [
      for (final value in json['splitPointsMs'] as List? ?? const [])
        (value as num).round(),
    ],
    audioMuted: json['audioMuted'] as bool? ?? false,
  );
}

class VideoRedactionTrack {
  const VideoRedactionTrack({
    required this.id,
    required this.category,
    required this.startMs,
    required this.endMs,
    required this.keyframes,
    required this.selected,
    required this.style,
    required this.source,
    this.holds = const [],
    this.confidence,
  });

  final String id;
  final RedactionCategory category;
  final int startMs;
  final int endMs;
  final List<VideoKeyframe> keyframes;
  final bool selected;
  final RedactionStyle style;
  final RedactionSource source;
  final List<VideoHold> holds;
  final double? confidence;

  bool isVisibleAt(int timestampMs) => selected && existsAt(timestampMs);

  bool existsAt(int timestampMs) =>
      timestampMs >= startMs && timestampMs <= endMs;

  Rect boundsAt(int timestampMs) {
    for (final hold in holds.reversed) {
      if (hold.contains(timestampMs)) return hold.bounds;
    }
    if (keyframes.isEmpty) return Rect.zero;
    if (timestampMs <= keyframes.first.timestampMs) {
      return keyframes.first.bounds;
    }
    if (timestampMs >= keyframes.last.timestampMs) return keyframes.last.bounds;
    for (var index = 1; index < keyframes.length; index++) {
      final next = keyframes[index];
      if (timestampMs > next.timestampMs) continue;
      final previous = keyframes[index - 1];
      final span = next.timestampMs - previous.timestampMs;
      final t = span == 0 ? 0.0 : (timestampMs - previous.timestampMs) / span;
      return Rect.lerp(previous.bounds, next.bounds, t) ?? previous.bounds;
    }
    return keyframes.last.bounds;
  }

  VideoRedactionTrack copyWith({
    int? startMs,
    int? endMs,
    List<VideoKeyframe>? keyframes,
    bool? selected,
    RedactionStyle? style,
    List<VideoHold>? holds,
  }) => VideoRedactionTrack(
    id: id,
    category: category,
    startMs: startMs ?? this.startMs,
    endMs: endMs ?? this.endMs,
    keyframes: keyframes ?? this.keyframes,
    selected: selected ?? this.selected,
    style: style ?? this.style,
    source: source,
    holds: holds ?? this.holds,
    confidence: confidence,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'category': category.name,
    'startMs': startMs,
    'endMs': endMs,
    'keyframes': [for (final keyframe in keyframes) keyframe.toJson()],
    'selected': selected,
    'style': style.name,
    'source': source.name,
    'holds': [for (final hold in holds) hold.toJson()],
    'confidence': confidence,
  };

  factory VideoRedactionTrack.fromJson(Map<String, Object?> json) =>
      VideoRedactionTrack(
        id: json['id']! as String,
        category: RedactionCategory.values.byName(json['category']! as String),
        startMs: json['startMs']! as int,
        endMs: json['endMs']! as int,
        keyframes: [
          for (final value in json['keyframes'] as List? ?? const [])
            VideoKeyframe.fromJson(Map<String, Object?>.from(value as Map)),
        ],
        selected: json['selected'] as bool? ?? true,
        style: RedactionStyle.values.byName(json['style']! as String),
        source: RedactionSource.values.byName(json['source']! as String),
        holds: [
          for (final value in json['holds'] as List? ?? const [])
            VideoHold.fromJson(Map<String, Object?>.from(value as Map)),
        ],
        confidence: (json['confidence'] as num?)?.toDouble(),
      );
}

class VideoSession {
  const VideoSession({
    required this.sourcePath,
    required this.durationMs,
    required this.width,
    required this.height,
    required this.hasAudio,
    this.frameRate = 30,
    this.tracks = const [],
    this.exportPath,
    this.metadataRemoved = false,
    this.analysisVersion = privacyCamVideoAnalysisVersion,
    VideoEditPlan? editPlan,
  }) : editPlan = editPlan ?? const VideoEditPlan(trimStartMs: 0, trimEndMs: 0);

  final String sourcePath;
  final int durationMs;
  final int width;
  final int height;
  final bool hasAudio;
  final double frameRate;
  final List<VideoRedactionTrack> tracks;
  final String? exportPath;
  final bool metadataRemoved;
  final int analysisVersion;
  final VideoEditPlan editPlan;

  VideoEditPlan get resolvedEditPlan =>
      editPlan.trimEndMs == 0 ? VideoEditPlan.full(durationMs) : editPlan;

  VideoSession copyWith({
    List<VideoRedactionTrack>? tracks,
    String? exportPath,
    bool? metadataRemoved,
    int? analysisVersion,
    double? frameRate,
    VideoEditPlan? editPlan,
    bool clearExport = false,
  }) => VideoSession(
    sourcePath: sourcePath,
    durationMs: durationMs,
    width: width,
    height: height,
    hasAudio: hasAudio,
    frameRate: frameRate ?? this.frameRate,
    tracks: tracks ?? this.tracks,
    exportPath: clearExport ? null : exportPath ?? this.exportPath,
    metadataRemoved: metadataRemoved ?? this.metadataRemoved,
    analysisVersion: analysisVersion ?? this.analysisVersion,
    editPlan: editPlan ?? resolvedEditPlan,
  );

  Map<String, Object?> toJson() => {
    'sourcePath': sourcePath,
    'durationMs': durationMs,
    'width': width,
    'height': height,
    'hasAudio': hasAudio,
    'frameRate': frameRate,
    'tracks': [for (final track in tracks) track.toJson()],
    'exportPath': exportPath,
    'metadataRemoved': metadataRemoved,
    'analysisVersion': analysisVersion,
    'editPlan': resolvedEditPlan.toJson(),
  };

  factory VideoSession.fromJson(Map<String, Object?> json) => VideoSession(
    sourcePath: json['sourcePath']! as String,
    durationMs: json['durationMs']! as int,
    width: json['width']! as int,
    height: json['height']! as int,
    hasAudio: json['hasAudio'] as bool? ?? false,
    frameRate: ((json['frameRate'] as num?)?.toDouble() ?? 30).clamp(1, 120),
    tracks: [
      for (final value in json['tracks'] as List? ?? const [])
        VideoRedactionTrack.fromJson(Map<String, Object?>.from(value as Map)),
    ],
    exportPath: json['exportPath'] as String?,
    metadataRemoved: json['metadataRemoved'] as bool? ?? false,
    analysisVersion: (json['analysisVersion'] as num?)?.round() ?? 1,
    editPlan: json['editPlan'] == null
        ? null
        : VideoEditPlan.fromJson(
            Map<String, Object?>.from(json['editPlan']! as Map),
          ),
  );

  List<Map<String, Object?>> exportTracks() {
    final exported = <Map<String, Object?>>[];
    var outputOffset = 0;
    for (final kept in resolvedEditPlan.keptRanges(durationMs)) {
      for (final track in tracks.where((item) => item.selected)) {
        final overlapStart = track.startMs > kept.startMs
            ? track.startMs
            : kept.startMs;
        final overlapEnd = track.endMs < kept.endMs ? track.endMs : kept.endMs;
        if (overlapEnd <= overlapStart) continue;
        final frames = <VideoKeyframe>[
          VideoKeyframe(
            timestampMs: outputOffset + overlapStart - kept.startMs,
            bounds: track.boundsAt(overlapStart),
          ),
          for (final frame in track.keyframes)
            if (frame.timestampMs > overlapStart &&
                frame.timestampMs < overlapEnd)
              VideoKeyframe(
                timestampMs: outputOffset + frame.timestampMs - kept.startMs,
                bounds: frame.bounds,
              ),
          VideoKeyframe(
            timestampMs: outputOffset + overlapEnd - kept.startMs,
            bounds: track.boundsAt(overlapEnd),
          ),
        ];
        final mapped = track.copyWith(
          startMs: outputOffset + overlapStart - kept.startMs,
          endMs: outputOffset + overlapEnd - kept.startMs,
          keyframes: frames,
          holds: [
            for (final hold in track.holds)
              if (hold.endMs > overlapStart && hold.startMs < overlapEnd)
                VideoHold(
                  startMs:
                      outputOffset +
                      (hold.startMs < overlapStart
                          ? overlapStart
                          : hold.startMs) -
                      kept.startMs,
                  endMs:
                      outputOffset +
                      (hold.endMs > overlapEnd ? overlapEnd : hold.endMs) -
                      kept.startMs,
                  bounds: hold.bounds,
                ),
          ],
        );
        exported.add(mapped.toJson());
      }
      outputOffset += kept.durationMs;
    }
    return exported;
  }

  List<Map<String, Object?>> exportEditRanges() => [
    for (final range in resolvedEditPlan.keptRanges(durationMs)) range.toJson(),
  ];
}

bool privacyCamVideoSessionRequiresPro(VideoSession session) =>
    privacyCamVideoRequiresPro(
      session.resolvedEditPlan.outputDurationMs(session.durationMs),
    );
