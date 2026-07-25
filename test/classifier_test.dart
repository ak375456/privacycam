import 'package:flutter_test/flutter_test.dart';
import 'package:privacycam/domain/models.dart';
import 'package:privacycam/services/classifier.dart';

void main() {
  final classifier = SensitiveTextClassifier();

  group('SensitiveTextClassifier', () {
    test('classifies email, international phone, URL and other text', () {
      expect(
        classifier.classify('support@company.co.uk'),
        RedactionCategory.email,
      );
      expect(classifier.classify('+92 300 1234567'), RedactionCategory.phone);
      expect(
        classifier.classify('visit https://example.com/private'),
        RedactionCategory.url,
      );
      expect(
        classifier.classify('ordinary heading'),
        RedactionCategory.otherText,
      );
    });

    test('only accepts payment cards that pass Luhn validation', () {
      expect(
        classifier.classify('4242 4242 4242 4242'),
        RedactionCategory.card,
      );
      expect(
        classifier.classify('4242 4242 4242 4241'),
        isNot(RedactionCategory.card),
      );
      expect(classifier.passesLuhn('4111111111111111'), isTrue);
      expect(classifier.passesLuhn('4111111111111112'), isFalse);
    });

    test('does not classify short numbers as phones', () {
      expect(classifier.classify('Order 12345'), RedactionCategory.otherText);
    });

    test('classifies common card security-code labels', () {
      for (final value in [
        'CVV 123',
        'CVC2: 456',
        'CID 1234',
        'CSC # 987',
        'Security code 321',
        'Card security code: 123',
      ]) {
        expect(
          classifier.classify(value),
          RedactionCategory.cardSecurityCode,
          reason: value,
        );
      }
      expect(classifier.isShortSecurityCodeValue('123'), isTrue);
      expect(classifier.isShortSecurityCodeValue('1234'), isTrue);
      expect(classifier.classify('123'), RedactionCategory.otherText);
    });
  });

  test('QR detections default to strong pixelation', () {
    expect(RedactionCategory.qrCode.defaultStyle, RedactionStyle.pixelate);
  });
}
