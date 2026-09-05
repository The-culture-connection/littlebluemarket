import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth/auth_service.dart';
import 'firebase/firebase_auth_service.dart';
import 'firebase/firebase_bootstrap.dart';
import 'firebase/firestore_catalog_repository.dart';
import 'firebase/firestore_collection_repository.dart';
import 'firebase/firestore_diagnostics_repository.dart';
import 'firebase/firestore_messaging_repository.dart';
import 'firebase/firestore_profile_repository.dart';
import 'firebase/firestore_search_repository.dart';
import 'firebase/firestore_seller_repository.dart';
import 'firebase/firestore_social_repository.dart';
import 'shopify/commerce_proxy_repository.dart';
import 'shopify/fulfillment_proxy_repository.dart';
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

/// A human label for the corner badge and the error reports:
/// `fixtures`, `live · little-blue-610e5`, `emulators · little-blue-610e5`.
final backendLabelProvider = Provider<String>((ref) {
  return switch (ref.watch(backendProvider)) {
    Backend.fixtures => 'fixtures',
    Backend.live =>
      '${useFirebaseEmulators ? 'emulators' : 'live'} · ${firebaseProjectId() ?? '?'}',
  };
});

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
  final auth = ref.watch(authServiceProvider);
  return FixtureBackend(
    store: ref.watch(fixtureStoreProvider),
    latency: ref.watch(fixtureLatencyProvider),
    auth: auth is FixtureAuthService ? auth : null,
  );
});

// Each repository resolves independently, which is the point: Firebase lands
// two PRs before the commerce proxy, and in between the app runs half live and
// half fixture without a special mode for it.

final catalogRepositoryProvider = Provider<CatalogRepository>((ref) {
  return switch (ref.watch(backendProvider)) {
    Backend.fixtures => FixtureCatalogRepository(
      ref.watch(fixtureBackendProvider),
    ),
    Backend.live => FirestoreCatalogRepository(
      firestore: ref.watch(firestoreProvider),
      functions: ref.watch(firebaseFunctionsProvider),
    ),
  };
});

final collectionRepositoryProvider = Provider<CollectionRepository>((ref) {
  return switch (ref.watch(backendProvider)) {
    Backend.fixtures => FixtureCollectionRepository(
      ref.watch(fixtureBackendProvider),
    ),
    Backend.live => FirestoreCollectionRepository(
      firestore: ref.watch(firestoreProvider),
    ),
  };
});

final searchRepositoryProvider = Provider<SearchRepository>((ref) {
  return switch (ref.watch(backendProvider)) {
    Backend.fixtures => FixtureSearchRepository(
      ref.watch(fixtureBackendProvider),
    ),
    Backend.live => FirestoreSearchRepository(
      firestore: ref.watch(firestoreProvider),
      uid: ref.watch(_uidProvider),
    ),
  };
});

final commerceRepositoryProvider = Provider<CommerceRepository>((ref) {
  return switch (ref.watch(backendProvider)) {
    Backend.fixtures => FixtureCommerceRepository(
      ref.watch(fixtureBackendProvider),
    ),
    Backend.live => CommerceProxyRepository(
      functions: ref.watch(firebaseFunctionsProvider),
      firestore: ref.watch(firestoreProvider),
      uid: ref.watch(_uidProvider),
    ),
  };
});

final socialRepositoryProvider = Provider<SocialRepository>((ref) {
  return switch (ref.watch(backendProvider)) {
    Backend.fixtures => FixtureSocialRepository(
      ref.watch(fixtureBackendProvider),
    ),
    Backend.live => FirestoreSocialRepository(
      firestore: ref.watch(firestoreProvider),
      uid: ref.watch(_uidProvider),
    ),
  };
});

final messagingRepositoryProvider = Provider<MessagingRepository>((ref) {
  return switch (ref.watch(backendProvider)) {
    Backend.fixtures => FixtureMessagingRepository(
      ref.watch(fixtureBackendProvider),
    ),
    Backend.live => FirestoreMessagingRepository(
      firestore: ref.watch(firestoreProvider),
      uid: ref.watch(_uidProvider),
    ),
  };
});

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return switch (ref.watch(backendProvider)) {
    Backend.fixtures => FixtureProfileRepository(
      ref.watch(fixtureBackendProvider),
    ),
    Backend.live => FirestoreProfileRepository(
      firestore: ref.watch(firestoreProvider),
      storage: ref.watch(firebaseStorageProvider),
      functions: ref.watch(firebaseFunctionsProvider),
      auth: ref.watch(firebaseAuthProvider),
      uid: ref.watch(_uidProvider),
    ),
  };
});

final sellerRepositoryProvider = Provider<SellerRepository>((ref) {
  return switch (ref.watch(backendProvider)) {
    Backend.fixtures => FixtureSellerRepository(
      ref.watch(fixtureBackendProvider),
    ),
    Backend.live => FirestoreSellerRepository(
      firestore: ref.watch(firestoreProvider),
      storage: ref.watch(firebaseStorageProvider),
      functions: ref.watch(firebaseFunctionsProvider),
      uid: ref.watch(_uidProvider),
    ),
  };
});

final fulfillmentRepositoryProvider = Provider<FulfillmentRepository>((ref) {
  return switch (ref.watch(backendProvider)) {
    Backend.fixtures => FixtureFulfillmentRepository(
      ref.watch(fixtureBackendProvider),
    ),
    Backend.live => FulfillmentProxyRepository(
      firestore: ref.watch(firestoreProvider),
      functions: ref.watch(firebaseFunctionsProvider),
      uid: ref.watch(_uidProvider),
    ),
  };
});

/// The dev Diagnostics screen's data. Fixture rows on the demo backend, the
/// deployed health check on the live one.
final diagnosticsRepositoryProvider = Provider<DiagnosticsRepository>((ref) {
  return switch (ref.watch(backendProvider)) {
    Backend.fixtures => FixtureDiagnosticsRepository(
      ref.watch(authServiceProvider),
      backend: ref.watch(backendLabelProvider),
    ),
    Backend.live => FirestoreDiagnosticsRepository(
      functions: ref.watch(firebaseFunctionsProvider),
      auth: ref.watch(firebaseAuthProvider),
      firestore: ref.watch(firestoreProvider),
      backend: ref.watch(backendLabelProvider),
    ),
  };
});

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

/// The signed-in uid, straight from the identity provider.
///
/// Deliberately not `currentUidProvider` from the session: the session is built
/// *out of* the repositories, so reading it here would be a cycle. This is the
/// raw auth state, which is all a repository needs to know.
final _uidProvider = Provider<String?>((ref) {
  final auth = ref.watch(authServiceProvider);
  return ref.watch(_authUserProvider).value?.uid ?? auth.currentUser?.uid;
});

final _authUserProvider = StreamProvider<AuthUser?>((ref) {
  return ref.watch(authServiceProvider).authStateChanges();
});
