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
      size: CGSize(width: 540, height: 960),
      frameRate: 24,
      keyframeInterval: 24,
      videoBitrate: 1_000_000,
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
      size: CGSize(width: 360, height: 640),
      frameRate: 24,
      keyframeInterval: 24,
      videoBitrate: 800_000,
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
  private var activeSegmentWriters: [String: () -> Void] = [:]
  private var activeSessions: [String: ProxySession] = [:]

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
    case "ensureSegment":
      ensureSegment(call.arguments, result: result)
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
  let segmentedPreview = (args["segmentedPreview"] as? NSNumber)?.boolValue ?? false
  let segmentDurationMs = (args["segmentDurationMs"] as? NSNumber)?.int64Value ?? 10000

    let outputDirectoryURL = URL(fileURLWithPath: outputDirectory, isDirectory: true)
    do {
      try FileManager.default.createDirectory(at: outputDirectoryURL, withIntermediateDirectories: true, attributes: nil)
    } catch {
      result(["ok": false, "code": "io_error", "message": "Unable to create proxy directory", "recoverable": true])
      return
    }

    // If segmented preview requested, use the outputDirectory as the job directory. Otherwise create a single proxy file URL.
    let outputURL: URL = {
      if segmentedPreview {
        let jobDir = outputDirectoryURL.appendingPathComponent(jobId, isDirectory: true)
        try? FileManager.default.createDirectory(at: jobDir, withIntermediateDirectories: true, attributes: nil)
        return jobDir
      } else {
        return outputDirectoryURL
          .appendingPathComponent("proxy_\(Int(Date().timeIntervalSince1970 * 1000))_\(UUID().uuidString)")
          .appendingPathExtension("mp4")
      }
    }()

    let targetSize = segmentedPreview ? CGSize(width: 360, height: 640) : profile.size
    let effectiveTier = segmentedPreview ? PreviewTier.fallback : tier

    let job = ProxyJob(
      jobId: jobId,
      sourcePath: sourcePath,
      targetSize: targetSize,
      frameRateHint: frameRateHint,
      fallback: fallback || forceFallback,
      outputURL: outputURL,
      enableLogging: enableLogging,
      completion: result,
      tier: effectiveTier
    )

    syncQueue.async {
      if self.activeJobs[jobId] != nil {
        result(["ok": false, "code": "job_exists", "message": "Proxy job already running", "recoverable": true])
        return
      }
      self.activeJobs[jobId] = job
      if segmentedPreview {
        self.startProxySession(job, segmentDurationMs: segmentDurationMs)
      } else {
        self.startExport(job)
      }
    }
  }

  private func startProxySession(_ job: ProxyJob, segmentDurationMs: Int64) {
    let sourceURL = URL(fileURLWithPath: job.sourcePath)
    let asset = AVURLAsset(url: sourceURL)
    let session = ProxySession(
      job: job,
      asset: asset,
      segmentDurationMs: segmentDurationMs,
      eventEmitter: { [weak self] event in
        guard let self else { return }
        DispatchQueue.main.async {
          self.eventSink?(event)
        }
      },
      completion: { [weak self] payload in
        guard let self else { return }
        self.complete(jobId: job.jobId, payload: payload)
      },
      fallback: { [weak self] error in
        guard let self else { return }
        if job.enableLogging {
          print("[VideoProxyChannel] Session fallback for job=\(job.jobId) reason=\(error.localizedDescription)")
        }
        self.syncQueue.async {
          self.activeSessions.removeValue(forKey: job.jobId)
          self.activeSegmentWriters.removeValue(forKey: job.jobId)
          self.startSegmentedExport(job, segmentDurationMs: segmentDurationMs)
        }
      },
      teardown: { [weak self] in
        self?.syncQueue.async {
          self?.activeSessions.removeValue(forKey: job.jobId)
          self?.activeSegmentWriters.removeValue(forKey: job.jobId)
        }
      }
    )

    activeSessions[job.jobId] = session
    activeSegmentWriters[job.jobId] = { [weak session] in
      session?.cancelActiveTasks()
    }

    session.start()
  }

  private func startSegmentedExport(_ job: ProxyJob, segmentDurationMs: Int64) {
    let sourceURL = URL(fileURLWithPath: job.sourcePath)
    let asset = AVURLAsset(url: sourceURL)
    let durationSec = CMTimeGetSeconds(asset.duration)
    let durationMs = Int64(durationSec * 1000)
    let totalSegments = Int((durationMs + segmentDurationMs - 1) / segmentDurationMs)

    DispatchQueue.global(qos: .userInitiated).async {
      var segmentIndex = 0
      var startMs: Int64 = 0
      while startMs < durationMs {
        let endMs = min(startMs + segmentDurationMs, durationMs)
        let jobDir = job.outputURL // in segmented mode this is a directory URL
        let segmentURL = jobDir.appendingPathComponent(String(format: "segment_%03d.mp4", segmentIndex))

        // Use AVAssetReader/Writer to produce a segment with explicit encoder settings so we can set bitrate, fps and keyframe interval.
        do {
          if FileManager.default.fileExists(atPath: segmentURL.path) {
            try FileManager.default.removeItem(at: segmentURL)
          }

          let reader = try AVAssetReader(asset: asset)
          let writer = try AVAssetWriter(outputURL: segmentURL, fileType: .mp4)

          // Video output settings - decompress frames
          guard let videoTrack = asset.tracks(withMediaType: .video).first else {
            self.complete(jobId: job.jobId, payload: ["ok": false, "code": "no_video", "message": "Video track missing", "recoverable": true])
            return
          }

          let videoReaderOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: nil)
          videoReaderOutput.alwaysCopiesSampleData = false
          reader.add(videoReaderOutput)

          // Video writer input settings - H.264
          let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(job.targetSize.width),
            AVVideoHeightKey: Int(job.targetSize.height),
            AVVideoCompressionPropertiesKey: [
              AVVideoAverageBitRateKey: job.tier == .fallback ? 800_000 : 1_200_000,
              AVVideoMaxKeyFrameIntervalKey: 24, // approximate 1s at 24fps; set to 24 for GOP ~= 1s
              AVVideoProfileLevelKey: AVVideoProfileLevelH264BaselineAutoLevel
            ]
          ]

          let videoWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
          videoWriterInput.expectsMediaDataInRealTime = false
          writer.add(videoWriterInput)

          var audioReaderOutput: AVAssetReaderTrackOutput? = nil
          var audioWriterInput: AVAssetWriterInput? = nil
          if let audioTrack = asset.tracks(withMediaType: .audio).first {
            audioReaderOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: nil)
            audioReaderOutput?.alwaysCopiesSampleData = false
            reader.add(audioReaderOutput!)

            let audioSettings: [String: Any] = [
              AVFormatIDKey: kAudioFormatMPEG4AAC,
              AVNumberOfChannelsKey: 2,
              AVSampleRateKey: 44_100,
              AVEncoderBitRateKey: 96_000
            ]
            audioWriterInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            audioWriterInput?.expectsMediaDataInRealTime = false
            writer.add(audioWriterInput!)
          }

          let startTime = CMTimeMake(value: startMs, timescale: 1000)
          let duration = CMTimeMake(value: endMs - startMs, timescale: 1000)
          let timeRange = CMTimeRange(start: startTime, duration: duration)

          reader.timeRange = timeRange

          writer.startWriting()
          writer.startSession(atSourceTime: .zero)

          let videoQueue = DispatchQueue(label: "videoQueue")
          let audioQueue = DispatchQueue(label: "audioQueue")

          writer.requestMediaDataWhenReady(on: videoQueue) {
            while videoWriterInput.isReadyForMoreMediaData {
              if let sample = videoReaderOutput.copyNextSampleBuffer() {
                videoWriterInput.append(sample)
              } else {
                videoWriterInput.markAsFinished()
                break
              }
            }
          }

          if let audioReaderOutput = audioReaderOutput, let audioWriterInput = audioWriterInput {
            writer.requestMediaDataWhenReady(on: audioQueue) {
              while audioWriterInput.isReadyForMoreMediaData {
                if let sample = audioReaderOutput.copyNextSampleBuffer() {
                  audioWriterInput.append(sample)
                } else {
                  audioWriterInput.markAsFinished()
                  break
                }
              }
            }
          }

          // Start the reader
          if !reader.startReading() {
            throw NSError(domain: "VideoProxy", code: -1, userInfo: [NSLocalizedDescriptionKey: "Reader failed to start"]) 
          }

          // Poll writer status until done
          var finished = false
          while !finished {
            if writer.status == .completed {
              finished = true
            } else if writer.status == .failed || writer.status == .cancelled || reader.status == .failed {
              throw writer.error ?? reader.error ?? NSError(domain: "VideoProxy", code: -1, userInfo: [NSLocalizedDescriptionKey: "Export failed"])
            }
            Thread.sleep(forTimeInterval: 0.05)
          }

          writer.finishWriting {
            if writer.status == .completed {
              let metadata = self.inspectProxy(at: segmentURL, frameRateHint: job.frameRateHint, fallbackSize: job.targetSize)
              self.eventSink?([
                "jobId": job.jobId,
                "type": "segment_ready",
                "segmentIndex": segmentIndex,
                "path": segmentURL.path,
                "durationMs": metadata.durationMs,
                "width": metadata.width,
                "height": metadata.height,
                "hasAudio": audioWriterInput != nil,
                "totalSegments": totalSegments,
                "totalDurationMs": durationMs,
              ])
            } else {
              try? FileManager.default.removeItem(at: segmentURL)
              let message = writer.error?.localizedDescription ?? "Segment write failed"
              self.complete(jobId: job.jobId, payload: ["ok": false, "code": "transcode_failed", "message": message, "recoverable": true])
              return
            }
          }
        } catch {
          try? FileManager.default.removeItem(at: segmentURL)
          self.complete(jobId: job.jobId, payload: ["ok": false, "code": "transcode_failed", "message": error.localizedDescription, "recoverable": true])
          return
        }

        segmentIndex += 1
        startMs = endMs
        // loop continues for next segment
        

        // Loop will proceed once writer.finishWriting has completed (we wait on a semaphore there).
      }

      // After all segments, emit completed
      let elapsed = Int(Date().timeIntervalSince1970 * 1000)
      self.eventSink?([
        "ok": true,
        "jobId": job.jobId,
        "type": "completed",
        "outputDirectory": job.outputURL.path,
        "totalSegments": totalSegments,
        "totalDurationMs": durationMs,
        "transcodeDurationMs": elapsed,
      ])
      DispatchQueue.main.async {
        job.completion(["ok": true, "jobId": job.jobId])
      }
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

  private func ensureSegment(_ arguments: Any?, result: @escaping FlutterResult) {
    guard
      let args = arguments as? [String: Any],
      let jobId = args["jobId"] as? String,
      let startMsNumber = args["startMs"] as? NSNumber,
      let endMsNumber = args["endMs"] as? NSNumber
    else {
      result(["ok": false, "code": "invalid_args", "message": "Missing arguments", "recoverable": true])
      return
    }

    let qualityLabel = (args["quality"] as? String) ?? ProxySession.SegmentQuality.preview.rawValue
    let startMs = startMsNumber.int64Value
    let endMs = endMsNumber.int64Value

    syncQueue.async {
      guard let session = self.activeSessions[jobId] else {
        DispatchQueue.main.async {
          result(FlutterError(code: "no_session", message: "Proxy session not ready", details: nil))
        }
        return
      }

      session.ensureSegment(startMs: startMs, endMs: endMs, qualityLabel: qualityLabel) { outcome in
        DispatchQueue.main.async {
          switch outcome {
          case .success:
            result(["ok": true])
          case let .failure(error):
            let nsError = error as NSError
            result(FlutterError(code: nsError.domain, message: nsError.localizedDescription, details: nsError.code))
          }
        }
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
      if let job = self.activeJobs.removeValue(forKey: jobId) {
        job.progressTimer?.cancel()
        job.exportSession?.cancelExport()
        try? FileManager.default.removeItem(at: job.outputURL)
      }
      if let session = self.activeSessions.removeValue(forKey: jobId) {
        session.cancel()
      }
      // Cancel any active per-segment writer/reader
      if let cancelClosure = self.activeSegmentWriters[jobId] {
        cancelClosure()
        self.activeSegmentWriters.removeValue(forKey: jobId)
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

  private final class ProxySession {
    enum SegmentQuality: String, CaseIterable {
      case preview = "PREVIEW"
      case proxy = "PROXY"
      case mezzanine = "MEZZANINE"

      var rank: Int {
        switch self {
        case .preview: return 0
        case .proxy: return 1
        case .mezzanine: return 2
        }
      }

      var exportPreset: String {
        switch self {
        case .preview:
          return AVAssetExportPresetLowQuality
        case .proxy:
          return AVAssetExportPreset960x540
        case .mezzanine:
          return AVAssetExportPreset1280x720
        }
      }

      static func from(label: String) -> SegmentQuality {
        let normalized = label.uppercased()
        return SegmentQuality(rawValue: normalized) ?? .preview
      }
    }

    private enum EmitReason {
      case ensure
      case upgrade
    }

    private struct SegmentKey: Hashable {
      let startMs: Int64
      let endMs: Int64
      let quality: SegmentQuality

      var durationMs: Int {
        return max(1, Int(endMs - startMs))
      }

      func segmentIndex(segmentDurationMs: Int64) -> Int {
        guard segmentDurationMs > 0 else { return 0 }
        return Int(startMs / segmentDurationMs)
      }

      func timeRange(maxDurationMs: Int) -> CMTimeRange {
        let upperBound = Int64(max(0, maxDurationMs))
        let clampedStart = max(0, min(startMs, upperBound))
        let limitedEnd = min(endMs, upperBound)
        var clampedEnd = max(clampedStart + 1, limitedEnd)
        clampedEnd = min(clampedEnd, upperBound)
        let duration = max(1, clampedEnd - clampedStart)
        return CMTimeRange(
          start: CMTime(value: clampedStart, timescale: 1000),
          duration: CMTime(value: duration, timescale: 1000)
        )
      }
    }

    private struct CacheEntry {
      let key: SegmentKey
      let url: URL
      let fileSize: Int64
    }

    private let job: ProxyJob
    private let asset: AVURLAsset
    private let segmentDurationMs: Int64
    private let eventEmitter: ([String: Any]) -> Void
    private let completion: ([String: Any]) -> Void
    private let fallback: (Error) -> Void
    private let teardown: () -> Void
    private let queue: DispatchQueue
    private let queueKey = DispatchSpecificKey<Void>()
    private let cacheDirectory: URL

    private var cancelled = false
    private var didTeardown = false
    private var cache: [SegmentKey: CacheEntry] = [:]
    private var lru: [SegmentKey] = []
    private var totalBytes: Int64 = 0
    private var pendingExports: [SegmentKey: AVAssetExportSession] = [:]
    private var pendingUpgradeKeys: Set<SegmentKey> = []
    private var previewURL: URL?
    private var preparedVideoComposition: AVMutableVideoComposition?
    private var videoWidth: Int = 0
    private var videoHeight: Int = 0
    private var frameRate: Double = 0
    private var durationMs: Int = 0
    private var totalSegments: Int = 0
    private var hasAudio: Bool = false
    private var startDate = Date()

    private let maxCacheEntries = 12
    private let maxCacheBytes: Int64 = 200 * 1024 * 1024

    init(job: ProxyJob,
         asset: AVURLAsset,
         segmentDurationMs: Int64,
         eventEmitter: @escaping ([String: Any]) -> Void,
         completion: @escaping ([String: Any]) -> Void,
         fallback: @escaping (Error) -> Void,
         teardown: @escaping () -> Void) {
      self.job = job
      self.asset = asset
      self.segmentDurationMs = segmentDurationMs
      self.eventEmitter = eventEmitter
      self.completion = completion
      self.fallback = fallback
      self.teardown = teardown
      self.cacheDirectory = job.outputURL
      self.queue = DispatchQueue(
        label: "com.example.coalition.videoProxy.session.\(job.jobId)",
        qos: .userInitiated
      )
      self.queue.setSpecific(key: queueKey, value: ())
    }

    func start() {
      startDate = Date()
      let keys = ["tracks", "duration"]
      asset.loadValuesAsynchronously(forKeys: keys) { [weak self] in
        guard let self else { return }
        self.asyncOnQueue {
          guard !self.cancelled else { return }
          do {
            try self.validateAsset(keys: keys)
            try self.prepareSession()
          } catch {
            self.handleFatalError(error)
          }
        }
      }
    }

    func ensureSegment(startMs: Int64,
                       endMs: Int64,
                       qualityLabel: String,
                       completion: @escaping (Result<Void, Error>) -> Void) {
      asyncOnQueue {
        guard !self.cancelled else {
          completion(.failure(self.makeError(code: -10, message: "Session cancelled")))
          return
        }

        let quality = SegmentQuality.from(label: qualityLabel)
        let assetDurationMs = Int64(self.durationMs)
        var clampedStart = max(Int64(0), min(startMs, assetDurationMs))
        var clampedEnd = max(clampedStart + 1, min(endMs, assetDurationMs))
        if clampedStart >= assetDurationMs {
          clampedStart = max(0, assetDurationMs - self.segmentDurationMs)
          clampedEnd = assetDurationMs
        } else if clampedEnd <= clampedStart {
          clampedEnd = min(clampedStart + self.segmentDurationMs, assetDurationMs)
        }

        let key = SegmentKey(startMs: clampedStart, endMs: clampedEnd, quality: quality)

        if let entry = self.cacheEntry(for: key) {
          self.emitSegmentEvent(entry: entry, reason: .ensure)
          completion(.success(()))
          self.scheduleUpgrades(for: key, producedQuality: quality)
          return
        }

        self.produceSegment(key: key, quality: quality, reason: .ensure) { result in
          switch result {
          case let .success(entry):
            self.emitSegmentEvent(entry: entry, reason: .ensure)
            completion(.success(()))
            self.scheduleUpgrades(for: key, producedQuality: quality)
          case let .failure(error):
            completion(.failure(error))
          }
        }
      }
    }

    func cancelActiveTasks() {
      asyncOnQueue {
        for export in self.pendingExports.values {
          export.cancelExport()
        }
        self.pendingExports.removeAll()
        self.pendingUpgradeKeys.removeAll()
      }
    }

    func cancel() {
      asyncOnQueue {
        guard !self.cancelled else { return }
        self.cancelled = true
        for export in self.pendingExports.values {
          export.cancelExport()
        }
        self.pendingExports.removeAll()
        self.pendingUpgradeKeys.removeAll()
        self.cleanupFiles()
        self.performTeardownIfNeeded()
      }
    }

    private func validateAsset(keys: [String]) throws {
      for key in keys {
        var error: NSError?
        let status = asset.statusOfValue(forKey: key, error: &error)
        if status != .loaded {
          throw error ?? makeError(code: -2, message: "Unable to load asset key \(key)")
        }
      }
    }

    private func prepareSession() throws {
      guard let videoTrack = asset.tracks(withMediaType: .video).first else {
        throw makeError(code: -3, message: "Video track missing")
      }

      durationMs = Int((CMTimeGetSeconds(asset.duration) * 1000.0).rounded())
      if durationMs <= 0 {
        durationMs = Int(segmentDurationMs)
      }

      frameRate = Double(videoTrack.nominalFrameRate)
      if frameRate <= 0, job.frameRateHint > 0 {
        frameRate = Double(job.frameRateHint)
      }

      videoWidth = Int(max(1, job.targetSize.width))
      videoHeight = Int(max(1, job.targetSize.height))
      hasAudio = !asset.tracks(withMediaType: .audio).isEmpty
      if segmentDurationMs > 0 {
        totalSegments = Int((Int64(durationMs) + segmentDurationMs - 1) / segmentDurationMs)
      }

      preparedVideoComposition = makeVideoComposition(for: videoTrack)

      var metadata: [String: Any] = [
        "durationMs": durationMs,
        "width": videoWidth,
        "height": videoHeight,
        "frameRate": frameRate,
        "fps": frameRate,
        "segmentDurationMs": Int(segmentDurationMs),
        "hasAudio": hasAudio
      ]

      do {
        let keyframeTimes = try collectKeyframes(from: videoTrack)
        if !keyframeTimes.isEmpty {
          metadata["keyframes"] = keyframeTimes.map { ["timestampMs": $0] }
        }
      } catch {
        if job.enableLogging {
          print("[VideoProxyChannel] Failed to collect keyframes for job=\(job.jobId): \(error.localizedDescription)")
        }
      }

      emit([
        "jobId": job.jobId,
        "type": "metadata_ready",
        "metadata": metadata
      ])

      let elapsed = Int(Date().timeIntervalSince(startDate) * 1000)
      completion([
        "ok": true,
        "jobId": job.jobId,
        "proxyPath": "",
        "durationMs": durationMs,
        "width": videoWidth,
        "height": videoHeight,
        "frameRate": frameRate,
        "transcodeDurationMs": elapsed
      ])

      generatePreviewGop(videoTrack: videoTrack, metadata: metadata)
    }

    private func collectKeyframes(from track: AVAssetTrack) throws -> [Int] {
      let reader = try AVAssetReader(asset: asset)
      let settings: [String: Any] = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
      ]
      let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
      output.alwaysCopiesSampleData = false
      reader.add(output)
      guard reader.startReading() else {
        throw reader.error ?? makeError(code: -4, message: "Failed to start keyframe reader")
      }

      var keyframes: [Int] = []
      let maxFrames = 512
      while let sample = output.copyNextSampleBuffer() {
        if cancelled {
          reader.cancelReading()
          break
        }
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false) as? [[CFString: Any]],
           attachments.first?[kCMSampleAttachmentKey_NotSync] == nil {
          let pts = CMSampleBufferGetPresentationTimeStamp(sample)
          let ms = Int((CMTimeGetSeconds(pts) * 1000.0).rounded())
          keyframes.append(ms)
        }
        CMSampleBufferInvalidate(sample)
        if keyframes.count >= maxFrames {
          break
        }
      }
      reader.cancelReading()
      return keyframes
    }

    private func generatePreviewGop(videoTrack: AVAssetTrack, metadata: [String: Any]) {
      asyncOnQueue {
        guard !self.cancelled else { return }

        let previewURL = self.cacheDirectory.appendingPathComponent("preview_\(self.job.jobId).mp4")
        let previewDuration = min(Int64(self.durationMs), max(self.segmentDurationMs, Int64(2000)))
        let timeRange = CMTimeRange(
          start: .zero,
          duration: CMTime(value: previewDuration, timescale: 1000)
        )

        guard let composition = self.preparedVideoComposition else { return }

        do {
          let reader = try AVAssetReader(asset: self.asset)
          reader.timeRange = timeRange

          let writer = try AVAssetWriter(outputURL: previewURL, fileType: .mp4)

          let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: self.videoWidth,
            AVVideoHeightKey: self.videoHeight,
            AVVideoCompressionPropertiesKey: [
              AVVideoAverageBitRateKey: 600_000,
              AVVideoMaxKeyFrameIntervalKey: 24,
              AVVideoProfileLevelKey: AVVideoProfileLevelH264BaselineAutoLevel
            ]
          ]

          let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
          writerInput.expectsMediaDataInRealTime = false
          writerInput.transform = .identity
          let readerOutput = AVAssetReaderVideoCompositionOutput(videoTracks: [videoTrack], videoSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
          ])
          readerOutput.alwaysCopiesSampleData = false
          readerOutput.videoComposition = composition
          reader.add(readerOutput)

          writer.add(writerInput)

          let writingQueue = DispatchQueue(label: "com.example.coalition.videoProxy.preview.\(self.job.jobId)")
          let finishGroup = DispatchGroup()
          finishGroup.enter()

          var finished = false
          writerInput.requestMediaDataWhenReady(on: writingQueue) {
            if finished { return }
            while writerInput.isReadyForMoreMediaData {
              if self.cancelled {
                finished = true
                writerInput.markAsFinished()
                finishGroup.leave()
                return
              }
              guard let sample = readerOutput.copyNextSampleBuffer() else {
                finished = true
                writerInput.markAsFinished()
                finishGroup.leave()
                return
              }
              writerInput.append(sample)
            }
          }

          guard reader.startReading() else {
            throw reader.error ?? self.makeError(code: -5, message: "Preview reader failed")
          }

          writer.startWriting()
          writer.startSession(atSourceTime: .zero)

          finishGroup.wait()

          let writerGroup = DispatchGroup()
          writerGroup.enter()
          writer.finishWriting {
            writerGroup.leave()
          }
          writerGroup.wait()

          if self.cancelled || writer.status != .completed || reader.status != .completed {
            throw writer.error ?? reader.error ?? self.makeError(code: -6, message: "Preview export failed")
          }

          self.previewURL = previewURL

          self.emit([
            "jobId": self.job.jobId,
            "type": "preview_ready",
            "path": previewURL.path,
            "durationMs": Int(previewDuration),
            "width": self.videoWidth,
            "height": self.videoHeight,
            "previewQualityLabel": SegmentQuality.preview.rawValue,
            "metadata": metadata
          ])
        } catch {
          try? FileManager.default.removeItem(at: previewURL)
          if self.job.enableLogging {
            print("[VideoProxyChannel] Preview generation failed for job=\(self.job.jobId): \(error.localizedDescription)")
          }
        }
      }
    }

    private func produceSegment(key: SegmentKey,
                                quality: SegmentQuality,
                                reason: EmitReason,
                                completion: ((Result<CacheEntry, Error>) -> Void)?) {
      if cancelled {
        completion?(.failure(makeError(code: -10, message: "Session cancelled")))
        return
      }

      if let existing = cacheEntry(for: key) {
        completion?(.success(existing))
        return
      }

      guard let exportSession = AVAssetExportSession(asset: asset, presetName: quality.exportPreset) else {
        completion?(.failure(makeError(code: -7, message: "Unable to create export session")))
        return
      }

      let outputURL = segmentURL(for: key)
      try? FileManager.default.removeItem(at: outputURL)

      exportSession.outputURL = outputURL
      exportSession.outputFileType = .mp4
      exportSession.timeRange = key.timeRange(maxDurationMs: durationMs)
      exportSession.shouldOptimizeForNetworkUse = true
      if let composition = preparedVideoComposition {
        exportSession.videoComposition = composition
      }

      pendingExports[key] = exportSession

      exportSession.exportAsynchronously { [weak self] in
        guard let self else { return }
        self.asyncOnQueue {
          self.pendingExports.removeValue(forKey: key)

          if self.cancelled {
            try? FileManager.default.removeItem(at: outputURL)
            completion?(.failure(self.makeError(code: -10, message: "Session cancelled")))
            return
          }

          switch exportSession.status {
          case .completed:
            let attributes = try? FileManager.default.attributesOfItem(atPath: outputURL.path)
            let sizeValue = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
            let entry = CacheEntry(key: key, url: outputURL, fileSize: sizeValue)
            self.storeCacheEntry(entry)
            if reason == .upgrade {
              self.emitSegmentEvent(entry: entry, reason: .upgrade)
            }
            completion?(.success(entry))
          case .cancelled:
            try? FileManager.default.removeItem(at: outputURL)
            completion?(.failure(self.makeError(code: -8, message: "Segment export cancelled")))
          default:
            let error = exportSession.error ?? self.makeError(code: -9, message: "Segment export failed")
            try? FileManager.default.removeItem(at: outputURL)
            completion?(.failure(error))
          }
        }
      }
    }

    private func scheduleUpgrades(for key: SegmentKey, producedQuality: SegmentQuality) {
      for candidate in SegmentQuality.allCases where candidate.rank > producedQuality.rank {
        let upgradeKey = SegmentKey(startMs: key.startMs, endMs: key.endMs, quality: candidate)
        if cache[upgradeKey] != nil { continue }
        if pendingExports[upgradeKey] != nil { continue }
        if pendingUpgradeKeys.contains(upgradeKey) { continue }
        pendingUpgradeKeys.insert(upgradeKey)

        produceSegment(key: upgradeKey, quality: candidate, reason: .upgrade) { [weak self] _ in
          guard let self else { return }
          self.asyncOnQueue {
            self.pendingUpgradeKeys.remove(upgradeKey)
          }
        }
      }
    }

    private func emit(_ payload: [String: Any]) {
      if cancelled { return }
      eventEmitter(payload)
    }

    private func emitSegmentEvent(entry: CacheEntry, reason: EmitReason) {
      var payload: [String: Any] = [
        "jobId": job.jobId,
        "path": entry.url.path,
        "durationMs": entry.key.durationMs,
        "segmentIndex": entry.key.segmentIndex(segmentDurationMs: segmentDurationMs),
        "width": videoWidth,
        "height": videoHeight,
        "hasAudio": hasAudio,
        "quality": entry.key.quality.rawValue,
        "metadata": [
          "segmentDurationMs": Int(segmentDurationMs),
          "width": videoWidth,
          "height": videoHeight,
          "frameRate": frameRate,
          "fps": frameRate,
          "durationMs": durationMs,
          "hasAudio": hasAudio
        ]
      ]

      if reason == .ensure {
        payload["type"] = "segment_ready"
        payload["totalSegments"] = totalSegments
        payload["totalDurationMs"] = durationMs
      } else {
        payload["type"] = "segment_upgraded"
      }

      emit(payload)
    }

    private func cacheEntry(for key: SegmentKey) -> CacheEntry? {
      guard let entry = cache[key] else { return nil }
      if !FileManager.default.fileExists(atPath: entry.url.path) {
        cache.removeValue(forKey: key)
        lru.removeAll { $0 == key }
        totalBytes = max(0, totalBytes - entry.fileSize)
        return nil
      }
      touch(key)
      return entry
    }

    private func storeCacheEntry(_ entry: CacheEntry) {
      if let existing = cache[entry.key] {
        totalBytes = max(0, totalBytes - existing.fileSize)
      }
      cache[entry.key] = entry
      touch(entry.key)
      totalBytes += entry.fileSize
      trimCacheIfNeeded()
    }

    private func touch(_ key: SegmentKey) {
      lru.removeAll { $0 == key }
      lru.append(key)
    }

    private func trimCacheIfNeeded() {
      while (cache.count > maxCacheEntries || totalBytes > maxCacheBytes), let oldest = lru.first {
        lru.removeFirst()
        if let removed = cache.removeValue(forKey: oldest) {
          totalBytes = max(0, totalBytes - removed.fileSize)
          try? FileManager.default.removeItem(at: removed.url)
        }
      }
    }

    private func segmentURL(for key: SegmentKey) -> URL {
      let filename = String(
        format: "segment_%010lld_%010lld_%@.mp4",
        key.startMs,
        key.endMs,
        key.quality.rawValue.lowercased()
      )
      return cacheDirectory.appendingPathComponent(filename)
    }

    private func makeVideoComposition(for track: AVAssetTrack) -> AVMutableVideoComposition {
      let composition = AVMutableVideoComposition()
      composition.renderSize = job.targetSize
      let timescale = max(1, job.frameRateHint)
      composition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(timescale))

      let instruction = AVMutableVideoCompositionInstruction()
      instruction.timeRange = CMTimeRange(start: .zero, duration: asset.duration)

      let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
      let transform = transformForTrack(track)
      layerInstruction.setTransform(transform, at: .zero)
      instruction.layerInstructions = [layerInstruction]
      composition.instructions = [instruction]
      return composition
    }

    private func transformForTrack(_ track: AVAssetTrack) -> CGAffineTransform {
      let preferredTransform = track.preferredTransform
      let naturalSize = track.naturalSize
      let rawRect = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
      let boundingRect = CGRect(
        x: min(rawRect.minX, rawRect.maxX),
        y: min(rawRect.minY, rawRect.maxY),
        width: abs(rawRect.width),
        height: abs(rawRect.height)
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
      return finalTransform
    }

    private func cleanupFiles() {
      if let previewURL, FileManager.default.fileExists(atPath: previewURL.path) {
        try? FileManager.default.removeItem(at: previewURL)
      }
      for entry in cache.values {
        try? FileManager.default.removeItem(at: entry.url)
      }
      cache.removeAll()
      lru.removeAll()
      totalBytes = 0
    }

    private func performTeardownIfNeeded() {
      if didTeardown { return }
      didTeardown = true
      teardown()
    }

    private func handleFatalError(_ error: Error) {
      if job.enableLogging {
        print("[VideoProxyChannel] Proxy session failed for job=\(job.jobId): \(error.localizedDescription)")
      }
      cancel()
      fallback(error)
    }

    private func makeError(code: Int, message: String) -> NSError {
      return NSError(domain: "VideoProxySession", code: code, userInfo: [NSLocalizedDescriptionKey: message])
    }

    private func asyncOnQueue(_ block: @escaping () -> Void) {
      if DispatchQueue.getSpecific(key: queueKey) != nil {
        block()
      } else {
        queue.async(execute: block)
      }
    }
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
