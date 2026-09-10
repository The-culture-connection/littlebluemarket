import 'dart:io' show Platform;

/// Phones and desktops: straight from `dart:io`.
bool get platformIsIOS => Platform.isIOS;
bool get platformIsAndroid => Platform.isAndroid;
String get platformName => Platform.operatingSystem;

/// True when the process environment carries [key]. `flutter test` sets
/// `FLUTTER_TEST`, which is how the app knows to stay on fixtures under test.
bool environmentHas(String key) {
  try {
    return Platform.environment.containsKey(key);
  } catch (_) {
    return false;
  }
}
