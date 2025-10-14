import AVFoundation
import CoreMedia
import Flutter
import Foundation

private let proxyChannelName = "coalition/video_proxy"
private let proxyProgressChannelName = "coalition/video_proxy/progress"

private enum PreviewTier {
  case fast
  case quality
  case fallback
}

private struct PreviewProfile {
  let size: CGSize
  let frameRate: Int
  let keyframeInterval: Int
  let videoBitrate: Int
  let audioBitrate: Int
  let audioSampleRate: Int
}

private func parsePreviewTier(_ value: String?, isFallback: Bool) -> PreviewTier {
  if isFallback { return .fallback }
  guard let value else { return .fast }
  return value.uppercased() == "QUALITY" ? .quality : .fast
}

private func profile(for tier: PreviewTier) -> PreviewProfile {
  switch tier {
  case .fast:
    return PreviewProfile(
      size: CGSize(width: 720, height: 1280),
      frameRate: 24,
      keyframeInterval: 24,
      videoBitrate: 1_200_000,
      audioBitrate: 96_000,
      audioSampleRate: 44_100
    )
  case .quality:
    return PreviewProfile(
      size: CGSize(width: 720, height: 1280),
      frameRate: 24,
      keyframeInterval: 24,
      videoBitrate: 1_500_000,
      audioBitrate: 128_000,
      audioSampleRate: 48_000
    )
  case .fallback:
    return PreviewProfile(
      size: CGSize(width: 720, height: 1280),
      frameRate: 24,
      keyframeInterval: 24,
      videoBitrate: 1_000_000,
      audioBitrate: 96_000,
      audioSampleRate: 44_100
    )
  }
}

private func shouldPassthroughAudio(_ track: AVAssetTrack?) -> Bool {
  guard let track else { return false }
  let bitrate = track.estimatedDataRate
  guard bitrate <= 128_000 else { return false }
  guard let formatDesc = track.formatDescriptions.first as? CMAudioFormatDescription else { return false }
  guard let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc)?.pointee else { return false }
  let isAac = asbd.mFormatID == kAudioFormatMPEG4AAC
  let sampleRate = Int(asbd.mSampleRate)
  let validSampleRate = sampleRate == 44_100 || sampleRate == 48_000
  return isAac && validSampleRate
}

final class VideoProxyChannel: NSObject, FlutterStreamHandler {
  private var eventSink: FlutterEventSink?
  private let syncQueue = DispatchQueue(label: "com.example.coalition.videoProxy")
  private var activeJobs: [String: ProxyJob] = [:]

  init(messenger: FlutterBinaryMessenger) {
    super.init()
    let methodChannel = FlutterMethodChannel(name: proxyChannelName, binaryMessenger: messenger)
    methodChannel.setMethodCallHandler(handle)
    let progressChannel = FlutterEventChannel(name: proxyProgressChannelName, binaryMessenger: messenger)
    progressChannel.setStreamHandler(self)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "createProxy":
      createProxy(call.arguments, fallback: false, result: result)
    case "createProxyFallback720p":
      createProxy(call.arguments, fallback: true, result: result)
    case "cancelProxy":
      cancelProxy(call.arguments, result: result)
    case "probeSource":
      probeSource(call.arguments, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func createProxy(_ arguments: Any?, fallback: Bool, result: @escaping FlutterResult) {
    guard
      let args = arguments as? [String: Any],
      let jobId = args["jobId"] as? String,
      let sourcePath = args["sourcePath"] as? String,
      let outputDirectory = args["outputDirectory"] as? String
    else {
      result(["ok": false, "code": "invalid_args", "message": "Missing arguments", "recoverable": true])
      return
    }

    let previewQuality = args["previewQuality"] as? String
    let forceFallback = (args["forceFallback"] as? NSNumber)?.boolValue ?? false
    let tier = parsePreviewTier(previewQuality, isFallback: fallback || forceFallback)
    let profile = profile(for: tier)
    let frameRateHint = profile.frameRate
    let enableLogging = (args["enableLogging"] as? NSNumber)?.boolValue ?? true

    let outputDirectoryURL = URL(fileURLWithPath: outputDirectory, isDirectory: true)
    do {
      try FileManager.default.createDirectory(at: outputDirectoryURL, withIntermediateDirectories: true, attributes: nil)
    } catch {
      result(["ok": false, "code": "io_error", "message": "Unable to create proxy directory", "recoverable": true])
      return
    }

    let outputURL = outputDirectoryURL
      .appendingPathComponent("proxy_\(Int(Date().timeIntervalSince1970 * 1000))_\(UUID().uuidString)")
      .appendingPathExtension("mp4")

    let job = ProxyJob(
      jobId: jobId,
      sourcePath: sourcePath,
      targetSize: profile.size,
      frameRateHint: frameRateHint,
      fallback: fallback || forceFallback,
      outputURL: outputURL,
      enableLogging: enableLogging,
      completion: result,
      tier: tier
    )

    syncQueue.async {
      if self.activeJobs[jobId] != nil {
        result(["ok": false, "code": "job_exists", "message": "Proxy job already running", "recoverable": true])
        return
      }
      self.activeJobs[jobId] = job
      self.startExport(job)
    }
  }

  private func startExport(_ job: ProxyJob) {
    let sourceURL = URL(fileURLWithPath: job.sourcePath)
    let asset = AVURLAsset(url: sourceURL)
    let keys = ["tracks", "duration"]
    do {
      try asset.loadValuesSynchronously(forKeys: keys)
    } catch {
      complete(jobId: job.jobId, payload: ["ok": false, "code": "load_failed", "message": error.localizedDescription, "recoverable": true])
      return
    }

    for key in keys {
      var error: NSError?
      let status = asset.statusOfValue(forKey: key, error: &error)
      if status != .loaded {
        complete(jobId: job.jobId, payload: ["ok": false, "code": "load_failed", "message": error?.localizedDescription ?? "Unable to load media", "recoverable": true])
        return
      }
    }

    guard let videoTrack = asset.tracks(withMediaType: .video).first else {
      complete(jobId: job.jobId, payload: ["ok": false, "code": "no_video", "message": "Video track missing", "recoverable": true])
      return
    }

    let audioTrack = asset.tracks(withMediaType: .audio).first
    job.audioPassthrough = shouldPassthroughAudio(audioTrack)

    let composition = AVMutableComposition()
    guard let compositionVideo = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
      complete(jobId: job.jobId, payload: ["ok": false, "code": "composition_failed", "message": "Unable to create video track", "recoverable": true])
      return
    }

    do {
      try compositionVideo.insertTimeRange(CMTimeRange(start: .zero, duration: asset.duration), of: videoTrack, at: .zero)
      compositionVideo.preferredTransform = .identity
      if let audioTrack,
         let compositionAudio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
        try compositionAudio.insertTimeRange(CMTimeRange(start: .zero, duration: asset.duration), of: audioTrack, at: .zero)
      }
    } catch {
      complete(jobId: job.jobId, payload: ["ok": false, "code": "composition_failed", "message": error.localizedDescription, "recoverable": true])
      return
    }

    let videoComposition = AVMutableVideoComposition()
    videoComposition.renderSize = job.targetSize
    let timescale = max(1, job.frameRateHint)
    videoComposition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(timescale))

    let instruction = AVMutableVideoCompositionInstruction()
    instruction.timeRange = CMTimeRange(start: .zero, duration: asset.duration)

    let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionVideo)
    let preferredTransform = videoTrack.preferredTransform
    let naturalSize = videoTrack.naturalSize
    let rawTransformedRect = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
    let boundingRect = CGRect(
      x: min(rawTransformedRect.minX, rawTransformedRect.maxX),
      y: min(rawTransformedRect.minY, rawTransformedRect.maxY),
      width: abs(rawTransformedRect.width),
      height: abs(rawTransformedRect.height)
    )
    let rotatedSize = boundingRect.size
    let scale = min(job.targetSize.width / max(rotatedSize.width, 1), job.targetSize.height / max(rotatedSize.height, 1))
    let scaledSize = CGSize(width: rotatedSize.width * scale, height: rotatedSize.height * scale)
    let translateX = (job.targetSize.width - scaledSize.width) / 2 - boundingRect.minX * scale
    let translateY = (job.targetSize.height - scaledSize.height) / 2 - boundingRect.minY * scale

    var finalTransform = preferredTransform
    finalTransform = finalTransform.concatenating(CGAffineTransform(translationX: -boundingRect.minX, y: -boundingRect.minY))
    finalTransform = finalTransform.concatenating(CGAffineTransform(scaleX: scale, y: scale))
    finalTransform = finalTransform.concatenating(CGAffineTransform(translationX: translateX, y: translateY))
    layerInstruction.setTransform(finalTransform, at: .zero)
    instruction.layerInstructions = [layerInstruction]
    videoComposition.instructions = [instruction]

    guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
      complete(jobId: job.jobId, payload: ["ok": false, "code": "export_init_failed", "message": "Unable to create export session", "recoverable": true])
      return
    }

    exportSession.videoComposition = videoComposition
    exportSession.outputURL = job.outputURL
    exportSession.outputFileType = .mp4
    exportSession.shouldOptimizeForNetworkUse = true

    if FileManager.default.fileExists(atPath: job.outputURL.path) {
      try? FileManager.default.removeItem(at: job.outputURL)
    }

    let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
    timer.schedule(deadline: .now(), repeating: 0.2)
    timer.setEventHandler { [weak self] in
      guard let self = self else { return }
      self.eventSink?([
        "jobId": job.jobId,
        "type": "progress",
        "progress": exportSession.progress,
        "fallbackTriggered": job.fallback,
      ])
    }
    timer.resume()

    job.exportSession = exportSession
    job.progressTimer = timer
    job.startDate = Date()
    if job.enableLogging {
      print(
        "[VideoProxyChannel] Starting job=\(job.jobId) source=\(job.sourcePath) " +
          "target=\(Int(job.targetSize.width))x\(Int(job.targetSize.height)) tier=\(job.tier) " +
          "fallback=\(job.fallback) audioPassthrough=\(job.audioPassthrough)"
      )
    }

    exportSession.exportAsynchronously { [weak self] in
      guard let self else { return }
      timer.cancel()
      switch exportSession.status {
      case .completed:
        let elapsed = Int(Date().timeIntervalSince(job.startDate ?? Date()) * 1000)
        let metadata = self.inspectProxy(at: job.outputURL, frameRateHint: job.frameRateHint, fallbackSize: job.targetSize)
        if job.enableLogging {
          print(
            "[VideoProxyChannel] Completed job=\(job.jobId) elapsed=\(elapsed)ms " +
              "size=\(metadata.width)x\(metadata.height) tier=\(job.tier) " +
              "fallback=\(job.fallback) audioPassthrough=\(job.audioPassthrough)"
          )
        }
        let payload: [String: Any] = [
          "ok": true,
          "proxyPath": job.outputURL.path,
          "width": metadata.width,
          "height": metadata.height,
          "durationMs": metadata.durationMs,
          "frameRate": metadata.frameRate,
          "rotationBaked": true,
          "usedFallback720p": job.fallback,
          "transcodeDurationMs": elapsed,
        ]
        self.complete(jobId: job.jobId, payload: payload)
      case .cancelled:
        try? FileManager.default.removeItem(at: job.outputURL)
        self.complete(jobId: job.jobId, payload: ["ok": false, "code": "cancelled", "message": "Proxy generation canceled", "recoverable": true])
      case .failed:
        try? FileManager.default.removeItem(at: job.outputURL)
        let message = exportSession.error?.localizedDescription ?? "Proxy generation failed"
        self.complete(jobId: job.jobId, payload: ["ok": false, "code": "transcode_failed", "message": message, "recoverable": true])
      default:
        try? FileManager.default.removeItem(at: job.outputURL)
        self.complete(jobId: job.jobId, payload: ["ok": false, "code": "transcode_failed", "message": "Export did not complete", "recoverable": true])
      }
    }
  }

  private func cancelProxy(_ arguments: Any?, result: @escaping FlutterResult) {
    guard
      let args = arguments as? [String: Any],
      let jobId = args["jobId"] as? String
    else {
      result(["ok": false, "code": "invalid_args", "message": "Missing jobId", "recoverable": true])
      return
    }

    syncQueue.async {
      if let job = self.activeJobs[jobId] {
        job.progressTimer?.cancel()
        job.exportSession?.cancelExport()
        try? FileManager.default.removeItem(at: job.outputURL)
      }
      DispatchQueue.main.async {
        result(["ok": true])
      }
    }
  }

  private func probeSource(_ arguments: Any?, result: @escaping FlutterResult) {
    guard
      let args = arguments as? [String: Any],
      let sourcePath = args["sourcePath"] as? String
    else {
      result(["ok": false, "code": "invalid_args", "message": "Missing sourcePath", "recoverable": true])
      return
    }

    let asset = AVURLAsset(url: URL(fileURLWithPath: sourcePath))
    let keys = ["tracks", "duration"]
    DispatchQueue.global(qos: .userInitiated).async {
      do {
        try asset.loadValuesSynchronously(forKeys: keys)
        var response: [String: Any] = ["ok": true]
        if let videoTrack = asset.tracks(withMediaType: .video).first {
          response["width"] = Int(videoTrack.naturalSize.width)
          response["height"] = Int(videoTrack.naturalSize.height)
          response["rotation"] = Int(videoTrack.preferredTransform.rotationDegrees)
          response["codec"] = videoTrack.formatDescriptions.first.flatMap { ($0 as? CMFormatDescription).flatMap { CMFormatDescriptionGetMediaSubType($0).toString() } }
        }
        response["durationMs"] = Int(CMTimeGetSeconds(asset.duration) * 1000)
        DispatchQueue.main.async { result(response) }
      } catch {
        DispatchQueue.main.async {
          result(["ok": false, "code": "probe_failed", "message": error.localizedDescription, "recoverable": true])
        }
      }
    }
  }

  private func inspectProxy(at url: URL, frameRateHint: Int, fallbackSize: CGSize) -> ProxyMetadata {
    let asset = AVURLAsset(url: url)
    let videoTrack = asset.tracks(withMediaType: .video).first
    let width = Int(videoTrack?.naturalSize.width ?? fallbackSize.width)
    let height = Int(videoTrack?.naturalSize.height ?? fallbackSize.height)
    let durationMs = Int(CMTimeGetSeconds(asset.duration) * 1000)
    let frameRate = videoTrack?.nominalFrameRate ?? Float(frameRateHint)
    return ProxyMetadata(width: width, height: height, durationMs: durationMs, frameRate: Double(frameRate))
  }

  private func complete(jobId: String, payload: [String: Any]) {
    syncQueue.async {
      guard let job = self.activeJobs.removeValue(forKey: jobId) else { return }
      job.progressTimer?.cancel()
      DispatchQueue.main.async {
        job.completion(payload)
      }
    }
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  private final class ProxyJob {
    let jobId: String
    let sourcePath: String
    let targetSize: CGSize
    let frameRateHint: Int
    let fallback: Bool
    let outputURL: URL
    let enableLogging: Bool
    let completion: FlutterResult
    let tier: PreviewTier
    var exportSession: AVAssetExportSession?
    var progressTimer: DispatchSourceTimer?
    var startDate: Date?
    var audioPassthrough: Bool = false

    init(jobId: String,
         sourcePath: String,
         targetSize: CGSize,
         frameRateHint: Int,
         fallback: Bool,
         outputURL: URL,
         enableLogging: Bool,
         completion: @escaping FlutterResult,
         tier: PreviewTier) {
      self.jobId = jobId
      self.sourcePath = sourcePath
      self.targetSize = targetSize
      self.frameRateHint = frameRateHint
      self.fallback = fallback
      self.outputURL = outputURL
      self.enableLogging = enableLogging
      self.completion = completion
      self.tier = tier
    }
  }

  private struct ProxyMetadata {
    let width: Int
    let height: Int
    let durationMs: Int
    let frameRate: Double
  }
}

private extension CGAffineTransform {
  var rotationDegrees: CGFloat {
    let radians = atan2(b, a)
    let degrees = radians * 180 / .pi
    let normalized = degrees.truncatingRemainder(dividingBy: 360)
    return (normalized >= 0 ? normalized : normalized + 360).rounded()
  }
}

private extension FourCharCode {
  func toString() -> String {
    var value = self.bigEndian
    let data = Data(bytes: &value, count: 4)
    return String(data: data, encoding: .ascii) ?? ""
  }
}
