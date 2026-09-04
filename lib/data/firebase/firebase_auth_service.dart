import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' as fb;

import '../auth/auth_service.dart';
import '../repositories/repositories.dart';

/// Identity, backed by Firebase Auth.
///
/// Passwordless by necessity as well as by design: the store's customer
/// accounts are code-based, and no password of theirs could be verified here
/// anyway. Someone who already buys on the website signs in with the same
/// email and a Cloud Function links their existing customer record — so to
/// them this is logging in, not signing up.
class FirebaseAuthService implements AuthService {
  FirebaseAuthService(this._auth);

  final fb.FirebaseAuth _auth;

  /// The address the current code was sent to, so [confirmCode] can complete
  /// the email-link sign-in the platform started.
  String? _pendingEmail;

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
  Future<void> sendSignInCode(String email) async {
    final normalized = _normalize(email);
    if (!normalized.contains('@') || !normalized.contains('.')) {
      throw const ValidationException(
        'That email does not look right',
        field: 'email',
      );
    }
    _pendingEmail = normalized;

    try {
      await _auth.sendSignInLinkToEmail(
        email: normalized,
        actionCodeSettings: fb.ActionCodeSettings(
          // Set to the app's dynamic-link domain during Firebase setup; the
          // link is what carries the one-time code back.
          url: 'https://littlebluemarket.page.link/signin',
          handleCodeInApp: true,
          androidPackageName: 'com.littlebluemarket.app',
          androidInstallApp: true,
          iOSBundleId: 'com.littlebluemarket.app',
        ),
      );
    } on fb.FirebaseAuthException catch (error) {
      throw _translate(error);
    }
  }

  @override
  Future<AuthUser> confirmCode({
    required String email,
    required String code,
  }) async {
    final normalized = _normalize(email);
    try {
      final credential = fb.EmailAuthProvider.credentialWithLink(
        email: normalized,
        emailLink: code,
      );

      // An anonymous guest is upgraded in place rather than replaced, so the
      // cart and anything else attached to that uid survives signing up.
      final current = _auth.currentUser;
      final result = current != null && current.isAnonymous
          ? await current.linkWithCredential(credential)
          : await _auth.signInWithCredential(credential);

      final user = _wrap(result.user);
      if (user == null) {
        throw const BackendException('Sign-in returned no user');
      }
      _pendingEmail = null;
      return user;
    } on fb.FirebaseAuthException catch (error) {
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
  Future<void> linkGuestToEmail({
    required String email,
    required String code,
  }) => confirmCode(email: email, code: code);

  @override
  Future<void> signOut() => _auth.signOut();

  String get pendingEmail => _pendingEmail ?? '';

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
