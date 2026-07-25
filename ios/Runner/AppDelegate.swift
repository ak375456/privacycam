import AVFoundation
import CoreImage
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(
      forPlugin: "PrivacyCamVideoPlugin"
    ) {
      PrivacyCamVideoPlugin.register(with: registrar)
    }
  }
}

private final class PrivacyCamVideoPlugin: NSObject, FlutterPlugin {
  private let channel: FlutterMethodChannel
  private let queue = DispatchQueue(label: "app.privacycam.video", qos: .userInitiated)
  private var analysisCancelled = false
  private var exportSession: AVAssetExportSession?
  private var progressTimer: DispatchSourceTimer?

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "app.privacycam/video",
      binaryMessenger: registrar.messenger()
    )
    let instance = PrivacyCamVideoPlugin(channel: channel)
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  init(channel: FlutterMethodChannel) {
    self.channel = channel
    super.init()
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "inspectVideo":
      guard let path = argument(call, "path") as? String else {
        return fail(result, "missing_path", "The selected video path is missing.")
      }
      queue.async { [weak self] in self?.inspect(path: path, result: result) }
    case "extractFrames":
      guard
        let path = argument(call, "path") as? String,
        let timestamps = argument(call, "timestampsMs") as? [NSNumber]
      else {
        return fail(result, "invalid_frames", "The video frame request is invalid.")
      }
      let maximum = (argument(call, "maximumDimension") as? NSNumber)?.intValue ?? 1280
      analysisCancelled = false
      queue.async { [weak self] in
        self?.extractFrames(
          path: path,
          timestamps: timestamps.map(\.int64Value),
          maximumDimension: maximum,
          result: result
        )
      }
    case "cancelAnalysis":
      analysisCancelled = true
      result(nil)
    case "exportVideo":
      guard
        let arguments = call.arguments as? [String: Any],
        let path = arguments["path"] as? String,
        let outputPath = arguments["outputPath"] as? String,
        let rawTracks = arguments["tracks"] as? [[String: Any]],
        let rawEditRanges = arguments["editRanges"] as? [[String: Any]]
      else {
        return fail(result, "invalid_export", "The video export request is invalid.")
      }
      let tracks = rawTracks.compactMap(VideoMaskTrack.init)
      let editRanges = rawEditRanges.compactMap(VideoEditRange.init)
      let muteAudio = arguments["muteAudio"] as? Bool ?? false
      let blur = (arguments["blurStrength"] as? NSNumber)?.doubleValue ?? 18
      let pixel = (arguments["pixelSize"] as? NSNumber)?.doubleValue ?? 14
      queue.async { [weak self] in
        self?.export(
          path: path,
          outputPath: outputPath,
          tracks: tracks,
          editRanges: editRanges,
          muteAudio: muteAudio,
          blurStrength: blur,
          pixelSize: pixel,
          result: result
        )
      }
    case "cancelExport":
      exportSession?.cancelExport()
      stopProgress()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func inspect(path: String, result: @escaping FlutterResult) {
    var url = URL(fileURLWithPath: path)
    guard FileManager.default.fileExists(atPath: path) else {
      return fail(result, "missing_video", "The selected video is no longer available.")
    }
    var resourceValues = URLResourceValues()
    resourceValues.isExcludedFromBackup = true
    try? url.setResourceValues(resourceValues)
    let asset = AVURLAsset(url: url)
    guard let track = asset.tracks(withMediaType: .video).first else {
      return fail(result, "no_video", "This file has no readable video track.")
    }
    let size = track.naturalSize.applying(track.preferredTransform)
    let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    let frameRate = track.nominalFrameRate > 0 ? Double(track.nominalFrameRate) : 30.0
    succeed(result, [
      "durationMs": max(0, Int64(CMTimeGetSeconds(asset.duration) * 1000)),
      "width": Int(abs(size.width).rounded()),
      "height": Int(abs(size.height).rounded()),
      "hasAudio": !asset.tracks(withMediaType: .audio).isEmpty,
      "fileSize": fileSize,
      "frameRate": frameRate,
    ])
  }

  private func extractFrames(
    path: String,
    timestamps: [Int64],
    maximumDimension: Int,
    result: @escaping FlutterResult
  ) {
    let asset = AVURLAsset(url: URL(fileURLWithPath: path))
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.maximumSize = CGSize(width: maximumDimension, height: maximumDimension)
    generator.requestedTimeToleranceBefore = CMTime(value: 1, timescale: 20)
    generator.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 20)
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("privacycam_video_frames_\(UUID().uuidString)", isDirectory: true)
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      var frames: [[String: Any]] = []
      for timestamp in timestamps {
        if analysisCancelled {
          try? FileManager.default.removeItem(at: directory)
          return succeed(result, [])
        }
        var actual = CMTime.zero
        let requested = CMTime(value: timestamp, timescale: 1000)
        let image = try generator.copyCGImage(at: requested, actualTime: &actual)
        let data = UIImage(cgImage: image).jpegData(compressionQuality: 0.91)
        guard let data else { continue }
        let url = directory.appendingPathComponent("frame_\(timestamp).jpg")
        try data.write(to: url, options: .atomic)
        frames.append([
          "timestampMs": max(0, Int64(CMTimeGetSeconds(actual) * 1000)),
          "path": url.path,
          "width": image.width,
          "height": image.height,
        ])
      }
      succeed(result, frames)
    } catch {
      try? FileManager.default.removeItem(at: directory)
      fail(result, "frame_extraction_failed", "PrivacyCam could not read frames from this video.")
    }
  }

  private func export(
    path: String,
    outputPath: String,
    tracks: [VideoMaskTrack],
    editRanges: [VideoEditRange],
    muteAudio: Bool,
    blurStrength: Double,
    pixelSize: Double,
    result: @escaping FlutterResult
  ) {
    let sourceAsset = AVURLAsset(url: URL(fileURLWithPath: path))
    guard !tracks.isEmpty else {
      return fail(result, "no_redactions", "Select at least one privacy area before exporting.")
    }
    let asset: AVAsset
    do {
      asset = try editedAsset(from: sourceAsset, keeping: editRanges, muteAudio: muteAudio)
    } catch {
      return fail(result, "edit_failed", "PrivacyCam could not apply the selected video cuts.")
    }
    let composition = AVVideoComposition(asset: asset) { request in
      let timeMs = Int64(CMTimeGetSeconds(request.compositionTime) * 1000)
      var image = request.sourceImage
      let extent = image.extent
      for track in tracks where track.isVisible(at: timeMs) {
        let normalized = track.bounds(at: timeMs)
        let rect = CGRect(
          x: extent.minX + normalized.minX * extent.width,
          y: extent.maxY - normalized.maxY * extent.height,
          width: normalized.width * extent.width,
          height: normalized.height * extent.height
        ).intersection(extent)
        guard !rect.isNull, rect.width > 1, rect.height > 1 else { continue }
        let effect: CIImage
        switch track.style {
        case "blur":
          effect = image.clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [
              kCIInputRadiusKey: max(10, blurStrength * max(1, extent.width / 1080))
            ])
            .cropped(to: rect)
        case "pixelate":
          effect = image.applyingFilter("CIPixellate", parameters: [
            kCIInputScaleKey: max(10, pixelSize * max(1, extent.width / 1080)),
            kCIInputCenterKey: CIVector(x: rect.midX, y: rect.midY),
          ]).cropped(to: rect)
        default:
          effect = CIImage(color: .black).cropped(to: rect)
        }
        image = effect.composited(over: image)
      }
      request.finish(with: image.cropped(to: extent), context: nil)
    }

    let outputURL = URL(fileURLWithPath: outputPath)
    try? FileManager.default.removeItem(at: outputURL)
    let compatible = AVAssetExportSession.exportPresets(compatibleWith: asset)
    let preset = compatible.contains(AVAssetExportPreset1920x1080)
      ? AVAssetExportPreset1920x1080
      : AVAssetExportPresetHighestQuality
    guard let exporter = AVAssetExportSession(asset: asset, presetName: preset) else {
      return fail(result, "export_unavailable", "This device cannot export the selected video.")
    }
    exporter.outputURL = outputURL
    exporter.outputFileType = .mp4
    exporter.videoComposition = composition
    exporter.metadata = []
    exporter.metadataItemFilter = AVMetadataItemFilter.forSharing()
    exporter.shouldOptimizeForNetworkUse = true
    exportSession = exporter
    startProgress(exporter)
    exporter.exportAsynchronously { [weak self] in
      guard let self else { return }
      self.stopProgress()
      self.exportSession = nil
      switch exporter.status {
      case .completed:
        if self.verifyMetadataRemoved(url: outputURL) {
          return self.succeed(result, ["path": outputPath, "metadataRemoved": true])
        }
        self.removeResidualMetadata(
          from: outputURL,
          outputPath: outputPath,
          result: result
        )
      case .cancelled:
        try? FileManager.default.removeItem(at: outputURL)
        self.fail(result, "export_cancelled", "Video export was cancelled.")
      default:
        try? FileManager.default.removeItem(at: outputURL)
        self.fail(
          result,
          "export_failed",
          exporter.error?.localizedDescription ?? "The privacy-safe video could not be created."
        )
      }
    }
  }

  private func editedAsset(
    from source: AVAsset,
    keeping ranges: [VideoEditRange],
    muteAudio: Bool
  ) throws -> AVAsset {
    guard !ranges.isEmpty else { throw VideoEditError.noKeptVideo }
    let fullDurationMs = Int64(CMTimeGetSeconds(source.duration) * 1000)
    if !muteAudio,
      ranges.count == 1,
      ranges[0].startMs <= 0,
      ranges[0].endMs >= fullDurationMs - 2
    {
      return source
    }
    guard let sourceVideo = source.tracks(withMediaType: .video).first else {
      throw VideoEditError.noKeptVideo
    }
    let composition = AVMutableComposition()
    guard let destinationVideo = composition.addMutableTrack(
      withMediaType: .video,
      preferredTrackID: kCMPersistentTrackID_Invalid
    ) else { throw VideoEditError.noKeptVideo }
    destinationVideo.preferredTransform = sourceVideo.preferredTransform
    var cursor = CMTime.zero
    for range in ranges where range.endMs > range.startMs {
      let sourceRange = CMTimeRange(
        start: CMTime(value: range.startMs, timescale: 1000),
        end: CMTime(value: range.endMs, timescale: 1000)
      )
      try destinationVideo.insertTimeRange(sourceRange, of: sourceVideo, at: cursor)
      cursor = CMTimeAdd(cursor, sourceRange.duration)
    }
    guard cursor > .zero else { throw VideoEditError.noKeptVideo }
    if !muteAudio {
      for sourceAudio in source.tracks(withMediaType: .audio) {
        guard let destinationAudio = composition.addMutableTrack(
          withMediaType: .audio,
          preferredTrackID: kCMPersistentTrackID_Invalid
        ) else { continue }
        var audioCursor = CMTime.zero
        for range in ranges where range.endMs > range.startMs {
          let sourceRange = CMTimeRange(
            start: CMTime(value: range.startMs, timescale: 1000),
            end: CMTime(value: range.endMs, timescale: 1000)
          )
          try destinationAudio.insertTimeRange(sourceRange, of: sourceAudio, at: audioCursor)
          audioCursor = CMTimeAdd(audioCursor, sourceRange.duration)
        }
      }
    }
    return composition
  }

  /// Camera recordings can contain separate QuickTime metadata tracks in
  /// addition to ordinary asset metadata. If AVAssetExportSession preserves
  /// one, rebuild the file from video/audio tracks only without re-encoding.
  private func removeResidualMetadata(
    from outputURL: URL,
    outputPath: String,
    result: @escaping FlutterResult
  ) {
    let renderedURL = outputURL.deletingPathExtension()
      .appendingPathExtension("rendered.mp4")
    try? FileManager.default.removeItem(at: renderedURL)
    do {
      try FileManager.default.moveItem(at: outputURL, to: renderedURL)
      let source = AVURLAsset(url: renderedURL)
      let composition = AVMutableComposition()
      guard
        let sourceVideo = source.tracks(withMediaType: .video).first,
        let video = composition.addMutableTrack(
          withMediaType: .video,
          preferredTrackID: kCMPersistentTrackID_Invalid
        )
      else {
        throw MetadataCleanupError.missingVideo
      }
      try video.insertTimeRange(sourceVideo.timeRange, of: sourceVideo, at: .zero)
      video.preferredTransform = sourceVideo.preferredTransform

      for sourceAudio in source.tracks(withMediaType: .audio) {
        guard let audio = composition.addMutableTrack(
          withMediaType: .audio,
          preferredTrackID: kCMPersistentTrackID_Invalid
        ) else { continue }
        try audio.insertTimeRange(sourceAudio.timeRange, of: sourceAudio, at: .zero)
      }

      guard let cleaner = AVAssetExportSession(
        asset: composition,
        presetName: AVAssetExportPresetPassthrough
      ) else {
        throw MetadataCleanupError.unavailable
      }
      cleaner.outputURL = outputURL
      cleaner.outputFileType = .mp4
      cleaner.metadata = []
      cleaner.metadataItemFilter = AVMetadataItemFilter.forSharing()
      cleaner.shouldOptimizeForNetworkUse = true
      exportSession = cleaner
      cleaner.exportAsynchronously { [weak self] in
        guard let self else { return }
        self.exportSession = nil
        try? FileManager.default.removeItem(at: renderedURL)
        guard cleaner.status == .completed,
              self.verifyMetadataRemoved(url: outputURL)
        else {
          try? FileManager.default.removeItem(at: outputURL)
          return self.fail(
            result,
            "metadata_verification_failed",
            "Metadata removal could not be verified, so export was stopped."
          )
        }
        self.succeed(result, ["path": outputPath, "metadataRemoved": true])
      }
    } catch {
      try? FileManager.default.removeItem(at: renderedURL)
      try? FileManager.default.removeItem(at: outputURL)
      fail(
        result,
        "metadata_verification_failed",
        "Metadata removal could not be verified, so export was stopped."
      )
    }
  }

  private func verifyMetadataRemoved(url: URL) -> Bool {
    let asset = AVURLAsset(url: url)
    let containers: [AVAssetTrack?] = [nil] + asset.tracks.map(Optional.some)
    for track in containers {
      let formats = track?.availableMetadataFormats ?? asset.availableMetadataFormats
      for format in formats {
        let items = track?.metadata(forFormat: format) ?? asset.metadata(forFormat: format)
        for item in items {
          guard let value = item.value else { continue }
          let valueText = String(describing: value)
            .trimmingCharacters(in: .whitespacesAndNewlines)
          guard !valueText.isEmpty else { continue }
          let rawKey = item.key.map { String(describing: $0) } ?? ""
          let key = "\(item.commonKey?.rawValue ?? "") \(rawKey) \(item.identifier?.rawValue ?? "")"
            .lowercased()
          // AVFoundation may add a fresh container creation timestamp while it
          // writes the new MP4. That value describes this sanitized export, not
          // the source recording. Reject privacy-bearing source metadata only.
          if key.contains("location") ||
            key.contains("iso6709") ||
            key.contains("author") ||
            key.contains("artist") ||
            key.contains("album") ||
            key.contains("title") ||
            key.contains("description") ||
            key.contains("copyright") ||
            key.contains("make") ||
            key.contains("model")
          {
            return false
          }
        }
      }
    }
    return FileManager.default.fileExists(atPath: url.path)
  }

  private func startProgress(_ exporter: AVAssetExportSession) {
    stopProgress()
    let timer = DispatchSource.makeTimerSource(queue: queue)
    timer.schedule(deadline: .now(), repeating: .milliseconds(180))
    timer.setEventHandler { [weak self, weak exporter] in
      guard let self, let exporter else { return }
      DispatchQueue.main.async {
        self.channel.invokeMethod("exportProgress", arguments: Double(exporter.progress))
      }
    }
    progressTimer = timer
    timer.resume()
  }

  private func stopProgress() {
    progressTimer?.cancel()
    progressTimer = nil
  }

  private func argument(_ call: FlutterMethodCall, _ key: String) -> Any? {
    (call.arguments as? [String: Any])?[key]
  }

  private func succeed(_ result: @escaping FlutterResult, _ value: Any?) {
    DispatchQueue.main.async { result(value) }
  }

  private func fail(_ result: @escaping FlutterResult, _ code: String, _ message: String) {
    DispatchQueue.main.async {
      result(FlutterError(code: code, message: message, details: nil))
    }
  }
}

private enum MetadataCleanupError: Error {
  case missingVideo
  case unavailable
}

private enum VideoEditError: Error {
  case noKeptVideo
}

private struct VideoEditRange {
  let startMs: Int64
  let endMs: Int64

  init?(_ raw: [String: Any]) {
    guard
      let start = raw["startMs"] as? NSNumber,
      let end = raw["endMs"] as? NSNumber,
      end.int64Value > start.int64Value
    else { return nil }
    startMs = start.int64Value
    endMs = end.int64Value
  }
}

private struct VideoMaskKeyframe {
  let timestampMs: Int64
  let bounds: CGRect

  init?(_ raw: [String: Any]) {
    guard
      let time = raw["timestampMs"] as? NSNumber,
      let values = raw["bounds"] as? [NSNumber],
      values.count == 4
    else { return nil }
    timestampMs = time.int64Value
    bounds = CGRect(
      x: values[0].doubleValue,
      y: values[1].doubleValue,
      width: values[2].doubleValue - values[0].doubleValue,
      height: values[3].doubleValue - values[1].doubleValue
    )
  }
}

private struct VideoMaskHold {
  let startMs: Int64
  let endMs: Int64
  let bounds: CGRect

  init?(_ raw: [String: Any]) {
    guard
      let start = raw["startMs"] as? NSNumber,
      let end = raw["endMs"] as? NSNumber,
      let values = raw["bounds"] as? [NSNumber],
      values.count == 4,
      end.int64Value >= start.int64Value
    else { return nil }
    startMs = start.int64Value
    endMs = end.int64Value
    bounds = CGRect(
      x: values[0].doubleValue,
      y: values[1].doubleValue,
      width: values[2].doubleValue - values[0].doubleValue,
      height: values[3].doubleValue - values[1].doubleValue
    )
  }
}

private struct VideoMaskTrack {
  let startMs: Int64
  let endMs: Int64
  let style: String
  let keyframes: [VideoMaskKeyframe]
  let holds: [VideoMaskHold]

  init?(_ raw: [String: Any]) {
    guard
      let start = raw["startMs"] as? NSNumber,
      let end = raw["endMs"] as? NSNumber,
      let style = raw["style"] as? String,
      let rawFrames = raw["keyframes"] as? [[String: Any]]
    else { return nil }
    let frames = rawFrames.compactMap(VideoMaskKeyframe.init).sorted {
      $0.timestampMs < $1.timestampMs
    }
    guard !frames.isEmpty else { return nil }
    startMs = start.int64Value
    endMs = end.int64Value
    self.style = style
    keyframes = frames
    holds = (raw["holds"] as? [[String: Any]] ?? []).compactMap(VideoMaskHold.init)
  }

  func isVisible(at timeMs: Int64) -> Bool {
    timeMs >= startMs && timeMs <= endMs
  }

  func bounds(at timeMs: Int64) -> CGRect {
    if let hold = holds.reversed().first(where: { timeMs >= $0.startMs && timeMs <= $0.endMs }) {
      return hold.bounds
    }
    guard timeMs > keyframes[0].timestampMs else { return keyframes[0].bounds }
    guard timeMs < keyframes[keyframes.count - 1].timestampMs else {
      return keyframes[keyframes.count - 1].bounds
    }
    for index in 1..<keyframes.count {
      let next = keyframes[index]
      guard timeMs <= next.timestampMs else { continue }
      let previous = keyframes[index - 1]
      let duration = max(1, next.timestampMs - previous.timestampMs)
      let fraction = CGFloat(timeMs - previous.timestampMs) / CGFloat(duration)
      return CGRect(
        x: previous.bounds.minX + (next.bounds.minX - previous.bounds.minX) * fraction,
        y: previous.bounds.minY + (next.bounds.minY - previous.bounds.minY) * fraction,
        width: previous.bounds.width + (next.bounds.width - previous.bounds.width) * fraction,
        height: previous.bounds.height + (next.bounds.height - previous.bounds.height) * fraction
      )
    }
    return keyframes[keyframes.count - 1].bounds
  }
}
