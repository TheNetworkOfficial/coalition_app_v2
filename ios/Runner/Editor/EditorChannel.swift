import AVFoundation
import Flutter
import Foundation

final class EditorChannel: NSObject, FlutterStreamHandler {
  private let methodChannel: FlutterMethodChannel
  private let eventChannel: FlutterEventChannel
  private weak var previewRegistry: PreviewPlatformViewFactory?
  private let compositionBuilder = CompositionBuilder()

  private var eventSink: FlutterEventSink?
  private var player: AVPlayer?
  private var timeObserver: Any?
  private var currentUrl: URL?
  private var currentTimeline: String?
  private var currentPosterAsset: AVAsset?
  private var currentViewId: Int64?

  init(messenger: FlutterBinaryMessenger, previewRegistry: PreviewPlatformViewFactory) {
    self.previewRegistry = previewRegistry
    self.methodChannel = FlutterMethodChannel(name: "EditorChannel", binaryMessenger: messenger)
    self.eventChannel = FlutterEventChannel(name: "EditorChannelEvents", binaryMessenger: messenger)
    super.init()
    methodChannel.setMethodCallHandler(handle)
    eventChannel.setStreamHandler(self)
  }

  func releaseChannel() {
    releasePlayer()
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "prepareTimeline":
      guard let args = call.arguments as? [String: Any],
            let sourcePath = args["sourcePath"] as? String,
            let surfaceId = args["surfaceId"] as? NSNumber
      else {
        result(FlutterError(code: "invalid_args", message: "Missing args", details: nil))
        return
      }
      let proxyPath = args["proxyPath"] as? String
      currentTimeline = args["timelineJson"] as? String
      let path = proxyPath?.isEmpty == false ? proxyPath! : sourcePath
      currentUrl = URL(fileURLWithPath: path)
      currentViewId = surfaceId.int64Value
      DispatchQueue.main.async {
        self.preparePlayer(viewId: surfaceId.int64Value, result: result)
      }
    case "updateTimeline":
      currentTimeline = (call.arguments as? [String: Any])?["timelineJson"] as? String
      DispatchQueue.main.async {
        self.preparePlayer(viewId: nil, result: result)
      }
    case "seekPreview":
      guard let args = call.arguments as? [String: Any],
            let position = args["positionMs"] as? NSNumber
      else {
        result(FlutterError(code: "invalid_args", message: "positionMs missing", details: nil))
        return
      }
      let time = CMTime(value: CMTimeValue(truncating: position), timescale: 1000)
      player?.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
      result(nil)
    case "setPlaybackState":
      let args = call.arguments as? [String: Any]
      let playing = args?["playing"] as? Bool ?? true
      if let speed = args?["speed"] as? NSNumber {
        let factor = Float(truncating: speed)
        player?.rate = factor
        player?.play()
        player?.automaticallyWaitsToMinimizeStalling = false
      } else {
        if playing {
          player?.play()
        } else {
          player?.pause()
        }
      }
      result(nil)
    case "generatePosterFrame":
      guard let args = call.arguments as? [String: Any],
            let position = args["positionMs"] as? NSNumber,
            let asset = currentPosterAsset
      else {
        result(FlutterError(code: "invalid_args", message: "position missing", details: nil))
        return
      }
      let generator = AVAssetImageGenerator(asset: asset)
      generator.appliesPreferredTrackTransform = true
      let time = CMTime(value: CMTimeValue(truncating: position), timescale: 1000)
      DispatchQueue.global().async {
        do {
          let image = try generator.copyCGImage(at: time, actualTime: nil)
          let url = self.writePoster(image: image)
          DispatchQueue.main.async {
            result(url?.path)
          }
        } catch {
          DispatchQueue.main.async {
            result(FlutterError(code: "poster_failed", message: error.localizedDescription, details: nil))
          }
        }
      }
    case "release":
      releasePlayer()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func preparePlayer(viewId: Int64?, result: @escaping FlutterResult) {
    guard let url = currentUrl else {
      result(FlutterError(code: "unavailable", message: "Media missing", details: nil))
      return
    }
    do {
      let build = try compositionBuilder.build(url: url, timelineJson: currentTimeline)
      currentPosterAsset = build.posterAsset
      let item = build.playerItem
      let existingTime = player?.currentTime() ?? .zero
      if player == nil {
        player = AVPlayer(playerItem: item)
        player?.actionAtItemEnd = .none
        addTimeObserver()
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleItemEnd),
                                               name: .AVPlayerItemDidPlayToEndTime,
                                               object: nil)
      } else {
        player?.replaceCurrentItem(with: item)
      }
      let targetViewId = viewId ?? currentViewId
      if let id = targetViewId {
        currentViewId = id
        if let preview = previewRegistry?.view(for: id) {
          preview.bind(player: player)
        }
      }
      player?.seek(to: existingTime, toleranceBefore: .zero, toleranceAfter: .zero)
      player?.play()
      emit(event: ["type": "prepared"])
      result(nil)
    } catch {
      result(FlutterError(code: "prepare_failed", message: error.localizedDescription, details: nil))
    }
  }

  private func addTimeObserver() {
    guard timeObserver == nil else { return }
    timeObserver = player?.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.3, preferredTimescale: 1000),
                                                   queue: .main) { [weak self] time in
      self?.emit(event: [
        "type": "progress",
        "positionMs": Int(time.seconds * 1000),
      ])
    }
  }

  @objc private func handleItemEnd() {
    player?.seek(to: .zero)
    player?.play()
  }

  private func writePoster(image: CGImage) -> URL? {
    let data = UIImage(cgImage: image).pngData()
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("poster_\(UUID().uuidString).png")
    if let data = data {
      try? data.write(to: url)
      return url
    }
    return nil
  }

  private func releasePlayer() {
    if let observer = timeObserver {
      player?.removeTimeObserver(observer)
      timeObserver = nil
    }
    NotificationCenter.default.removeObserver(self)
    player?.pause()
    player?.replaceCurrentItem(with: nil)
    player = nil
    currentPosterAsset = nil
  }

  func onListen(withArguments _: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    return nil
  }

  func onCancel(withArguments _: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  private func emit(event: [String: Any]) {
    eventSink?(event)
  }
}
