import 'package:flutter_test/flutter_test.dart';
import 'package:privacycam/domain/video_models.dart';

void main() {
  group('video access limits', () {
    test('free access includes clips up to exactly 15 seconds', () {
      expect(privacyCamVideoRequiresPro(0), isFalse);
      expect(
        privacyCamVideoRequiresPro(privacyCamVideoFreeMaxDurationMs),
        isFalse,
      );
    });

    test('clips longer than 15 seconds require Pro', () {
      expect(
        privacyCamVideoRequiresPro(privacyCamVideoFreeMaxDurationMs + 1),
        isTrue,
      );
      expect(privacyCamVideoRequiresPro(privacyCamVideoMaxDurationMs), isTrue);
    });

    test('the user-facing Pro requirement is clear', () {
      expect(
        const VideoProRequiredException().toString(),
        'Videos longer than 15 seconds require PrivacyCam Pro.',
      );
    });

    test('a long source trimmed to 15 seconds remains free', () {
      const session = VideoSession(
        sourcePath: '/tmp/example.mp4',
        durationMs: privacyCamVideoMaxDurationMs,
        width: 1920,
        height: 1080,
        hasAudio: true,
        editPlan: VideoEditPlan(trimStartMs: 30000, trimEndMs: 45000),
      );

      expect(privacyCamVideoSessionRequiresPro(session), isFalse);
    });

    test('a long output still requires Pro', () {
      const session = VideoSession(
        sourcePath: '/tmp/example.mp4',
        durationMs: privacyCamVideoMaxDurationMs,
        width: 1920,
        height: 1080,
        hasAudio: true,
      );

      expect(privacyCamVideoSessionRequiresPro(session), isTrue);
    });
  });
}
