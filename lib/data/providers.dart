import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth/auth_service.dart';
import 'firebase/firebase_auth_service.dart';
import 'firebase/firebase_bootstrap.dart';
import 'fixtures/fixture_repositories.dart';
import 'fixtures/fixture_store.dart';
import 'repositories/repositories.dart';

/// Which backend the app is talking to.
///
/// Selected at build time:
///
/// ```
/// flutter run                                  # fixtures
/// flutter run --dart-define=LBM_BACKEND=live   # Firebase + the commerce proxy
/// ```
enum Backend { fixtures, live }

const _backendFlag = String.fromEnvironment('LBM_BACKEND');

final backendProvider = Provider<Backend>(
  (ref) => _backendFlag == 'live' ? Backend.live : Backend.fixtures,
);

/// How slow the demo backend pretends to be.
///
/// Non-zero in debug so loading states are actually seen and designed, and
/// zero everywhere else — a widget test that pays this on every read turns
/// `pumpAndSettle` into a stall.
final fixtureLatencyProvider = Provider<Duration>((ref) {
  const underTest = bool.fromEnvironment('FLUTTER_TEST');
  if (underTest || !kDebugMode) return Duration.zero;
  return const Duration(milliseconds: 250);
});

final fixtureStoreProvider = Provider<FixtureStore>((ref) {
  final store = FixtureStore();
  ref.onDispose(store.dispose);
  return store;
});

final fixtureBackendProvider = Provider<FixtureBackend>((ref) {
  return FixtureBackend(
    store: ref.watch(fixtureStoreProvider),
    latency: ref.watch(fixtureLatencyProvider),
  );
});

// Each repository resolves independently, which is the point: Firebase lands
// two PRs before the commerce proxy, and in between the app runs half live and
// half fixture without a special mode for it.
//
// Every `Backend.live` arm throws until its implementation lands. That is
// deliberate — a silent fall-through to fixtures in a live build would be a
// much worse bug than a loud one.

final catalogRepositoryProvider = Provider<CatalogRepository>((ref) {
  return switch (ref.watch(backendProvider)) {
    Backend.fixtures => FixtureCatalogRepository(ref.watch(fixtureBackendProvider)),
    Backend.live => throw _notWired('CatalogRepository'),
  };
});

final searchRepositoryProvider = Provider<SearchRepository>((ref) {
  return switch (ref.watch(backendProvider)) {
    Backend.fixtures => FixtureSearchRepository(ref.watch(fixtureBackendProvider)),
    Backend.live => throw _notWired('SearchRepository'),
  };
});

final commerceRepositoryProvider = Provider<CommerceRepository>((ref) {
  return switch (ref.watch(backendProvider)) {
    Backend.fixtures => FixtureCommerceRepository(ref.watch(fixtureBackendProvider)),
    Backend.live => throw _notWired('CommerceRepository'),
  };
});

final socialRepositoryProvider = Provider<SocialRepository>((ref) {
  return switch (ref.watch(backendProvider)) {
    Backend.fixtures => FixtureSocialRepository(ref.watch(fixtureBackendProvider)),
    Backend.live => throw _notWired('SocialRepository'),
  };
});

final messagingRepositoryProvider = Provider<MessagingRepository>((ref) {
  return switch (ref.watch(backendProvider)) {
    Backend.fixtures => FixtureMessagingRepository(ref.watch(fixtureBackendProvider)),
    Backend.live => throw _notWired('MessagingRepository'),
  };
});

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return switch (ref.watch(backendProvider)) {
    Backend.fixtures => FixtureProfileRepository(ref.watch(fixtureBackendProvider)),
    Backend.live => throw _notWired('ProfileRepository'),
  };
});

final fulfillmentRepositoryProvider = Provider<FulfillmentRepository>((ref) {
  return switch (ref.watch(backendProvider)) {
    Backend.fixtures =>
      FixtureFulfillmentRepository(ref.watch(fixtureBackendProvider)),
    Backend.live => throw _notWired('FulfillmentRepository'),
  };
});

BackendException _notWired(String name) => BackendException(
  '$name has no live implementation yet. '
  'Run without --dart-define=LBM_BACKEND=live, or wire it up.',
  code: 'not-wired',
);

/// Identity.
///
/// Separate from the repositories because it is not a repository: it is the
/// thing that tells them who is asking.
final authServiceProvider = Provider<AuthService>((ref) {
  return switch (ref.watch(backendProvider)) {
    Backend.fixtures => () {
      final service = FixtureAuthService();
      ref.onDispose(service.dispose);
      return service;
    }(),
    Backend.live => FirebaseAuthService(ref.watch(firebaseAuthProvider)),
  };
});
