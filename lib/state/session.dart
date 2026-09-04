import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether the person using the app has a profile.
///
/// Guests can browse the whole marketplace. Buying, posting, reviewing,
/// messaging and the community all need a profile — see `requireProfile`.
enum AuthState { guest, signedIn }

@immutable
class Session {
  const Session({required this.auth, this.themeMode});

  final AuthState auth;

  /// `null` follows the system setting, which is the default.
  final Brightness? themeMode;

  bool get isGuest => auth == AuthState.guest;

  Session copyWith({AuthState? auth, Brightness? themeMode, bool clearTheme = false}) =>
      Session(
        auth: auth ?? this.auth,
        themeMode: clearTheme ? null : (themeMode ?? this.themeMode),
      );
}

class SessionNotifier extends Notifier<Session> {
  @override
  Session build() => const Session(auth: AuthState.guest);

  void signIn() => state = state.copyWith(auth: AuthState.signedIn);

  void continueAsGuest() => state = state.copyWith(auth: AuthState.guest);

  void signOut() => state = state.copyWith(auth: AuthState.guest);

  void setBrightness(Brightness? b) =>
      state = b == null ? state.copyWith(clearTheme: true) : state.copyWith(themeMode: b);
}

final sessionProvider = NotifierProvider<SessionNotifier, Session>(
  SessionNotifier.new,
);

/// True when the current user is browsing without a profile.
final isGuestProvider = Provider<bool>((ref) {
  return ref.watch(sessionProvider).isGuest;
});
