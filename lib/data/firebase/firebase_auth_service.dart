import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;

import '../auth/auth_service.dart';
import '../repositories/dev_error_sink.dart';
import '../repositories/repositories.dart';

/// Identity, backed by Firebase Auth.
///
/// Email and password.
///
/// Not what the prototype drew — that was a six-digit code — but Firebase does
/// not issue codes, only links, and the link had to travel through Dynamic
/// Links, which shut down in August 2025. Password auth is the one option that
/// needs no email infrastructure of our own: Firebase sends the reset mail
/// itself, and the verification mail too when ours is not set up.
///
/// The account here is not the shop account. Someone who already buys on the
/// website signs up with the same address and a Cloud Function links their
/// existing customer record once the address is **verified** — so to them this
/// still reads as logging in.
class FirebaseAuthService implements AuthService {
  FirebaseAuthService(this._auth, {FirebaseFunctions? functions})
    : _functions = functions;

  final fb.FirebaseAuth _auth;

  /// Where the branded confirmation mail is sent from. Null in tests that
  /// build the service without Cloud Functions; Firebase's own mail then.
  final FirebaseFunctions? _functions;

  /// The Cloud Function that sends the branded mail (Stage 16).
  static const _sendVerificationFunction = 'sendVerificationEmail';

  /// The branded mail first, Firebase's own as the fallback.
  ///
  /// `sendVerificationEmail` mints the same Firebase link and sends it in
  /// the app's own message, from the app's own address, to a page in the
  /// app's own style. It refuses while SMTP is not set up on the project,
  /// when the mail server does, or when it is not deployed yet, and for all
  /// of those the plain Firebase mail goes out instead, so an account is
  /// never left without a link. The dev strip still hears why. The one
  /// refusal that is not a fallback is the 30-second throttle, which the
  /// screen shows as "give it a minute".
  Future<void> _sendVerification(fb.User user) async {
    final functions = _functions;
    if (functions != null) {
      try {
        await functions.httpsCallable(_sendVerificationFunction).call<void>();
        return;
      } on FirebaseFunctionsException catch (error) {
        if (error.code == 'resource-exhausted') {
          throw const RateLimitException();
        }
        DevErrorSink.report(
          error,
          null,
          '$_sendVerificationFunction ${error.code}: ${error.message}',
        );
      } catch (error, stack) {
        DevErrorSink.report(error, stack, _sendVerificationFunction);
      }
    }
    await user.sendEmailVerification();
  }

  AuthUser? _wrap(
    fb.User? user, {
    bool isSeller = false,
    bool isAdmin = false,
  }) {
    if (user == null) return null;
    return AuthUser(
      uid: user.uid,
      email: user.email,
      isAnonymous: user.isAnonymous,
      emailVerified: user.emailVerified,
      isSeller: isSeller,
      isAdmin: isAdmin,
    );
  }

  /// The user plus the `seller` claim from the token the phone is holding.
  /// The cached token is read (no network), so this is cheap.
  Future<AuthUser?> _wrapWithClaims(fb.User? user) async {
    if (user == null) return null;
    var isSeller = false;
    var isAdmin = false;
    try {
      final token = await user.getIdTokenResult();
      isSeller = token.claims?['seller'] == true;
      isAdmin = token.claims?['admin'] == true;
    } catch (_) {
      // Offline, or a token that could not be read: not a seller for now.
    }
    return _wrap(user, isSeller: isSeller, isAdmin: isAdmin);
  }

  @override
  AuthUser? get currentUser => _wrap(_auth.currentUser);

  /// Token-driven, not sign-in-driven.
  ///
  /// `authStateChanges` only fires when the *user* changes. A verified email
  /// or a granted `seller` claim changes the token, not the user, so nothing
  /// downstream would ever hear about it. `idTokenChanges` fires for both,
  /// and for the forced refresh [reloadUser] makes. The `distinct` keeps the
  /// hourly silent refresh from re-emitting an identical user.
  @override
  Stream<AuthUser?> authStateChanges() =>
      _auth.idTokenChanges().asyncMap(_wrapWithClaims).distinct(_sameUser);

  static bool _sameUser(AuthUser? a, AuthUser? b) =>
      a?.uid == b?.uid &&
      a?.emailVerified == b?.emailVerified &&
      a?.isSeller == b?.isSeller &&
      a?.isAdmin == b?.isAdmin &&
      a?.isAnonymous == b?.isAnonymous;

  @override
  Future<AuthUser?> reloadUser() async {
    final user = _auth.currentUser;
    if (user == null) return null;
    try {
      // `reload` re-reads the account (emailVerified lives there); the forced
      // token refresh picks up any claim granted since the last mint. Both
      // fan out through idTokenChanges, so the session updates itself.
      await user.reload();
      await user.getIdToken(true);
      return _wrapWithClaims(_auth.currentUser);
    } on fb.FirebaseAuthException catch (error) {
      throw _translate(error);
    }
  }

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

      // Fire and forget. A failure here must not strand an account that
      // already exists; the account is made either way, and the screen
      // offers a resend.
      unawaited(_sendVerification(result.user!).catchError((_) {}));
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
      await _sendVerification(user);
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
    DevErrorSink.report(error, null, 'auth ${error.code}');
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
      'user-disabled' => const PermissionException(
        'This account has been suspended by Little Blue Market. If you think '
        'that is a mistake, write to us from the website.',
      ),
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
