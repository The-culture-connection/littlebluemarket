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

  /// Passwordless: the store's customer accounts are code-based, and no
  /// password of theirs could be verified here anyway.
  Future<void> sendSignInCode(String email);

  /// Returns the signed-in user. Throws [ValidationException] on a bad code.
  Future<AuthUser> confirmCode({required String email, required String code});

  /// Anonymous sign-in, so a guest still has a uid.
  Future<void> continueAsGuest();

  /// Upgrades the anonymous account in place, preserving anything already
  /// attached to that uid — notably a cart built before signing up, which the
  /// prototype's "Buy, sign up" flow silently threw away.
  Future<void> linkGuestToEmail({required String email, required String code});

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

  /// Any six digits are accepted, as in the prototype. The real service
  /// verifies for real.
  static final _codePattern = RegExp(r'^\d{6}$');

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

  @override
  Future<void> sendSignInCode(String email) async {
    if (!email.contains('@') || !email.contains('.')) {
      throw const ValidationException('That email does not look right', field: 'email');
    }
  }

  @override
  Future<AuthUser> confirmCode({
    required String email,
    required String code,
  }) async {
    if (!_codePattern.hasMatch(code)) {
      throw const ValidationException('That code is not right', field: 'code');
    }
    final user = AuthUser(uid: demoUid, email: email, emailVerified: true);
    _emit(user);
    return user;
  }

  @override
  Future<void> continueAsGuest() async {
    _emit(const AuthUser(uid: 'guest', isAnonymous: true));
  }

  @override
  Future<void> linkGuestToEmail({
    required String email,
    required String code,
  }) async {
    await confirmCode(email: email, code: code);
  }

  @override
  Future<void> signOut() async => _emit(null);

  /// Test and demo shortcut: land straight in a signed-in session.
  void signInAsDemoUser() {
    _emit(AuthUser(uid: demoUid, email: 'demo@example.com', emailVerified: true));
  }

  void dispose() => _controller.close();
}
