import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:privacycam/domain/models.dart';
import 'package:privacycam/presentation/widgets/sticker_redaction.dart';
import 'package:privacycam/services/export_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          pathProvider,
          (call) async => call.method == 'getTemporaryDirectory'
              ? Directory.systemTemp.path
              : null,
        );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null);
  });

  test('sticker styles survive session persistence', () {
    for (final style in [RedactionStyle.emoji, RedactionStyle.flowers]) {
      final item = RedactionItem(
        id: style.name,
        category: RedactionCategory.manual,
        bounds: const Rect.fromLTWH(10, 20, 100, 40),
        selected: true,
        style: style,
        source: RedactionSource.manual,
      );

      final restored = RedactionItemPersistence.fromJson(item.toJson());

      expect(restored.style, style);
      expect(restored.bounds, item.bounds);
    }
  });

  testWidgets('emoji and flower sticker previews are available', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Row(
          children: [
            SizedBox(
              width: 120,
              height: 60,
              child: StickerRedaction(style: RedactionStyle.emoji),
            ),
            SizedBox(
              width: 120,
              height: 60,
              child: StickerRedaction(style: RedactionStyle.flowers),
            ),
          ],
        ),
      ),
    );

    expect(find.byType(StickerRedaction), findsNWidgets(2));
    expect(
      find.descendant(
        of: find.byType(StickerRedaction),
        matching: find.byType(CustomPaint),
      ),
      findsNWidgets(2),
    );
  });

  test('sticker covers are flattened into exported images', () async {
    final source = File(
      '${Directory.systemTemp.path}/privacycam_flower_source_${DateTime.now().microsecondsSinceEpoch}.png',
    );
    final original = img.Image(width: 100, height: 100);
    img.fill(original, color: img.ColorRgba8(255, 255, 255, 255));
    await source.writeAsBytes(img.encodePng(original));
    addTearDown(() async {
      if (await source.exists()) await source.delete();
    });
    for (final style in [RedactionStyle.emoji, RedactionStyle.flowers]) {
      final session = ImageSession(
        sourcePath: source.path,
        width: 100,
        height: 100,
        items: [
          RedactionItem(
            id: style.name,
            category: RedactionCategory.manual,
            bounds: const Rect.fromLTWH(20, 20, 60, 40),
            selected: true,
            style: style,
            source: RedactionSource.manual,
          ),
        ],
      );
      final rendered = await ExportService().preview(
        session,
        const ExportSettings(),
      );
      addTearDown(() async {
        final preview = File(rendered.previewPath!);
        if (await preview.exists()) await preview.delete();
      });
      final exported = img.decodeImage(
        await File(rendered.previewPath!).readAsBytes(),
      )!;
      final covered = exported.getPixel(50, 40);
      final untouched = exported.getPixel(5, 5);

      expect(
        [covered.r, covered.g, covered.b],
        isNot(equals([untouched.r, untouched.g, untouched.b])),
        reason: style.name,
      );
      expect(covered.a, 255);
    }
  });
}
