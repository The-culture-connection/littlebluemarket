import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' as fb;

import '../auth/auth_service.dart';
import '../repositories/repositories.dart';

/// Identity, backed by Firebase Auth.
///
/// Email and password.
///
/// Not what the prototype drew — that was a six-digit code — but Firebase does
/// not issue codes, only links, and the link had to travel through Dynamic
/// Links, which shut down in August 2025. Password auth is the one option that
/// needs no email infrastructure of our own: Firebase sends the verification
/// and reset mail itself.
///
/// The account here is not the shop account. Someone who already buys on the
/// website signs up with the same address and a Cloud Function links their
/// existing customer record once the address is **verified** — so to them this
/// still reads as logging in.
class FirebaseAuthService implements AuthService {
  FirebaseAuthService(this._auth);

  final fb.FirebaseAuth _auth;

  AuthUser? _wrap(fb.User? user) {
    if (user == null) return null;
    return AuthUser(
      uid: user.uid,
      email: user.email,
      isAnonymous: user.isAnonymous,
      emailVerified: user.emailVerified,
    );
  }

  @override
  AuthUser? get currentUser => _wrap(_auth.currentUser);

  @override
  Stream<AuthUser?> authStateChanges() =>
      _auth.authStateChanges().map(_wrap);

  @override
  Future<AuthUser> signUpWithPassword({
    required String email,
    required String password,
  }) async {
    final normalized = _normalize(email);
    try {
      final credential = fb.EmailAuthProvider.credential(
        email: normalized,
        password: password,
      );

      // A guest is upgraded in place rather than replaced, so the cart and
      // anything else attached to that uid survives signing up.
      final current = _auth.currentUser;
      final result = current != null && current.isAnonymous
          ? await current.linkWithCredential(credential)
          : await _auth.createUserWithEmailAndPassword(
              email: normalized,
              password: password,
            );

      final user = _wrap(result.user);
      if (user == null) {
        throw const BackendException('Sign-up returned no user');
      }

      // Fire and forget. Firebase sends this from its own domain with no
      // setup, but a failure here must not strand an account that already
      // exists — the account is made either way, and the screen offers a
      // resend.
      unawaited(result.user!.sendEmailVerification().catchError((_) {}));
      return user;
    } on fb.FirebaseAuthException catch (error) {
      throw _translate(error);
    }
  }

  @override
  Future<AuthUser> signInWithPassword({
    required String email,
    required String password,
  }) async {
    final normalized = _normalize(email);
    try {
      final result = await _auth.signInWithEmailAndPassword(
        email: normalized,
        password: password,
      );
      final user = _wrap(result.user);
      if (user == null) {
        throw const BackendException('Sign-in returned no user');
      }
      return user;
    } on fb.FirebaseAuthException catch (error) {
      throw _translate(error);
    }
  }

  @override
  Future<void> sendEmailVerification() async {
    final user = _auth.currentUser;
    if (user == null || user.emailVerified) return;
    try {
      await user.sendEmailVerification();
    } on fb.FirebaseAuthException catch (error) {
      throw _translate(error);
    }
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: _normalize(email));
    } on fb.FirebaseAuthException catch (error) {
      // Never confirm whether an address is known: that turns the reset
      // screen into a way to enumerate accounts.
      if (error.code == 'user-not-found') return;
      throw _translate(error);
    }
  }
  @override
  Future<void> continueAsGuest() async {
    // A guest still gets a uid, so security rules can require one and a cart
    // built before signing up has somewhere to live.
    if (_auth.currentUser != null) return;
    try {
      await _auth.signInAnonymously();
    } on fb.FirebaseAuthException catch (error) {
      throw _translate(error);
    }
  }

  @override
  Future<void> signOut() => _auth.signOut();

  String _normalize(String email) => email.trim().toLowerCase();

  /// Firebase's error codes become the app's exception types, so the UI never
  /// has to know which identity provider is behind the screen.
  RepositoryException _translate(fb.FirebaseAuthException error) {
    return switch (error.code) {
      'invalid-email' => const ValidationException(
        'That email does not look right',
        field: 'email',
      ),
      'invalid-action-code' ||
      'expired-action-code' ||
      'invalid-verification-code' => const ValidationException(
        'That code is not right, or it expired',
        field: 'code',
      ),
      // Firebase collapses a wrong password and an unknown address into one
      // code on purpose. Saying which would let anyone test whether an
      // address has an account here.
      'invalid-credential' ||
      'wrong-password' ||
      'user-not-found' => const ValidationException(
        'That email and password do not match',
        field: 'password',
      ),
      'weak-password' => const ValidationException(
        'Use at least 6 characters',
        field: 'password',
      ),
      'operation-not-allowed' => const BackendException(
        'Email and password sign-in is not enabled for this project',
        code: 'operation-not-allowed',
      ),
      'network-request-failed' => const OfflineException(),
      'too-many-requests' => const RateLimitException(),
      'user-disabled' => const PermissionException('This account is disabled'),
      // Someone already signed up with this email while browsing as a guest.
      // Their real account wins; the anonymous one is abandoned.
      'credential-already-in-use' ||
      'email-already-in-use' => const ValidationException(
        'That email already has an account. Sign in instead.',
        field: 'email',
      ),
      _ => BackendException(
        error.message ?? 'Sign-in failed',
        code: error.code,
      ),
    };
  }
}
