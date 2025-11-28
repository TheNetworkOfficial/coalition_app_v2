import AVFoundation
import Flutter
import Foundation
import UIKit

final class EditorChannel: NSObject, FlutterStreamHandler {
  private let methodChannel: FlutterMethodChannel
  private let eventChannel: FlutterEventChannel
  private weak var previewRegistry: PreviewPlatformViewFactory?
  private let compositionBuilder = CompositionBuilder()

  private let overlayRenderer = OverlayRenderer()
  private var textOverlays: [TextOverlay] = []
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
      textOverlays = parseTextOverlays(from: currentTimeline)
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
      if let id = targetViewId, let preview = previewRegistry?.view(for: id) {
        currentViewId = id
        preview.bind(player: player)
        applyTextOverlays(on: preview)
      } else if let id = currentViewId, let preview = previewRegistry?.view(for: id) {
        applyTextOverlays(on: preview)
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
    timeObserver = player?.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.2, preferredTimescale: 600),
                                                   queue: .main) { [weak self] time in
      guard let self = self else { return }
      let positionMs = Int64(time.seconds * 1000)
      self.overlayRenderer.updateVisibility(currentMs: positionMs, overlays: self.textOverlays)
      self.emit(event: [
        "type": "progress",
        "positionMs": Int(positionMs),
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
    textOverlays = []
    if let id = currentViewId, let preview = previewRegistry?.view(for: id) {
      overlayRenderer.applyTextOverlays([], in: preview.overlayLayer)
    }
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

  private func applyTextOverlays(on preview: PreviewPlatformView) {
    let view = preview.view()
    view.setNeedsLayout()
    view.layoutIfNeeded()
    overlayRenderer.applyTextOverlays(textOverlays, in: preview.overlayLayer)
    updateOverlayVisibility()
  }

  private func updateOverlayVisibility() {
    guard !textOverlays.isEmpty else { return }
    guard let player = player else { return }
    let seconds = CMTimeGetSeconds(player.currentTime())
    let positionMs = Int64(seconds * 1000)
    overlayRenderer.updateVisibility(currentMs: positionMs, overlays: textOverlays)
  }

  private func parseTextOverlays(from json: String?) -> [TextOverlay] {
    guard let data = json?.data(using: .utf8),
          let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      return []
    }
    let ops = (root["ops"] as? [[String: Any]]) ?? []
    var overlays: [TextOverlay] = []
    for entry in ops {
      guard let type = entry["type"] as? String, type == "overlay_text" else { continue }
      guard let text = entry["text"] as? String, !text.isEmpty else { continue }
      let x = CGFloat(doubleValue(entry["x"], fallback: 0.5)).clamped(min: 0, max: 1)
      let y = CGFloat(doubleValue(entry["y"], fallback: 0.5)).clamped(min: 0, max: 1)
      let rawScale = CGFloat(doubleValue(entry["scale"], fallback: 1.0))
      let scale = rawScale.clamped(min: 0.5, max: 3.0)
      let rotation = CGFloat(doubleValue(entry["rotationDeg"], fallback: 0.0))
      let start = int64Value(entry["startMs"]) ?? 0
      let rawEnd = int64Value(entry["endMs"]) ?? Int64.max
      let end = max(start, rawEnd)
      let color = color(from: entry["color"] as? String)
      let overlay = TextOverlay(
        text: text,
        x: x,
        y: y,
        scale: scale,
        rotationDeg: rotation,
        color: color,
        startMs: start,
        endMs: end
      )
      overlays.append(overlay)
    }
    return overlays
  }

  private func doubleValue(_ value: Any?, fallback: Double) -> Double {
    if let number = value as? NSNumber {
      return number.doubleValue
    }
    if let string = value as? String, let parsed = Double(string) {
      return parsed
    }
    return fallback
  }

  private func int64Value(_ value: Any?) -> Int64? {
    if let number = value as? NSNumber {
      return number.int64Value
    }
    if let string = value as? String, let parsed = Double(string) {
      return Int64(parsed)
    }
    return nil
  }

  private func color(from hex: String?) -> UIColor {
    guard var raw = hex?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
      return .white
    }
    if raw.hasPrefix("#") {
      raw.removeFirst()
    }
    guard raw.count == 6 else {
      return .white
    }
    var value: UInt64 = 0
    Scanner(string: raw).scanHexInt64(&value)
    let r = CGFloat((value & 0xFF0000) >> 16) / 255
    let g = CGFloat((value & 0x00FF00) >> 8) / 255
    let b = CGFloat(value & 0x0000FF) / 255
    return UIColor(red: r, green: g, blue: b, alpha: 1)
  }
}

private extension CGFloat {
  func clamped(min: CGFloat, max: CGFloat) -> CGFloat {
    Swift.max(min, Swift.min(self, max))
  }
}
