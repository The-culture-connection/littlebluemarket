import Flutter
import UIKit
import FirebaseCore
import FirebaseMessaging

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  // Push (CP-P7). Apple hands the push token to these two callbacks. Firebase
  // normally picks it up on its own by swizzling them, but when that quietly
  // does not happen the app has no token and "Send me a test notification"
  // says no phone is registered. So: say in the console what Apple said, and
  // hand the token to Firebase ourselves (harmless when swizzling also did).
  // In Xcode's console (or `flutter run`'s output) look for "LBM push:".
  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    NSLog("LBM push: APNs token received (%d bytes)", deviceToken.count)
    if FirebaseApp.app() != nil {
      Messaging.messaging().apnsToken = deviceToken
    } else {
      NSLog("LBM push: Firebase not configured yet when the APNs token arrived; the next registration will carry it")
    }
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    NSLog("LBM push: APNs registration FAILED: %@", error.localizedDescription)
    super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
  }
}
