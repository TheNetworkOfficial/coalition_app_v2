import CoreImage
import CoreGraphics
import CoreMedia
import UIKit

struct OverlayTextOp {
  let text: String
  let x: CGFloat
  let y: CGFloat
  let scale: CGFloat
  let rotation: CGFloat
  let startMs: Int?
  let endMs: Int?
  let color: UIColor
  let fontName: String?

  func contains(timeMs: Double) -> Bool {
    if let start = startMs, timeMs < Double(start) {
      return false
    }
    if let end = endMs, timeMs > Double(end) {
      return false
    }
    return true
  }
}

enum OverlayRenderer {
  static func apply(overlays: [OverlayTextOp],
                    to image: CIImage,
                    renderSize: CGSize,
                    time: CMTime) -> CIImage {
    guard !overlays.isEmpty else {
      return image
    }
    var output = image
    let timeMs = time.seconds * 1000.0
    for overlay in overlays where overlay.contains(timeMs: timeMs) {
      guard let textImage = makeTextImage(for: overlay, canvasSize: renderSize) else {
        continue
      }
      var overlayCI = CIImage(cgImage: textImage)
      let normalizedX = overlay.x.clamped(to: 0 ... 1)
      let normalizedY = overlay.y.clamped(to: 0 ... 1)
      let targetX = normalizedX * renderSize.width - CGFloat(textImage.width) / 2
      let targetY = (1 - normalizedY) * renderSize.height - CGFloat(textImage.height) / 2
      var transform = CGAffineTransform(translationX: targetX, y: targetY)
      if overlay.rotation != 0 {
        let radians = overlay.rotation * .pi / 180
        transform = transform
          .translatedBy(x: CGFloat(textImage.width) / 2, y: CGFloat(textImage.height) / 2)
          .rotated(by: radians)
          .translatedBy(x: -CGFloat(textImage.width) / 2, y: -CGFloat(textImage.height) / 2)
      }
      overlayCI = overlayCI.transformed(by: transform)
      output = overlayCI.composited(over: output)
    }
    return output
  }

  private static func makeTextImage(for overlay: OverlayTextOp, canvasSize: CGSize) -> CGImage? {
    let baseWidth = max(canvasSize.width * overlay.scale * 0.2, 32)
    let baseHeight = max(canvasSize.height * overlay.scale * 0.08, 24)
    let size = CGSize(width: baseWidth, height: baseHeight)
    let renderer = UIGraphicsImageRenderer(size: size)
    let image = renderer.image { ctx in
      let paragraph = NSMutableParagraphStyle()
      paragraph.alignment = .center
      let attributes: [NSAttributedString.Key: Any] = [
        .font: UIFont(name: overlay.fontName ?? "HelveticaNeue-Bold", size: baseHeight * 0.6)
          ?? UIFont.boldSystemFont(ofSize: baseHeight * 0.6),
        .foregroundColor: overlay.color,
        .paragraphStyle: paragraph,
      ]
      let textRect = CGRect(origin: .zero, size: size)
      overlay.text.draw(in: textRect.insetBy(dx: 4, dy: 4), withAttributes: attributes)
    }
    return image.cgImage
  }
}

private extension Comparable {
  func clamped(to limits: ClosedRange<Self>) -> Self {
    min(max(self, limits.lowerBound), limits.upperBound)
  }
}
