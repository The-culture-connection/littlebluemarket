import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../models/models.dart';
import '../repositories/repositories.dart';
import 'firestore_errors.dart';
import 'mappers.dart';

/// The backend health check and the token facts, from the phone's side.
class FirestoreDiagnosticsRepository implements DiagnosticsRepository {
  FirestoreDiagnosticsRepository({
    required FirebaseFunctions functions,
    required FirebaseAuth auth,
    required FirebaseFirestore firestore,
    required this.backend,
  }) : _functions = functions,
       _auth = auth,
       _db = firestore;

  final FirebaseFunctions _functions;
  final FirebaseAuth _auth;
  final FirebaseFirestore _db;
  final String backend;

  @override
  Future<HealthReport> healthCheck() => guardFirestore(() async {
    final result = await _functions
        .httpsCallable(
          'diagnosticsHealthCheck',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 70)),
        )
        .call<Map<String, dynamic>>(const {});
    final data = result.data;
    final rows = data['checks'];
    return HealthReport(
      project: FirestoreMappers.str(data['project'], '?'),
      at: DateTime.tryParse(FirestoreMappers.str(data['at'])) ?? DateTime.now(),
      checks: [
        if (rows is List)
          for (final row in rows)
            if (row is Map)
              HealthCheckItem(
                name: FirestoreMappers.str(row['name'], '?'),
                ok: FirestoreMappers.boolean(row['ok']),
                summary: FirestoreMappers.str(row['summary']),
                fix: row['fix'] is String ? row['fix'] as String : null,
              ),
      ],
    );
  }, operation: 'callable diagnosticsHealthCheck');

  @override
  Future<AuthFacts> authFacts() => guardFirestore(() async {
    final user = _auth.currentUser;
    if (user == null) return AuthFacts(backend: backend);

    // Claims come from the token the phone is holding, which is what rules and
    // callables actually see — a stale one is exactly the thing worth showing.
    final token = await user.getIdTokenResult();
    final claims = token.claims ?? const {};

    var linked = false;
    try {
      final doc = await _db.collection('users').doc(user.uid).get();
      linked = doc.data()?['linkedAt'] != null;
    } catch (_) {
      // Rules or offline; the fact simply reads false.
    }

    return AuthFacts(
      backend: backend,
      uid: user.uid,
      email: user.email,
      isAnonymous: user.isAnonymous,
      emailVerified: user.emailVerified,
      isSeller: claims['seller'] == true,
      isAdmin: claims['admin'] == true,
      isLinked: linked,
    );
  }, operation: 'auth getIdTokenResult');

  @override
  Future<void> claimAdmin() => guardFirestore(() async {
    await _functions
        .httpsCallable('adminClaimSelf')
        .call<Map<String, dynamic>>(const {});
    // The claim lives on the token; force a fresh one so the facts card and
    // the next admin call both see it without a sign-out.
    await _auth.currentUser?.getIdToken(true);
  }, operation: 'callable adminClaimSelf');

  @override
  Future<int> syncCollections() => guardFirestore(() async {
    final result = await _functions
        .httpsCallable(
          'adminSyncCollections',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 120)),
        )
        .call<Map<String, dynamic>>(const {});
    return FirestoreMappers.integer(result.data['count']);
  }, operation: 'callable adminSyncCollections');

  @override
  Future<String> setSellerVendor({
    required String uid,
    required String vendorName,
  }) => guardFirestore(() async {
    final result = await _functions
        .httpsCallable('adminSetSellerVendor')
        .call<Map<String, dynamic>>({'uid': uid, 'vendorName': vendorName});
    return FirestoreMappers.str(result.data['previous']);
  }, operation: 'callable adminSetSellerVendor');

  @override
  Future<BackfillProgress> backfillCatalog({bool reset = false}) =>
      guardFirestore(() async {
        final result = await _functions
            .httpsCallable(
              'adminBackfillCatalog',
              options: HttpsCallableOptions(
                timeout: const Duration(seconds: 310),
              ),
            )
            .call<Map<String, dynamic>>({'reset': reset});
        final data = result.data;
        return BackfillProgress(
          processed: FirestoreMappers.integer(data['processed']),
          total: FirestoreMappers.integer(data['total']),
          done: FirestoreMappers.boolean(data['done']),
        );
      }, operation: 'callable adminBackfillCatalog');
}
