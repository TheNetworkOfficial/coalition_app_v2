import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var videoProxyChannel: VideoProxyChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    let didFinish = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    if let controller = window?.rootViewController as? FlutterViewController {
      videoProxyChannel = VideoProxyChannel(messenger: controller.binaryMessenger)
    }
    return didFinish
  }
}
