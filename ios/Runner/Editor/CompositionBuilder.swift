import AVFoundation
import CoreGraphics
import CoreMedia
import UIKit

struct FilterOpConfig {
  let filterName: String
  let intensity: Float
}

struct TimelineConfig {
  let trimRange: CMTimeRange?
  let speed: Float
  let rotationDegrees: CGFloat
  let cropRect: CGRect?
  let filter: FilterOpConfig?
  let overlays: [OverlayTextOp]
}

struct CompositionBuildResult {
  let playerItem: AVPlayerItem
  let posterAsset: AVAsset
}

final class CompositionBuilder {
  func build(url: URL, timelineJson: String?) throws -> CompositionBuildResult {
    let asset = AVURLAsset(url: url)
    let config = parseTimeline(json: timelineJson, asset: asset)
    let composition = AVMutableComposition()

    guard let assetVideoTrack = asset.tracks(withMediaType: .video).first else {
      throw NSError(domain: "EditorChannel", code: -1, userInfo: [NSLocalizedDescriptionKey: "Video track missing"])
    }

    let timeRange = config.trimRange ?? CMTimeRange(start: .zero, duration: asset.duration)
    let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
    try videoTrack?.insertTimeRange(timeRange, of: assetVideoTrack, at: .zero)
    videoTrack?.preferredTransform = assetVideoTrack.preferredTransform

    if let assetAudioTrack = asset.tracks(withMediaType: .audio).first {
      let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
      try audioTrack?.insertTimeRange(timeRange, of: assetAudioTrack, at: .zero)
    }

    if config.speed != 1 {
      let duration = composition.duration
      let scaledDuration = CMTimeMultiplyByFloat64(duration, 1.0 / Double(max(config.speed, 0.1)))
      composition.scaleTimeRange(CMTimeRange(start: .zero, duration: duration), toDuration: scaledDuration)
    }

    var videoComposition: AVVideoComposition?
    if config.filter != nil || config.rotationDegrees != 0 || config.cropRect != nil || !config.overlays.isEmpty {
      let originalSize = assetVideoTrack.naturalSize
      var renderSize = originalSize
      if let crop = config.cropRect {
        renderSize = CGSize(width: crop.size.width * originalSize.width,
                            height: crop.size.height * originalSize.height)
      }
      videoComposition = AVVideoComposition(asset: composition) { request in
        var output = request.sourceImage.clampedToExtent()
        if let crop = config.cropRect {
          let cropRect = CGRect(
            x: crop.origin.x * originalSize.width,
            y: (1 - crop.origin.y - crop.size.height) * originalSize.height,
            width: crop.size.width * originalSize.width,
            height: crop.size.height * originalSize.height
          )
          output = output.cropped(to: cropRect)
          output = output.transformed(by: CGAffineTransform(translationX: -cropRect.origin.x, y: -cropRect.origin.y))
        }
        if config.rotationDegrees != 0 {
          let radians = config.rotationDegrees * .pi / 180
          let centerX = renderSize.width / 2
          let centerY = renderSize.height / 2
          let transform = CGAffineTransform(translationX: centerX, y: centerY)
            .rotated(by: radians)
            .translatedBy(x: -centerX, y: -centerY)
          output = output.transformed(by: transform)
        }
        if let filter = config.filter, let ciFilter = CIFilter(name: filter.filterName) {
          ciFilter.setValue(output, forKey: kCIInputImageKey)
          ciFilter.setValue(filter.intensity, forKey: kCIInputIntensityKey)
          if let filtered = ciFilter.outputImage {
            output = filtered
          }
        }
        output = OverlayRenderer.apply(overlays: config.overlays,
                                       to: output,
                                       renderSize: renderSize,
                                       time: request.compositionTime)
        request.finish(with: output, context: nil)
      }
      videoComposition?.renderSize = renderSize
      videoComposition?.frameDuration = CMTime(value: 1, timescale: 30)
    }

    let playerItem = AVPlayerItem(asset: composition)
    playerItem.videoComposition = videoComposition
    return CompositionBuildResult(playerItem: playerItem, posterAsset: composition)
  }

  private func parseTimeline(json: String?, asset: AVAsset) -> TimelineConfig {
    guard let data = json?.data(using: .utf8),
          let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      return TimelineConfig(trimRange: nil,
                             speed: 1,
                             rotationDegrees: 0,
                             cropRect: nil,
                             filter: nil,
                             overlays: [])
    }
    let ops = (root["ops"] as? [[String: Any]]) ?? []
    var trimStart: Int?
    var trimEnd: Int?
    var speed: Float = 1
    var turns = 0
    var cropRect: CGRect?
    var filter: FilterOpConfig?
    var overlays: [OverlayTextOp] = []
    for op in ops {
      switch op["type"] as? String {
      case "trim":
        trimStart = op["startMs"] as? Int
        trimEnd = op["endMs"] as? Int
      case "speed":
        if let factor = op["factor"] as? Double, factor > 0 {
          speed = Float(factor)
        }
      case "rotate":
        turns = op["turns"] as? Int ?? 0
      case "crop":
        if let left = op["left"] as? Double,
           let top = op["top"] as? Double,
           let width = op["width"] as? Double,
           let height = op["height"] as? Double {
          cropRect = CGRect(x: left, y: top, width: width, height: height)
        }
      case "filter":
        if let id = op["id"] as? String {
          filter = FilterOpConfig(filterName: filterName(for: id), intensity: Float(op["intensity"] as? Double ?? 1.0))
        }
      case "overlay_text":
        if let text = op["text"] as? String {
          let colorHex = (op["color"] as? String) ?? "#FFFFFFFF"
          let color = UIColor(hex: colorHex)
          let overlay = OverlayTextOp(
            text: text,
            x: CGFloat(op["x"] as? Double ?? 0.5),
            y: CGFloat(op["y"] as? Double ?? 0.5),
            scale: CGFloat(op["scale"] as? Double ?? 1.0),
            rotation: CGFloat(op["rotationDeg"] as? Double ?? 0.0),
            startMs: op["startMs"] as? Int,
            endMs: op["endMs"] as? Int,
            color: color,
            fontName: op["fontFamily"] as? String
          )
          overlays.append(overlay)
        }
      default:
        continue
      }
    }

    var trimRange: CMTimeRange?
    if let start = trimStart {
      let startTime = CMTime(value: CMTimeValue(start), timescale: 1000)
      let end: CMTime
      if let endMs = trimEnd {
        end = CMTime(value: CMTimeValue(endMs), timescale: 1000)
      } else {
        end = asset.duration
      }
      trimRange = CMTimeRange(start: startTime, duration: CMTimeSubtract(end, startTime))
    }

    let normalizedTurns = ((turns % 4) + 4) % 4
    return TimelineConfig(trimRange: trimRange,
                          speed: speed,
                          rotationDegrees: CGFloat(normalizedTurns) * 90,
                          cropRect: cropRect,
                          filter: filter,
                          overlays: overlays)
  }

  private func filterName(for id: String) -> String {
    switch id.lowercased() {
    case "bw":
      return "CIPhotoEffectNoir"
    case "fade":
      return "CIPhotoEffectFade"
    default:
      return id
    }
  }
}

private extension UIColor {
  convenience init(hex: String) {
    var raw = hex
    if raw.hasPrefix("#") {
      raw.removeFirst()
    }
    var value: UInt64 = 0
    Scanner(string: raw).scanHexInt64(&value)
    let r, g, b, a: CGFloat
    switch raw.count {
    case 8:
      r = CGFloat((value & 0xFF00_0000) >> 24) / 255
      g = CGFloat((value & 0x00FF_0000) >> 16) / 255
      b = CGFloat((value & 0x0000_FF00) >> 8) / 255
      a = CGFloat(value & 0x0000_00FF) / 255
    case 6:
      r = CGFloat((value & 0xFF00_00) >> 16) / 255
      g = CGFloat((value & 0x00FF_00) >> 8) / 255
      b = CGFloat(value & 0x0000_FF) / 255
      a = 1
    default:
      r = 1
      g = 1
      b = 1
      a = 1
    }
    self.init(red: r, green: g, blue: b, alpha: a)
  }
}
