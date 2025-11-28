import Flutter

final class PreviewPlatformViewFactory: NSObject, FlutterPlatformViewFactory {
  private var views: [Int64: PreviewPlatformView] = [:]

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments _: Any?) -> FlutterPlatformView {
    let view = PreviewPlatformView(frame: frame, viewId: viewId) { [weak self] in
      self?.views.removeValue(forKey: viewId)
    }
    views[viewId] = view
    return view
  }

  func view(for id: Int64) -> PreviewPlatformView? {
    views[id]
  }
}
