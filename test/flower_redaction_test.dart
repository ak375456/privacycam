import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:privacycam/domain/models.dart';
import 'package:privacycam/presentation/widgets/flower_redaction.dart';
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

  test('flower style survives session persistence', () {
    const item = RedactionItem(
      id: 'flowers',
      category: RedactionCategory.manual,
      bounds: Rect.fromLTWH(10, 20, 100, 40),
      selected: true,
      style: RedactionStyle.flowers,
      source: RedactionSource.manual,
    );

    final restored = RedactionItemPersistence.fromJson(item.toJson());

    expect(restored.style, RedactionStyle.flowers);
    expect(restored.bounds, item.bounds);
  });

  testWidgets('flower cover is fully opaque', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: SizedBox(width: 120, height: 60, child: FlowerRedaction()),
        ),
      ),
    );
    final decoration =
        tester
                .widget<DecoratedBox>(
                  find.descendant(
                    of: find.byType(FlowerRedaction),
                    matching: find.byType(DecoratedBox),
                  ),
                )
                .decoration
            as BoxDecoration;

    expect(decoration.color, isNotNull);
    expect(decoration.color!.a, 1);
  });

  test('flower cover is flattened into an exported image', () async {
    final source = File(
      '${Directory.systemTemp.path}/privacycam_flower_source_${DateTime.now().microsecondsSinceEpoch}.png',
    );
    final original = img.Image(width: 100, height: 100);
    img.fill(original, color: img.ColorRgba8(255, 255, 255, 255));
    await source.writeAsBytes(img.encodePng(original));
    addTearDown(() async {
      if (await source.exists()) await source.delete();
    });
    final session = ImageSession(
      sourcePath: source.path,
      width: 100,
      height: 100,
      items: const [
        RedactionItem(
          id: 'flowers',
          category: RedactionCategory.manual,
          bounds: Rect.fromLTWH(20, 20, 60, 40),
          selected: true,
          style: RedactionStyle.flowers,
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

    expect(covered.r, isNot(equals(untouched.r)));
    expect(covered.a, 255);
  });
}
