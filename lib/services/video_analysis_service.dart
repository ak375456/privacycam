import 'dart:math';
import 'dart:ui';

import '../domain/models.dart';
import '../domain/video_models.dart';
import 'detection_service.dart';
import 'video_service.dart';

class VideoAnalysisService {
  const VideoAnalysisService({
    required this.videoService,
    required this.detectionService,
  });

  final VideoService videoService;
  final DetectionService detectionService;

  Future<List<VideoRedactionTrack>> analyze(
    VideoSession session, {
    required Set<RedactionCategory> autoHideCategories,
    required RedactionStyle faceStyle,
    required RedactionStyle peopleStyle,
    required RedactionStyle sensitiveStyle,
    required void Function(double progress, String detail) onProgress,
    required bool Function() isCancelled,
  }) async {
    // Faces need frequent positions to follow motion naturally. Expensive
    // object and text checks use their own, much slower cadence below.
    final intervalMs = max(300, (session.durationMs / 120).ceil());
    final timestamps = {
      for (var time = 0; time < session.durationMs; time += intervalMs) time,
      if (session.durationMs > 0) max(0, session.durationMs - 1),
    }.toList()..sort();
    onProgress(.02, 'Preparing ${timestamps.length} private frame checks');
    final frames = await videoService.extractFrames(
      session.sourcePath,
      timestamps,
    );
    final faceVerificationStride = _strideFor(600, intervalMs);
    final edgeProbeStride = _strideFor(1800, intervalMs);
    final peopleStride = _strideFor(1200, intervalMs);
    final plateStride = _strideFor(
      autoHideCategories.contains(RedactionCategory.numberPlate) ? 900 : 1800,
      intervalMs,
    );
    final codeStride = _strideFor(
      autoHideCategories.contains(RedactionCategory.qrCode) ||
              autoHideCategories.contains(RedactionCategory.barcode)
          ? 450
          : 1800,
      intervalMs,
    );
    final textStride = _strideFor(3000, intervalMs);
    const sensitiveTextCategories = {
      RedactionCategory.email,
      RedactionCategory.phone,
      RedactionCategory.address,
      RedactionCategory.card,
      RedactionCategory.cardSecurityCode,
      RedactionCategory.url,
    };
    final detectSensitiveText = autoHideCategories.any(
      sensitiveTextCategories.contains,
    );
    final builder = _TrackBuilder(
      durationMs: session.durationMs,
      sampleIntervalMs: intervalMs,
      detectorStride: {
        RedactionCategory.face: 1,
        RedactionCategory.person: peopleStride,
        RedactionCategory.numberPlate: plateStride,
        RedactionCategory.qrCode: codeStride,
        RedactionCategory.barcode: codeStride,
        RedactionCategory.email: textStride,
        RedactionCategory.phone: textStride,
        RedactionCategory.address: textStride,
        RedactionCategory.card: textStride,
        RedactionCategory.cardSecurityCode: textStride,
        RedactionCategory.url: textStride,
      },
    );
    var lastFaceDetectionMs = -100000;
    try {
      for (var index = 0; index < frames.length; index++) {
        if (isCancelled()) return const [];
        final frame = frames[index];
        final size = Size(frame.width.toDouble(), frame.height.toDouble());
        final detections = <RedactionItem>[];

        final faces = await detectionService.detectFacesVideo(
          frame.path,
          size,
          verificationPass: index % faceVerificationStride == 0,
          recoverEdges:
              index % edgeProbeStride == 0 ||
              frame.timestampMs - lastFaceDetectionMs <= 1800,
        );
        if (faces.isNotEmpty) lastFaceDetectionMs = frame.timestampMs;
        detections.addAll(faces);
        // Match the image review flow: always find people, then let the user
        // decide whether full-body tracks should be hidden. The setting only
        // controls the initial selection state; it must not remove the choice.
        if (index % peopleStride == 0) {
          final people = await detectionService.detectPeople(frame.path, size);
          // Use the same accepted person detections as still images. A
          // video-only confidence/aspect filter used to reject people as soon
          // as they sat, bent, or turned sideways, ending the body mask while
          // the person was still plainly visible.
          detections.addAll(people);
        }
        if (index % plateStride == 0) {
          final plates = await detectionService.detectNumberPlates(
            frame.path,
            size,
          );
          detections.addAll(
            plates.where((item) => (item.confidence ?? 0) >= .40),
          );
        }
        if (index % codeStride == 0) {
          detections.addAll(
            await detectionService.detectCodesFast(frame.path, size),
          );
        }
        if (detectSensitiveText && index % textStride == 0) {
          final text = await detectionService.detectText(frame.path, size);
          // Ordinary captions, signs and UI labels are intentionally ignored
          // in video. They create dozens of tracks and are not private data.
          detections.addAll(
            text.where(
              (item) => sensitiveTextCategories.contains(item.category),
            ),
          );
        }
        builder.addFrame(
          frame.timestampMs,
          _deduplicate(
            detections,
          ).map((item) => _normalize(item, size)).toList(),
        );
        final fraction = (index + 1) / max(1, frames.length);
        onProgress(
          .08 + fraction * .84,
          'Checking frame ${index + 1} of ${frames.length}',
        );
      }
      onProgress(.95, 'Building smooth privacy tracks');
      return builder.finish(
        autoHideCategories: autoHideCategories,
        faceStyle: faceStyle,
        peopleStyle: peopleStyle,
        sensitiveStyle: sensitiveStyle,
      );
    } finally {
      await videoService.deleteFrames(frames);
    }
  }

  RedactionItem _normalize(RedactionItem item, Size size) {
    var bounds = Rect.fromLTRB(
      (item.bounds.left / size.width).clamp(0, 1),
      (item.bounds.top / size.height).clamp(0, 1),
      (item.bounds.right / size.width).clamp(0, 1),
      (item.bounds.bottom / size.height).clamp(0, 1),
    );
    final safetyPadding = switch (item.category) {
      RedactionCategory.qrCode => .18,
      RedactionCategory.barcode => .14,
      RedactionCategory.numberPlate => .10,
      _ => 0.0,
    };
    if (safetyPadding > 0) {
      bounds = Rect.fromLTRB(
        (bounds.left - bounds.width * safetyPadding).clamp(0, 1),
        (bounds.top - bounds.height * safetyPadding).clamp(0, 1),
        (bounds.right + bounds.width * safetyPadding).clamp(0, 1),
        (bounds.bottom + bounds.height * safetyPadding).clamp(0, 1),
      );
    }
    return item.copyWith(bounds: bounds);
  }

  List<RedactionItem> _deduplicate(List<RedactionItem> items) {
    final result = <RedactionItem>[];
    for (final item in items) {
      final duplicate = result.any(
        (other) =>
            other.category == item.category &&
            _intersectionOverUnion(other.bounds, item.bounds) > .72,
      );
      if (!duplicate) result.add(item);
    }
    return result;
  }
}

int _strideFor(int cadenceMs, int sampleIntervalMs) =>
    max(1, (cadenceMs / sampleIntervalMs).ceil());

class _MutableTrack {
  _MutableTrack({
    required this.id,
    required this.category,
    required this.source,
    required this.confidence,
    required this.keyframes,
  });

  final String id;
  final RedactionCategory category;
  final RedactionSource source;
  final double? confidence;
  final List<VideoKeyframe> keyframes;

  VideoKeyframe get last => keyframes.last;
}

class _TrackBuilder {
  _TrackBuilder({
    required this.durationMs,
    required this.sampleIntervalMs,
    required this.detectorStride,
  });
  final int durationMs;
  final int sampleIntervalMs;
  final Map<RedactionCategory, int> detectorStride;
  final tracks = <_MutableTrack>[];

  void addFrame(int timestampMs, List<RedactionItem> detections) {
    final claimed = <_MutableTrack>{};
    for (final detection in detections) {
      _MutableTrack? best;
      var bestScore = -1.0;
      for (final track in tracks) {
        if (claimed.contains(track) || track.category != detection.category) {
          continue;
        }
        final gap = timestampMs - track.last.timestampMs;
        if (gap < 0 ||
            gap > _maximumGap(detection.category, track.last.bounds)) {
          continue;
        }
        if (!_isPlausibleMatch(
          detection.category,
          track.last.bounds,
          detection.bounds,
        )) {
          continue;
        }
        final score = _matchScore(track.last.bounds, detection.bounds);
        final edgeFace =
            detection.category == RedactionCategory.face &&
            (_isAtFrameEdge(track.last.bounds) ||
                _isAtFrameEdge(detection.bounds));
        final minimumScore = edgeFace
            ? .12
            : detection.category == RedactionCategory.face
            ? .25
            : detection.category == RedactionCategory.person
            ? .12
            : detection.category == RedactionCategory.qrCode ||
                  detection.category == RedactionCategory.barcode
            ? .10
            : .24;
        if (score > bestScore && score >= minimumScore) {
          best = track;
          bestScore = score;
        }
      }
      if (best == null) {
        best = _MutableTrack(
          id: 'video_${detection.category.name}_${DateTime.now().microsecondsSinceEpoch}_${tracks.length}',
          category: detection.category,
          source: detection.source,
          confidence: detection.confidence,
          keyframes: [],
        );
        tracks.add(best);
      }
      best.keyframes.add(
        VideoKeyframe(timestampMs: timestampMs, bounds: detection.bounds),
      );
      claimed.add(best);
    }
  }

  List<VideoRedactionTrack> finish({
    required Set<RedactionCategory> autoHideCategories,
    required RedactionStyle faceStyle,
    required RedactionStyle peopleStyle,
    required RedactionStyle sensitiveStyle,
  }) {
    final result = <VideoRedactionTrack>[];
    for (final track in tracks) {
      final keyframes = [...track.keyframes];
      var startMs = max(
        0,
        keyframes.first.timestampMs -
            _edgePadding(track.category, keyframes.first.bounds),
      );
      var endMs = min(
        durationMs,
        keyframes.last.timestampMs +
            _edgePadding(track.category, keyframes.last.bounds),
      );
      final boundaryWindow = _boundaryWindow(track.category);
      if (boundaryWindow > 0 && keyframes.first.timestampMs <= boundaryWindow) {
        startMs = 0;
        if (keyframes.first.timestampMs > 0) {
          keyframes.insert(
            0,
            VideoKeyframe(
              timestampMs: 0,
              bounds: _boundaryEnvelope(
                keyframes.first.bounds,
                keyframes.length > 1
                    ? keyframes[1].bounds
                    : keyframes.first.bounds,
              ),
            ),
          );
        }
      }
      if (boundaryWindow > 0 &&
          durationMs - keyframes.last.timestampMs <= boundaryWindow) {
        endMs = durationMs;
        if (keyframes.last.timestampMs < durationMs) {
          keyframes.add(
            VideoKeyframe(
              timestampMs: durationMs,
              bounds: _boundaryEnvelope(
                keyframes.length > 1
                    ? keyframes[keyframes.length - 2].bounds
                    : keyframes.last.bounds,
                keyframes.last.bounds,
              ),
            ),
          );
        }
      }
      final holds = <VideoHold>[];
      final exitGuardMs = _exitGuardDuration(track.category);
      if (exitGuardMs > 0 && keyframes.isNotEmpty) {
        final lastDetectionMs = track.keyframes.last.timestampMs;
        final guardEnd = min(durationMs, lastDetectionMs + exitGuardMs);
        if (guardEnd > lastDetectionMs) {
          holds.add(
            VideoHold(
              startMs: lastDetectionMs,
              endMs: guardEnd,
              bounds: _exitGuardBounds(
                track.keyframes.length > 1
                    ? track.keyframes[track.keyframes.length - 2].bounds
                    : track.keyframes.last.bounds,
                track.keyframes.last.bounds,
                track.category,
              ),
            ),
          );
          endMs = max(endMs, guardEnd);
        }
      }
      result.add(
        VideoRedactionTrack(
          id: track.id,
          category: track.category,
          startMs: startMs,
          endMs: endMs,
          keyframes: List.unmodifiable(keyframes),
          selected: autoHideCategories.contains(track.category),
          style: switch (track.category) {
            RedactionCategory.face => faceStyle,
            RedactionCategory.person => peopleStyle,
            RedactionCategory.qrCode ||
            RedactionCategory.barcode ||
            RedactionCategory.numberPlate => RedactionStyle.pixelate,
            RedactionCategory.cardSecurityCode => RedactionStyle.blackout,
            RedactionCategory.otherText => track.category.defaultStyle,
            _ => sensitiveStyle,
          },
          source: track.source,
          holds: List.unmodifiable(holds),
          confidence: track.confidence,
        ),
      );
    }
    // Exporters composite tracks in list order. Bodies must be painted first
    // so the smaller face protection remains visible and editable above them.
    result.sort((a, b) => _layer(a.category).compareTo(_layer(b.category)));
    return result;
  }

  int _boundaryWindow(RedactionCategory category) => switch (category) {
    RedactionCategory.qrCode || RedactionCategory.barcode => 2600,
    RedactionCategory.numberPlate => 1800,
    RedactionCategory.face || RedactionCategory.person => 1600,
    RedactionCategory.address ||
    RedactionCategory.phone ||
    RedactionCategory.email ||
    RedactionCategory.card ||
    RedactionCategory.cardSecurityCode => 1400,
    _ => 0,
  };

  int _exitGuardDuration(RedactionCategory category) => switch (category) {
    RedactionCategory.face => 1400,
    RedactionCategory.person => 1200,
    RedactionCategory.qrCode || RedactionCategory.barcode => 1800,
    RedactionCategory.numberPlate => 1500,
    RedactionCategory.address ||
    RedactionCategory.phone ||
    RedactionCategory.email ||
    RedactionCategory.card ||
    RedactionCategory.cardSecurityCode => 1200,
    _ => 0,
  };

  Rect _exitGuardBounds(Rect previous, Rect last, RedactionCategory category) {
    final union = previous.expandToInclude(last);
    final movement = last.center - previous.center;
    final categoryPadding = switch (category) {
      RedactionCategory.face => .34,
      RedactionCategory.person => .18,
      RedactionCategory.qrCode || RedactionCategory.barcode => .28,
      RedactionCategory.numberPlate => .24,
      _ => .18,
    };
    final horizontal = max(union.width * categoryPadding, .025);
    final vertical = max(union.height * categoryPadding, .025);
    final leadX = movement.dx.abs() < .004 ? 0.0 : movement.dx * 1.4;
    final leadY = movement.dy.abs() < .004 ? 0.0 : movement.dy * 1.4;
    return Rect.fromLTRB(
      (union.left - horizontal + min(0, leadX)).clamp(0, 1),
      (union.top - vertical + min(0, leadY)).clamp(0, 1),
      (union.right + horizontal + max(0, leadX)).clamp(0, 1),
      (union.bottom + vertical + max(0, leadY)).clamp(0, 1),
    );
  }

  Rect _boundaryEnvelope(Rect a, Rect b) {
    final union = a.expandToInclude(b);
    final horizontal = max(union.width * .32, .035);
    final vertical = max(union.height * .32, .035);
    return Rect.fromLTRB(
      (union.left - horizontal).clamp(0, 1),
      (union.top - vertical).clamp(0, 1),
      (union.right + horizontal).clamp(0, 1),
      (union.bottom + vertical).clamp(0, 1),
    );
  }

  int _layer(RedactionCategory category) => switch (category) {
    RedactionCategory.person => 0,
    RedactionCategory.face => 2,
    _ => 1,
  };

  int _maximumGap(RedactionCategory category, Rect lastBounds) {
    if (category == RedactionCategory.face) {
      // A face clipped by the image edge frequently disappears from ML Kit for
      // a few checks. Keep that uncertain edge track alive until an accurate
      // verification pass can reacquire it. Interior faces retain the shorter
      // gap so blur does not float over the scene after someone leaves.
      return (sampleIntervalMs * (_isAtFrameEdge(lastBounds) ? 4.25 : 2.25))
          .round();
    }
    final stride = detectorStride[category] ?? 1;
    if (category == RedactionCategory.person) {
      // Person inference runs less often than face inference. Bridge one
      // missed person check so a change of pose cannot create an uncovered
      // hole between two otherwise matching body detections.
      return (sampleIntervalMs * stride * 2.45).round();
    }
    if (category == RedactionCategory.qrCode ||
        category == RedactionCategory.barcode) {
      // Codes can change size extremely quickly as the camera approaches.
      // Keep the same track through one missed scan instead of exposing the
      // code between two short fragments.
      return (sampleIntervalMs * stride * 2.45).round();
    }
    // Only join detections from adjacent checks for this category. A missed
    // check ends the track instead of drawing an effect through empty frames.
    return (sampleIntervalMs * stride * 1.28).round();
  }

  int _edgePadding(RedactionCategory category, Rect bounds) {
    final stride = detectorStride[category] ?? 1;
    return switch (category) {
      RedactionCategory.face =>
        _isAtFrameEdge(bounds)
            ? (sampleIntervalMs * 3.5).round().clamp(850, 1200)
            : (sampleIntervalMs * .65).round().clamp(160, 240),
      RedactionCategory.numberPlate ||
      RedactionCategory.qrCode ||
      RedactionCategory.barcode =>
        (sampleIntervalMs * stride * 1.35).round().clamp(700, 1800),
      RedactionCategory.person =>
        (sampleIntervalMs * stride * .95).round().clamp(650, 1400),
      _ => (sampleIntervalMs * stride * .4).round().clamp(240, 900),
    };
  }

  bool _isPlausibleMatch(RedactionCategory category, Rect a, Rect b) {
    final edgeFace =
        category == RedactionCategory.face &&
        (_isAtFrameEdge(a) || _isAtFrameEdge(b));
    final areaA = a.width * a.height;
    final areaB = b.width * b.height;
    final areaRatio = min(areaA, areaB) / max(.000001, max(areaA, areaB));
    final minimumAreaRatio = edgeFace
        ? .16
        : category == RedactionCategory.face
        ? .32
        : category == RedactionCategory.person
        ? .12
        : category == RedactionCategory.qrCode ||
              category == RedactionCategory.barcode
        ? .08
        : .25;
    if (areaRatio < minimumAreaRatio) {
      return false;
    }

    final iou = _intersectionOverUnion(a, b);
    final distance = (a.center - b.center).distance;
    final scale = max(max(a.width, a.height), max(b.width, b.height));
    if (scale <= 0) return false;
    final normalizedDistance = distance / scale;
    return switch (category) {
      RedactionCategory.face =>
        edgeFace
            ? iou >= .015 || normalizedDistance <= 1.65
            : iou >= .04 || normalizedDistance <= .9,
      RedactionCategory.person => iou >= .015 || normalizedDistance <= 1.35,
      RedactionCategory.qrCode ||
      RedactionCategory.barcode => iou >= .015 || normalizedDistance <= 1.25,
      RedactionCategory.numberPlate => iou >= .08 || normalizedDistance <= .75,
      _ => iou >= .04 || normalizedDistance <= .9,
    };
  }

  bool _isAtFrameEdge(Rect bounds) =>
      bounds.left <= .025 ||
      bounds.top <= .025 ||
      bounds.right >= .975 ||
      bounds.bottom >= .975;
}

double _matchScore(Rect a, Rect b) {
  final iou = _intersectionOverUnion(a, b);
  final distance = (a.center - b.center).distance;
  final scale = max(max(a.width, a.height), max(b.width, b.height));
  final proximity = scale <= 0
      ? 0.0
      : (1 - distance / (scale * 1.5)).clamp(0, 1);
  final areaRatio =
      min(a.width * a.height, b.width * b.height) /
      max(.000001, max(a.width * a.height, b.width * b.height));
  return iou * .55 + proximity * .3 + areaRatio * .15;
}

double _intersectionOverUnion(Rect a, Rect b) {
  final intersection = a.intersect(b);
  if (intersection.width <= 0 || intersection.height <= 0) return 0;
  final area = intersection.width * intersection.height;
  final union = a.width * a.height + b.width * b.height - area;
  return union <= 0 ? 0 : area / union;
}
