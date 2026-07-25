import 'dart:io';
import 'dart:isolate';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:saver_gallery/saver_gallery.dart';

import '../domain/models.dart';

class ImageIoException implements Exception {
  const ImageIoException(this.message);
  final String message;
  @override
  String toString() => message;
}

class ImageIoService {
  ImageIoService({ImagePicker? picker}) : _picker = picker ?? ImagePicker();
  final ImagePicker _picker;
  static const maxPixels = 60000000;

  Future<String?> pickGalleryPath() async {
    final file = await _picker.pickImage(
      source: ImageSource.gallery,
      requestFullMetadata: false,
    );
    return file?.path;
  }

  Future<List<String>> pickGalleryPaths({int limit = 10}) async {
    final files = await _picker.pickMultiImage(
      limit: limit,
      requestFullMetadata: false,
    );
    return [for (final file in files) file.path];
  }

  Future<ImageSession> normalize(String sourcePath) async {
    final file = File(sourcePath);
    if (!await file.exists()) {
      throw const ImageIoException(
        'The selected image is no longer available.',
      );
    }
    final lowerPath = sourcePath.toLowerCase();
    final directory = await _workingDirectory();
    var rasterPath = sourcePath;
    String? convertedPath;
    if (lowerPath.endsWith('.heic') || lowerPath.endsWith('.heif')) {
      final conversionTarget =
          '${directory.path}/privacycam_heic_${DateTime.now().microsecondsSinceEpoch}.jpg';
      final converted = await FlutterImageCompress.compressAndGetFile(
        sourcePath,
        conversionTarget,
        minWidth: 16384,
        minHeight: 16384,
        quality: 97,
        autoCorrectionAngle: true,
        keepExif: false,
        format: CompressFormat.jpeg,
      );
      if (converted == null) {
        throw const ImageIoException(
          'This HEIC image could not be decoded on this device. Android 9 or newer is required.',
        );
      }
      rasterPath = converted.path;
      convertedPath = converted.path;
    }
    final isPng = lowerPath.endsWith('.png');
    final path =
        '${directory.path}/privacycam_${DateTime.now().microsecondsSinceEpoch}.${isPng ? 'png' : 'jpg'}';
    late final ({int width, int height}) dimensions;
    try {
      dimensions = await Isolate.run(
        () => _normalizeRaster(rasterPath, path, isPng, maxPixels),
      );
    } on ImageIoException {
      rethrow;
    } catch (_) {
      throw const ImageIoException(
        'This image is corrupted or uses an unsupported format.',
      );
    } finally {
      if (convertedPath != null) {
        final converted = File(convertedPath);
        if (await converted.exists()) await converted.delete();
      }
    }
    return ImageSession(
      sourcePath: path,
      width: dimensions.width,
      height: dimensions.height,
    );
  }

  Future<void> saveToGallery(String path) async {
    final bytes = await File(path).readAsBytes();
    final result = await SaverGallery.saveImage(
      bytes,
      fileName: 'PrivacyCam_${DateTime.now().millisecondsSinceEpoch}',
      skipIfExists: false,
    );
    if (!result.isSuccess) {
      throw ImageIoException(
        result.errorMessage ?? 'The image could not be saved.',
      );
    }
  }

  Future<void> deleteIfTemporary(String? path) async {
    if (path == null) return;
    final temp = await getTemporaryDirectory();
    final file = File(path);
    if (file.path.startsWith(temp.path) && await file.exists()) {
      await file.delete();
    }
  }

  Future<void> deleteWorkingFile(String? path) async {
    if (path == null) return;
    final file = File(path);
    final temp = await getTemporaryDirectory();
    final work = await _workingDirectory();
    if ((file.path.startsWith(temp.path) || file.path.startsWith(work.path)) &&
        await file.exists()) {
      await file.delete();
    }
  }

  Future<Directory> _workingDirectory() async {
    final support = await getApplicationSupportDirectory();
    final directory = Directory('${support.path}/privacycam_work');
    if (!await directory.exists()) await directory.create(recursive: true);
    return directory;
  }
}

({int width, int height}) _normalizeRaster(
  String sourcePath,
  String outputPath,
  bool png,
  int maximumPixels,
) {
  final decoded = img.decodeImage(File(sourcePath).readAsBytesSync());
  if (decoded == null) {
    throw const ImageIoException(
      'This image is corrupted or uses an unsupported format.',
    );
  }
  final oriented = img.bakeOrientation(decoded);
  if (oriented.width * oriented.height > maximumPixels) {
    throw const ImageIoException(
      'This image is too large for safe processing on this device. Try a smaller copy.',
    );
  }
  oriented.exif.clear();
  oriented.iccProfile = null;
  oriented.textData = null;
  oriented.extraChannels = null;
  final cleanBytes = png
      ? img.encodePng(oriented)
      : img.encodeJpg(oriented, quality: 96);
  File(outputPath).writeAsBytesSync(cleanBytes, flush: true);
  return (width: oriented.width, height: oriented.height);
}
