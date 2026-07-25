import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:saver_gallery/saver_gallery.dart';

import '../domain/video_models.dart';

class VideoServiceException implements Exception {
  const VideoServiceException(this.message);
  final String message;
  @override
  String toString() => message;
}

class VideoService {
  VideoService({ImagePicker? picker}) : _picker = picker ?? ImagePicker() {
    _channel.setMethodCallHandler(_handleNativeEvent);
  }

  static const _channel = MethodChannel('app.privacycam/video');
  final ImagePicker _picker;
  final _progress = StreamController<double>.broadcast();

  Stream<double> get exportProgress => _progress.stream;

  Future<void> _handleNativeEvent(MethodCall call) async {
    if (call.method == 'exportProgress') {
      _progress.add(((call.arguments as num?)?.toDouble() ?? 0).clamp(0, 1));
    }
  }

  Future<String?> pickVideo(ImageSource source) async {
    final picked = await _picker.pickVideo(
      source: source,
      maxDuration: const Duration(milliseconds: privacyCamVideoMaxDurationMs),
    );
    if (picked == null) return null;
    return _copyIntoWorkDirectory(picked.path);
  }

  Future<String?> recoverLostVideo() async {
    // image_picker only implements process-death recovery on Android. Calling
    // retrieveLostData on iOS reaches an intentionally unimplemented method.
    if (!Platform.isAndroid) return null;
    final response = await _picker.retrieveLostData();
    if (response.isEmpty || response.files == null || response.files!.isEmpty) {
      return null;
    }
    final video = response.files!.first;
    return _copyIntoWorkDirectory(video.path);
  }

  Future<String> _copyIntoWorkDirectory(String sourcePath) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw const VideoServiceException(
        'The selected video is no longer available.',
      );
    }
    final size = await source.length();
    if (size > privacyCamVideoMaxBytes) {
      throw const VideoServiceException(
        'This video is larger than 600 MB. Choose a shorter or smaller video.',
      );
    }
    final directory = await _workingDirectory();
    final extension = sourcePath.toLowerCase().endsWith('.mov') ? 'mov' : 'mp4';
    final destination = File(
      '${directory.path}/privacycam_video_${DateTime.now().microsecondsSinceEpoch}.$extension',
    );
    await source.copy(destination.path);
    return destination.path;
  }

  Future<VideoInfo> inspect(String path) async {
    try {
      final value = await _channel.invokeMapMethod<Object?, Object?>(
        'inspectVideo',
        {'path': path},
      );
      if (value == null) {
        throw const VideoServiceException('The video could not be read.');
      }
      final info = VideoInfo.fromMap(value);
      if (info.durationMs <= 0 || info.width <= 0 || info.height <= 0) {
        throw const VideoServiceException(
          'This video has no readable picture track.',
        );
      }
      if (info.durationMs > privacyCamVideoMaxDurationMs + 500) {
        throw const VideoServiceException(
          'Video privacy review currently supports clips up to 60 seconds.',
        );
      }
      return info;
    } on PlatformException catch (error) {
      throw VideoServiceException(
        error.message ?? 'This video format is not supported on this device.',
      );
    }
  }

  Future<List<VideoFrame>> extractFrames(
    String path,
    List<int> timestampsMs, {
    int maximumDimension = 800,
  }) async {
    try {
      final values = await _channel.invokeListMethod<Object?>('extractFrames', {
        'path': path,
        'timestampsMs': timestampsMs,
        'maximumDimension': maximumDimension.clamp(120, 1920),
      });
      return [
        for (final value in values ?? const [])
          VideoFrame.fromMap(Map<Object?, Object?>.from(value! as Map)),
      ];
    } on PlatformException catch (error) {
      throw VideoServiceException(
        error.message ?? 'PrivacyCam could not prepare this video for review.',
      );
    }
  }

  Future<String> export(
    VideoSession session, {
    required double blurStrength,
    required double pixelSize,
  }) async {
    final directory = await _workingDirectory();
    final outputPath =
        '${directory.path}/PrivacyCam_video_${DateTime.now().millisecondsSinceEpoch}.mp4';
    try {
      final result = await _channel
          .invokeMapMethod<Object?, Object?>('exportVideo', {
            'path': session.sourcePath,
            'outputPath': outputPath,
            'tracks': session.exportTracks(),
            'editRanges': session.exportEditRanges(),
            'muteAudio': session.resolvedEditPlan.audioMuted,
            'blurStrength': blurStrength,
            'pixelSize': pixelSize,
            'maximumDimension': 1920,
          });
      final path = result?['path'] as String?;
      final verified = result?['metadataRemoved'] as bool? ?? false;
      if (path == null || !verified || !await File(path).exists()) {
        await deleteWorkingFile(path ?? outputPath);
        throw const VideoServiceException(
          'Metadata removal could not be verified, so export was stopped.',
        );
      }
      _progress.add(1);
      return path;
    } on PlatformException catch (error) {
      await deleteWorkingFile(outputPath);
      throw VideoServiceException(
        error.message ?? 'The privacy-safe video could not be created.',
      );
    }
  }

  Future<void> cancelAnalysis() => _channel.invokeMethod('cancelAnalysis');
  Future<void> cancelExport() => _channel.invokeMethod('cancelExport');

  Future<void> saveToGallery(String path) async {
    final result = await SaverGallery.saveFile(
      filePath: path,
      fileName: 'PrivacyCam_${DateTime.now().millisecondsSinceEpoch}.mp4',
      androidRelativePath: 'Movies/PrivacyCam',
      skipIfExists: false,
    );
    if (!result.isSuccess) {
      throw VideoServiceException(
        result.errorMessage ?? 'The video could not be saved.',
      );
    }
  }

  Future<void> deleteFrames(Iterable<VideoFrame> frames) async {
    final directories = <String>{};
    for (final frame in frames) {
      final file = File(frame.path);
      directories.add(file.parent.path);
      if (await file.exists()) await file.delete();
    }
    for (final path in directories) {
      final directory = Directory(path);
      if (await directory.exists()) {
        try {
          await directory.delete();
        } on FileSystemException {
          // Another frame may still be closing; the OS cache will reclaim it.
        }
      }
    }
  }

  Future<void> deleteWorkingFile(String? path) async {
    if (path == null) return;
    final file = File(path);
    final work = await _workingDirectory();
    if (file.path.startsWith(work.path) && await file.exists()) {
      await file.delete();
    }
  }

  Future<Directory> _workingDirectory() async {
    final support = await getApplicationSupportDirectory();
    final directory = Directory('${support.path}/privacycam_video_work');
    if (!await directory.exists()) await directory.create(recursive: true);
    return directory;
  }

  void dispose() => _progress.close();
}
