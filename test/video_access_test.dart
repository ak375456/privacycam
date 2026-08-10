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
  });
}
