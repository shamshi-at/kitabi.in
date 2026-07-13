import Flutter
import UIKit
import flutter_local_notifications

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Required by flutter_local_notifications so its background isolate (the
    // reading timer's "still reading?" check-in actions) can reach other
    // plugins — without this, background notification-action handling on iOS
    // silently no-ops. Must be set before GeneratedPluginRegistrant.register.
    FlutterLocalNotificationsPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }
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
