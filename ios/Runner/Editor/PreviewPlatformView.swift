import AVFoundation
import Flutter
import UIKit

final class PreviewPlatformView: NSObject, FlutterPlatformView {
  private final class PreviewContainer: UIView {
    let playerLayer: AVPlayerLayer
    let overlayLayer = CALayer()

    init(playerLayer: AVPlayerLayer) {
      self.playerLayer = playerLayer
      super.init(frame: .zero)
      playerLayer.needsDisplayOnBoundsChange = true
      layer.addSublayer(playerLayer)
      layer.addSublayer(overlayLayer)
    }

    required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
      super.layoutSubviews()
      playerLayer.frame = bounds
      overlayLayer.frame = bounds
    }
  }

  private let container: PreviewContainer
  private let playerLayer: AVPlayerLayer
  private let disposeHandler: (() -> Void)?

  init(frame: CGRect, viewId: Int64, disposeHandler: (() -> Void)? = nil) {
    let layer = AVPlayerLayer()
    layer.videoGravity = .resizeAspect
    self.playerLayer = layer
    self.container = PreviewContainer(playerLayer: layer)
    self.disposeHandler = disposeHandler
    super.init()
    container.frame = frame
    container.backgroundColor = .black
  }

  func view() -> UIView {
    container
  }

  func bind(player: AVPlayer?) {
    playerLayer.player = player
  }

  var overlayLayer: CALayer {
    container.overlayLayer
  }

  func dispose() {
    playerLayer.player = nil
    disposeHandler?()
  }
}
