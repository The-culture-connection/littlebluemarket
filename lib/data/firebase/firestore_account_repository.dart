import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../models/models.dart';
import '../repositories/repositories.dart';
import 'firestore_errors.dart';
import 'mappers.dart';

/// Requests to delete an account or the data behind it.
///
/// The request goes through a callable rather than straight to Firestore,
/// because the page that files it has to work for someone who is not signed
/// in. Nothing here deletes anything: a person reads the list and acts.
class FirestoreAccountRepository implements AccountRepository {
  FirestoreAccountRepository({
    required FirebaseFirestore firestore,
    required FirebaseFunctions functions,
  }) : _db = firestore,
       _functions = functions;

  final FirebaseFirestore _db;
  final FirebaseFunctions _functions;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('deletionRequests');

  @override
  Future<void> requestDeletion(NewDeletionRequest draft) => guardFirestore(
    () async {
      if (!draft.isValid) {
        throw const ValidationException(
          'Check the email address and try again.',
          field: 'email',
        );
      }
      await _functions
          .httpsCallable(
            'requestAccountDeletion',
            options: HttpsCallableOptions(timeout: const Duration(seconds: 60)),
          )
          .call<Map<String, dynamic>>({
            'email': draft.email.trim(),
            'scope': draft.scope.value,
            'note': draft.note.trim(),
          });
    },
    operation: 'callable requestAccountDeletion',
  );

  @override
  Stream<List<DeletionRequest>> watchDeletionRequests({int limit = 100}) => _col
      .orderBy('createdAt', descending: true)
      .limit(limit)
      .snapshots()
      .map(
        (snapshot) => [
          for (final doc in snapshot.docs)
            FirestoreMappers.deletionRequest(doc.id, doc.data()),
        ],
      );

  @override
  Future<void> setDeletionStatus(String id, DeletionStatus status) =>
      guardFirestore(() async {
        await _col.doc(id).update({
          'status': status.value,
          'handledAt': FieldValue.serverTimestamp(),
        });
      }, operation: 'firestore deletionRequests setStatus');

  @override
  Future<int> deleteAccountNow({
    required String uid,
    required String requestId,
    required bool keepAccount,
  }) => guardFirestore(() async {
    final result = await _functions
        .httpsCallable(
          'adminDeleteAccount',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 310)),
        )
        .call<Map<String, dynamic>>({
          'uid': uid,
          'requestId': requestId,
          'keepAccount': keepAccount,
        });
    return FirestoreMappers.integer(result.data['postsRemoved']);
  }, operation: 'callable adminDeleteAccount');
}
