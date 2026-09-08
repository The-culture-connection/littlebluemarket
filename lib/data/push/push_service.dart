/// Push notifications, as the app sees them.
///
/// Pure Dart on purpose, like the repositories: the live implementation
/// wraps Firebase Cloud Messaging, the fixture one does nothing, and no
/// screen knows which it has. The phone's only jobs are to register its
/// token, subscribe to its topics, show a banner while the app is open, and
/// open the right screen when a banner is tapped. Deciding who hears about
/// what is the backend's.
enum PushPermission { granted, denied, notDetermined, unsupported }

abstract interface class PushService {
  /// What the phone currently allows.
  Future<PushPermission> permissionStatus();

  /// Asks the phone. On Android 13+ and iOS this shows the system prompt.
  Future<PushPermission> requestPermission();

  /// At start-up: asks only when the phone has never been asked, so the
  /// system prompt appears once and a refusal is respected afterwards (the
  /// Notifications screen is the way back in).
  Future<void> requestPermissionIfUndecided();

  /// Registers this phone for [uid]: writes the token, follows refreshes,
  /// wires foreground banners and taps. Safe to call more than once.
  Future<void> start(String uid);

  /// Forgets this phone for [uid]. Called before sign-out, while the rules
  /// still let the owner delete their own device document.
  Future<void> stop(String uid);

  /// The audiences an announcement can address: everyone, sellers, and
  /// people joined to the directory. Idempotent.
  Future<void> setTopics({required bool seller, required bool directory});

  /// The route a tapped notification asks the app to open.
  Stream<String> get openedRoutes;

  /// "Send me a test notification": asks the backend to push to this phone.
  Future<void> sendTest();
}
