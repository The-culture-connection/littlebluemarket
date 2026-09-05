import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/auth/auth_service.dart';
import '../data/providers.dart';
import '../data/repositories/dev_error_sink.dart';
import '../data/repositories/repositories.dart';
import '../models/models.dart';

/// Who is using the app.
///
/// Sealed over three states rather than a boolean, because there are genuinely
/// three: browsing without an account, holding an account with no profile yet,
/// and being a member. The middle one is what a `bool isGuest` could not say,
/// and it is exactly where someone lands between verifying a code and finishing
/// setup.
@immutable
sealed class Session {
  const Session();

  String? get uid;
}

/// Browsing without a profile. Can see the whole market, cannot buy, post,
/// message, or enter the community.
@immutable
final class GuestSession extends Session {
  const GuestSession({this.uid});

  /// Guests get an anonymous uid, so security rules can require one and a cart
  /// built before signing up survives the upgrade.
  @override
  final String? uid;
}

/// Authenticated, but with no profile document yet.
@immutable
final class OnboardingSession extends Session {
  const OnboardingSession({required this.uid, required this.email});

  @override
  final String uid;
  final String email;
}

@immutable
final class MemberSession extends Session {
  const MemberSession({
    required this.uid,
    required this.profile,
    this.emailVerified = false,
  });

  @override
  final String uid;
  final Person profile;

  /// Whether the address has been confirmed. Until it has, linking a shop
  /// customer or claiming a vendor is refused server-side, so the app says so
  /// before the person hits that wall.
  final bool emailVerified;

  /// Drives the seller half of Edit Profile, the storefront, and revenue.
  ///
  /// The session builds [profile] with `isSeller` taken from the token's
  /// `seller` claim, which is what rules and callables actually check. The
  /// document field is only a display mirror for *other* people's profiles.
  bool get isSeller => profile.isSeller;
}

class SessionNotifier extends StreamNotifier<Session> {
  /// Accounts this run has already asked the backend to link. Once per
  /// account per launch: the backend is idempotent, but a session stream that
  /// re-emits on every profile change must not re-call it each time.
  final _linkAttempted = <String>{};

  /// Accounts whose token was refreshed once because the profile said seller
  /// and the token did not. Once, so a fixture backend cannot loop.
  final _reloadedFor = <String>{};

  @override
  Stream<Session> build() {
    final auth = ref.watch(authServiceProvider);
    final profiles = ref.watch(profileRepositoryProvider);

    return auth.authStateChanges().switchMap((user) {
      if (user == null) return Stream.value(const GuestSession());
      if (user.isAnonymous) return Stream.value(GuestSession(uid: user.uid));

      // The profile is watched, not fetched once, so an edit made on the Edit
      // Profile screen reaches every screen that shows the current user.
      return profiles.watchPerson(user.uid).map<Session>((person) {
        if (person == null) {
          return OnboardingSession(uid: user.uid, email: user.email ?? '');
        }

        _linkOnce(user, person, profiles);
        _repairSellerDrift(user, person);

        return MemberSession(
          uid: user.uid,
          // Seller status is the token's claim, not the document's field.
          profile: person.copyWith(isSeller: user.isSeller),
          emailVerified: user.emailVerified,
        );
      });
    });
  }

  /// A verified account that the store has never heard of gets linked: past
  /// orders backfilled, vendor id recorded. Fire-and-forget; a failure is
  /// reported to the dev sink and retried on the next launch.
  void _linkOnce(AuthUser user, Person person, ProfileRepository profiles) {
    if (!user.emailVerified || person.isLinked) return;
    if (!_linkAttempted.add(user.uid)) return;
    unawaited(
      profiles.linkStoreAccounts().catchError((Object error, StackTrace stack) {
        DevErrorSink.report(error, stack, 'callable linkAccounts (auto)');
        return const LinkResult();
      }),
    );
  }

  /// The profile document says seller but the token does not: a grant landed
  /// while this token was in the pocket. One forced refresh closes the gap.
  void _repairSellerDrift(AuthUser user, Person person) {
    if (!person.isSeller || user.isSeller) return;
    if (!_reloadedFor.add(user.uid)) return;
    unawaited(_auth.reloadUser().catchError((Object _) => null));
  }

  AuthService get _auth => ref.read(authServiceProvider);

  /// Asks the provider whether anything changed about this account — the
  /// email got verified, a claim was granted. The session updates itself
  /// through the auth stream; the return value is for the screen that asked.
  Future<AuthUser?> reloadUser() => _auth.reloadUser();

  Future<void> signUp({required String email, required String password}) =>
      _auth.signUpWithPassword(email: email, password: password);

  Future<void> signInWithPassword({
    required String email,
    required String password,
  }) => _auth.signInWithPassword(email: email, password: password);

  Future<void> sendEmailVerification() => _auth.sendEmailVerification();

  Future<void> sendPasswordReset(String email) =>
      _auth.sendPasswordReset(email);

  Future<void> continueAsGuest() => _auth.continueAsGuest();

  Future<void> signOut() => _auth.signOut();

  /// Writes the profile that turns an [OnboardingSession] into a
  /// [MemberSession].
  Future<void> createProfile(ProfileEdit edit) async {
    await ref.read(profileRepositoryProvider).updateProfile(edit);
  }

  /// Demo and test shortcut. Real sign-in goes through [signInWithPassword].
  void signIn() {
    final auth = _auth;
    if (auth is FixtureAuthService) {
      auth.signInAsDemoUser();
    }
  }
}

final sessionProvider = StreamNotifierProvider<SessionNotifier, Session>(
  SessionNotifier.new,
);

/// True while the person has no profile — a guest, or mid-onboarding.
///
/// Keeps its exact name and type from the prototype so every gated affordance
/// compiles unchanged.
final isGuestProvider = Provider<bool>(
  (ref) => ref.watch(sessionProvider).value is! MemberSession,
);

final currentUidProvider = Provider<String?>(
  (ref) => ref.watch(sessionProvider).value?.uid,
);

/// The signed-in person, or null. This is what replaces `Fx.me`.
final meProvider = Provider<Person?>((ref) {
  final session = ref.watch(sessionProvider).value;
  return session is MemberSession ? session.profile : null;
});

final isSellerProvider = Provider<bool>((ref) {
  final session = ref.watch(sessionProvider).value;
  return session is MemberSession && session.isSeller;
});

/// The theme override, held apart from [Session].
///
/// It used to live on the session, which meant the router listened to it and
/// re-ran its redirect every time someone toggled dark mode. It is a display
/// preference and has nothing to do with identity.
///
/// Not yet persisted across launches — that needs shared_preferences, which
/// would be the app's first plugin with native code.
class ThemeModeNotifier extends Notifier<Brightness?> {
  @override
  Brightness? build() => null;

  void set(Brightness? brightness) => state = brightness;
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, Brightness?>(
  ThemeModeNotifier.new,
);

extension _SwitchMap<T> on Stream<T> {
  /// Like `asyncExpand`, but it cancels the previous inner subscription rather
  /// than waiting for it to finish.
  ///
  /// `asyncExpand` deadlocks here. The inner stream is a live profile watch
  /// that never completes, so once someone is signed in the auth stream's next
  /// event -- a sign-out -- would never be reached, and the app would show a
  /// signed-out user their old profile indefinitely. A test caught it.
  Stream<R> switchMap<R>(Stream<R> Function(T value) convert) {
    late StreamController<R> controller;
    StreamSubscription<T>? outer;
    StreamSubscription<R>? inner;

    controller = StreamController<R>(
      onListen: () {
        outer = listen(
          (value) {
            // Cancelling is enough: Dart guarantees no further events from a
            // cancelled subscription, so a stale profile cannot arrive late.
            inner?.cancel();
            inner = convert(
              value,
            ).listen(controller.add, onError: controller.addError);
          },
          onError: controller.addError,
          onDone: controller.close,
        );
      },
      onCancel: () async {
        await inner?.cancel();
        await outer?.cancel();
      },
    );
    return controller.stream;
  }
}
