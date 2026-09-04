import 'package:firebase_core/firebase_core.dart';

/// Placeholder. **Replaced wholesale by `flutterfire configure`.**
///
/// Run this once, from the project root, signed in to the Firebase account
/// that owns the project:
///
/// ```
/// dart pub global activate flutterfire_cli
/// flutterfire configure --project=little-blue-cart-dev
/// ```
///
/// That overwrites this file and writes `android/app/google-services.json` and
/// `ios/Runner/GoogleService-Info.plist`. All three are safe to commit: they
/// hold the Web API key and project identifiers, which are public by design.
/// They identify the project; they do not authorise anything. Security comes
/// from the Firestore rules and App Check, not from keeping them secret.
///
/// This deliberately throws rather than returning empty options, because a
/// Firebase app initialised with placeholder credentials fails later, further
/// from the cause, and much more confusingly.
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    throw UnsupportedError(
      'Firebase is not configured yet.\n'
      '\n'
      'Run:  flutterfire configure --project=little-blue-cart-dev\n'
      '\n'
      'That regenerates lib/firebase_options.dart with the real values. Until '
      'then the app runs on the fixture backend, which is the default: use '
      '--dart-define=LBM_BACKEND=live only after configuring.',
    );
  }
}
