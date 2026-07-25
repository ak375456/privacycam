import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:privacycam/services/export_service.dart';

void main() {
  test('metadata verification accepts a freshly re-encoded image', () async {
    final directory = await Directory.systemTemp.createTemp('privacycam_test_');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/safe.jpg');
    final image = img.Image(width: 8, height: 8);
    await file.writeAsBytes(img.encodeJpg(image));

    expect(await ExportService().verifyMetadataRemoved(file.path), isTrue);
  });

  test('metadata stripping removes inherited EXIF before encoding', () async {
    final directory = await Directory.systemTemp.createTemp('privacycam_exif_');
    addTearDown(() => directory.delete(recursive: true));
    final source = img.Image(width: 8, height: 8);
    source.exif.imageIfd[0x010F] = img.IfdValueAscii('Private Camera');
    expect(source.exif.isEmpty, isFalse);

    final clean = ExportService().withoutMetadata(source);
    final file = File('${directory.path}/stripped.jpg');
    await file.writeAsBytes(img.encodeJpg(clean));

    expect(clean.exif.isEmpty, isTrue);
    expect(await ExportService().verifyMetadataRemoved(file.path), isTrue);
  });
}
