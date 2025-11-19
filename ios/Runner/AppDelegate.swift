import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var videoProxyChannel: VideoProxyChannel?
  private var previewFactory: PreviewPlatformViewFactory?
  private var editorChannel: EditorChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    let didFinish = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    if let controller = window?.rootViewController as? FlutterViewController {
      videoProxyChannel = VideoProxyChannel(messenger: controller.binaryMessenger)
      let factory = PreviewPlatformViewFactory()
      controller.registrar(forPlugin: "EditorPreviewView")?.register(
        factory,
        withId: "EditorPreviewView"
      )
      previewFactory = factory
      editorChannel = EditorChannel(
        messenger: controller.binaryMessenger,
        previewRegistry: factory
      )
    }
    return didFinish
  }

  override func applicationWillTerminate(_ application: UIApplication) {
    super.applicationWillTerminate(application)
    editorChannel?.releaseChannel()
    editorChannel = nil
    previewFactory = nil
  }
}
