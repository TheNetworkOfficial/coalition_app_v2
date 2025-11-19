import AVFoundation
import Flutter
import UIKit

final class PreviewPlatformView: NSObject, FlutterPlatformView {
  private final class PreviewContainer: UIView {
    let playerLayer: AVPlayerLayer

    init(layer: AVPlayerLayer) {
      self.playerLayer = layer
      super.init(frame: .zero)
      layer.needsDisplayOnBoundsChange = true
      self.layer.addSublayer(layer)
    }

    required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
      super.layoutSubviews()
      playerLayer.frame = bounds
    }
  }

  private let container: PreviewContainer
  private let playerLayer = AVPlayerLayer()
  private let disposeHandler: (() -> Void)?

  init(frame: CGRect, viewId: Int64, disposeHandler: (() -> Void)? = nil) {
    let layer = AVPlayerLayer()
    layer.videoGravity = .resizeAspect
    self.container = PreviewContainer(layer: layer)
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

  func dispose() {
    playerLayer.player = nil
    disposeHandler?()
  }
}
