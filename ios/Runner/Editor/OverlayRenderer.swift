import UIKit

struct TextOverlay {
  let text: String
  let x: CGFloat
  let y: CGFloat
  let scale: CGFloat
  let rotationDeg: CGFloat
  let color: UIColor
  let startMs: Int64
  let endMs: Int64
}

final class OverlayRenderer {
  private var textLayers: [CATextLayer] = []

  func applyTextOverlays(_ overlays: [TextOverlay], in overlayLayer: CALayer) {
    overlayLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
    textLayers.removeAll()
    guard !overlays.isEmpty else { return }
    let size = overlayLayer.bounds.size
    for overlay in overlays {
      let layer = makeTextLayer(for: overlay, canvasSize: size)
      overlayLayer.addSublayer(layer)
      textLayers.append(layer)
    }
  }

  func updateVisibility(currentMs: Int64, overlays: [TextOverlay]) {
    guard overlays.count == textLayers.count else { return }
    for (index, layer) in textLayers.enumerated() {
      let overlay = overlays[index]
      let isVisible = currentMs >= overlay.startMs && currentMs <= overlay.endMs
      layer.isHidden = !isVisible
    }
  }

  private func makeTextLayer(for overlay: TextOverlay, canvasSize: CGSize) -> CATextLayer {
    let layer = CATextLayer()
    layer.contentsScale = UIScreen.main.scale
    layer.string = overlay.text
    layer.alignmentMode = .center
    layer.foregroundColor = overlay.color.cgColor
    let fontSize: CGFloat = 18
    layer.fontSize = fontSize

    let attributes: [NSAttributedString.Key: Any] = [
      .font: UIFont.systemFont(ofSize: fontSize),
    ]
    let text = overlay.text as NSString
    let bounding = text.boundingRect(
      with: CGSize(width: canvasSize.width, height: .greatestFiniteMagnitude),
      options: [.usesLineFragmentOrigin],
      attributes: attributes,
      context: nil
    )
    layer.bounds = CGRect(origin: .zero, size: bounding.size)

    let normalizedX = max(0, min(1, overlay.x))
    let normalizedY = max(0, min(1, overlay.y))
    let position = CGPoint(x: normalizedX * canvasSize.width, y: normalizedY * canvasSize.height)
    layer.position = position

    let radians = overlay.rotationDeg * .pi / 180
    var transform = CATransform3DIdentity
    transform = CATransform3DScale(transform, overlay.scale, overlay.scale, 1)
    transform = CATransform3DRotate(transform, radians, 0, 0, 1)
    layer.transform = transform

    layer.isHidden = false
    layer.setNeedsDisplay()
    return layer
  }
}
