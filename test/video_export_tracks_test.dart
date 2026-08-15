import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:privacycam/domain/models.dart';
import 'package:privacycam/domain/video_models.dart';

VideoRedactionTrack _track({
  required String id,
  required RedactionCategory category,
  required bool selected,
  required RedactionStyle style,
  required Rect bounds,
}) => VideoRedactionTrack(
  id: id,
  category: category,
  startMs: 0,
  endMs: 2000,
  keyframes: [
    VideoKeyframe(timestampMs: 0, bounds: bounds),
    VideoKeyframe(timestampMs: 2000, bounds: bounds),
  ],
  selected: selected,
  style: style,
  source: RedactionSource.automatic,
);

void main() {
  test('selected full-body and face tracks are both sent to video export', () {
    const bodyBounds = Rect.fromLTRB(.10, .08, .75, .96);
    const faceBounds = Rect.fromLTRB(.30, .10, .48, .30);
    final session = VideoSession(
      sourcePath: '/tmp/source.mp4',
      durationMs: 2000,
      width: 1080,
      height: 1920,
      hasAudio: true,
      tracks: [
        _track(
          id: 'body',
          category: RedactionCategory.person,
          selected: true,
          style: RedactionStyle.blackout,
          bounds: bodyBounds,
        ),
        _track(
          id: 'face',
          category: RedactionCategory.face,
          selected: true,
          style: RedactionStyle.blur,
          bounds: faceBounds,
        ),
      ],
    );

    final exported = session.exportTracks();

    expect(exported, hasLength(2));
    expect(
      exported.map((track) => track['category']),
      containsAll(<String>['person', 'face']),
    );
    final body = exported.singleWhere(
      (track) => track['category'] == RedactionCategory.person.name,
    );
    expect(body['selected'], isTrue);
    expect(body['style'], RedactionStyle.blackout.name);
    expect(((body['keyframes'] as List).first as Map)['bounds'], <double>[
      .10,
      .08,
      .75,
      .96,
    ]);
  });

  test('inactive full-body detections remain excluded from export', () {
    final session = VideoSession(
      sourcePath: '/tmp/source.mp4',
      durationMs: 2000,
      width: 1080,
      height: 1920,
      hasAudio: false,
      tracks: [
        _track(
          id: 'body',
          category: RedactionCategory.person,
          selected: false,
          style: RedactionStyle.blackout,
          bounds: const Rect.fromLTRB(.10, .08, .75, .96),
        ),
        _track(
          id: 'face',
          category: RedactionCategory.face,
          selected: true,
          style: RedactionStyle.blur,
          bounds: const Rect.fromLTRB(.30, .10, .48, .30),
        ),
      ],
    );

    final exported = session.exportTracks();

    expect(exported, hasLength(1));
    expect(exported.single['category'], RedactionCategory.face.name);
  });
}
