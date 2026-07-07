import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Register plugins against the app delegate itself (NOT the implicit engine's
    // registry). This is the FlutterFire-canonical setup and it matters for push:
    // the firebase_messaging plugin receives the APNs device token via UIApplication
    // delegate callback forwarding (addApplicationDelegate:), which only happens when
    // plugins are registered with the FlutterAppDelegate. Registering against
    // engineBridge.pluginRegistry (the implicit-engine pattern) left the APNs token
    // stranded — getAPNSToken() stayed null forever, so no FCM token was ever issued
    // on iOS while Android (no APNs dependency) worked fine.
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
