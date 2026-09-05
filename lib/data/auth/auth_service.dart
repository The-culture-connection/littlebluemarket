import 'dart:async';

import 'package:flutter/foundation.dart';

import '../fixtures/fixture_data.dart';
import '../repositories/repositories.dart';

/// Who is signed in, as far as the identity provider is concerned.
///
/// Deliberately thinner than a profile: this is the account, and the profile is
/// a separate document that may not exist yet. Keeping them apart is what makes
/// "authenticated but has not finished setup" a state the app can render rather
/// than a crash.
@immutable
class AuthUser {
  const AuthUser({
    required this.uid,
    this.email,
    this.isAnonymous = false,
    this.emailVerified = false,
  });

  final String uid;
  final String? email;

  /// A guest. They get a uid so security rules can require one and so a cart
  /// built before signing up survives the upgrade.
  final bool isAnonymous;

  /// Only a verified email may be used to link an existing customer or vendor
  /// record. Linking on an unverified address would let anyone claim a
  /// stranger's order history.
  final bool emailVerified;
}

/// Identity. The one thing the app cannot be lazy about.
abstract interface class AuthService {
  Stream<AuthUser?> authStateChanges();

  AuthUser? get currentUser;

  /// Creates the account and signs in.
  ///
  /// A guest is upgraded **in place** rather than replaced, preserving
  /// anything already attached to that uid — notably a cart built before
  /// signing up, which the prototype's "Buy, sign up" flow silently threw
  /// away.
  ///
  /// The returned user is **not** email-verified. Firebase sends the
  /// verification mail itself; until the person clicks it, linking their
  /// Shopify or vendor record is refused — see [AuthUser.emailVerified].
  Future<AuthUser> signUpWithPassword({
    required String email,
    required String password,
  });

  /// Signs an existing account in.
  ///
  /// Throws [ValidationException] on a wrong password or unknown address.
  /// Modern Firebase collapses those two into one error code on purpose, so
  /// the message cannot say which — and should not try.
  Future<AuthUser> signInWithPassword({
    required String email,
    required String password,
  });

  /// Re-sends the verification mail to the signed-in account.
  Future<void> sendEmailVerification();

  /// Sends a reset link. Deliberately silent about whether the address is
  /// known: saying so turns this screen into a way to enumerate accounts.
  Future<void> sendPasswordReset(String email);

  /// Anonymous sign-in, so a guest still has a uid.
  Future<void> continueAsGuest();

  Future<void> signOut();
}

/// The demo identity provider.
///
/// [demoUid] is the one place the prototype's hardcoded user survives, and it
/// survives only on this backend. Everywhere else the current user comes from
/// the session.
class FixtureAuthService implements AuthService {
  FixtureAuthService({this.demoUid = Fx.meId, AuthUser? initialUser})
    : _user = initialUser {
    // Seed late so a listener attached immediately still sees the first value.
    scheduleMicrotask(() => _emit(_user));
  }

  final String demoUid;

  AuthUser? _user;
  final _controller = StreamController<AuthUser?>.broadcast();

  /// Firebase's own minimum. Matching it here means the fixture backend
  /// rejects exactly what the real one would.
  static const _minPasswordLength = 6;

  /// Addresses that already "exist" on this backend, so the sign-in and
  /// sign-up paths can both be exercised without Firebase.
  final _accounts = <String, String>{};

  @override
  AuthUser? get currentUser => _user;

  void _emit(AuthUser? user) {
    _user = user;
    if (!_controller.isClosed) _controller.add(user);
  }

  @override
  Stream<AuthUser?> authStateChanges() {
    late StreamController<AuthUser?> out;
    StreamSubscription<AuthUser?>? subscription;
    out = StreamController<AuthUser?>(
      onListen: () {
        out.add(_user);
        subscription = _controller.stream.listen(out.add, onError: out.addError);
      },
      onCancel: () => subscription?.cancel(),
    );
    return out.stream;
  }

  void _checkEmail(String email) {
    if (!email.contains('@') || !email.contains('.')) {
      throw const ValidationException(
        'That email does not look right',
        field: 'email',
      );
    }
  }

  @override
  Future<AuthUser> signUpWithPassword({
    required String email,
    required String password,
  }) async {
    _checkEmail(email);
    if (password.length < _minPasswordLength) {
      throw const ValidationException(
        'Use at least 6 characters',
        field: 'password',
      );
    }
    final normalized = email.trim().toLowerCase();
    if (_accounts.containsKey(normalized)) {
      throw const ValidationException(
        'That email already has an account. Sign in instead.',
        field: 'email',
      );
    }
    _accounts[normalized] = password;

    // Verified on this backend, so the fixture flow reaches the same screens
    // a verified account would. Only the real service can prove an address.
    final user = AuthUser(uid: demoUid, email: email, emailVerified: true);
    _emit(user);
    return user;
  }

  @override
  Future<AuthUser> signInWithPassword({
    required String email,
    required String password,
  }) async {
    _checkEmail(email);
    final normalized = email.trim().toLowerCase();
    final known = _accounts[normalized];

    // An address nobody signed up for still signs in, because the fixture
    // backend has no account list worth honouring — but a password shorter
    // than the real minimum is refused, so the error path stays reachable.
    if (known == null && password.length < _minPasswordLength) {
      throw const ValidationException(
        'That email and password do not match',
        field: 'password',
      );
    }
    if (known != null && known != password) {
      throw const ValidationException(
        'That email and password do not match',
        field: 'password',
      );
    }

    final user = AuthUser(uid: demoUid, email: email, emailVerified: true);
    _emit(user);
    return user;
  }

  @override
  Future<void> sendEmailVerification() async {}

  @override
  Future<void> sendPasswordReset(String email) async => _checkEmail(email);

  @override
  Future<void> continueAsGuest() async {
    _emit(const AuthUser(uid: 'guest', isAnonymous: true));
  }

  @override
  Future<void> signOut() async => _emit(null);

  /// Test and demo shortcut: land straight in a signed-in session.
  ///
  /// Real sign-in goes through [signInWithPassword].
  void signInAsDemoUser() {
    _emit(AuthUser(uid: demoUid, email: 'demo@example.com', emailVerified: true));
  }

  void dispose() => _controller.close();
}
