import Flutter
import UIKit
import FirebaseCore
import FirebaseMessaging

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  // Push (CP-P7). What Apple said about the push token, readable from Dart
  // over the "lbm/push" channel so the dev strip can show it: on iOS 17+ the
  // Terminal does not reliably carry NSLog lines, and the app was observed
  // (2026-09-09) getting no token at all with neither callback firing, which
  // means nothing had asked Apple. So this file asks, remembers the answer,
  // and hands the token to Firebase itself.
  private static var apnsOutcome = "not asked yet"
  private static var apnsToken: Data?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    // Ask Apple for the push token now. Safe before permission is granted
    // (the token arrives silently; permission only governs banners), and
    // safe to repeat: Firebase's own request later is a no-op if this
    // answered first.
    application.registerForRemoteNotifications()
    AppDelegate.apnsOutcome = "asked Apple at launch, no answer yet"
    return result
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "LBMPush") else { return }
    let channel = FlutterMethodChannel(name: "lbm/push", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "apnsOutcome":
        result(AppDelegate.apnsOutcome)
      case "handApnsTokenToFirebase":
        // Dart asks once Firebase is certainly configured, in case the token
        // arrived before it was.
        if let token = AppDelegate.apnsToken, FirebaseApp.app() != nil {
          Messaging.messaging().apnsToken = token
          result(true)
        } else {
          result(false)
        }
      case "registerAgain":
        UIApplication.shared.registerForRemoteNotifications()
        AppDelegate.apnsOutcome = "asked Apple again from Dart, no answer yet"
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    AppDelegate.apnsToken = deviceToken
    AppDelegate.apnsOutcome = "APNs token received (\(deviceToken.count) bytes)"
    NSLog("LBM push: %@", AppDelegate.apnsOutcome)
    if FirebaseApp.app() != nil {
      Messaging.messaging().apnsToken = deviceToken
    }
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    AppDelegate.apnsOutcome = "APNs registration FAILED: \(error.localizedDescription)"
    NSLog("LBM push: %@", AppDelegate.apnsOutcome)
    super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
  }
}
