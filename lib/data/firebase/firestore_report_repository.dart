import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../models/models.dart';
import '../repositories/repositories.dart';
import 'firestore_errors.dart';
import 'mappers.dart';

/// `reports/{id}`, written by members and read by admins; the ban itself is
/// a callable because it disables a sign-in, which only the backend can do.
class FirestoreReportRepository implements ReportRepository {
  FirestoreReportRepository({
    required FirebaseFirestore firestore,
    required FirebaseFunctions functions,
    required this.uid,
  }) : _db = firestore,
       _functions = functions;

  final FirebaseFirestore _db;
  final FirebaseFunctions _functions;
  final String? uid;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('reports');

  /// Null while signed out; blocking needs an account, so the callers here
  /// refuse rather than guess.
  String get _me {
    final id = uid;
    if (id == null) throw const PermissionException('Sign in to do that.');
    return id;
  }

  @override
  Future<void> submit(NewReport draft) => guardFirestore(() async {
    final me = uid;
    if (me == null) throw const PermissionException('Sign in to report.');
    if (!draft.isValid) {
      throw const ValidationException('Say what happened, in a few words.');
    }
    if (draft.subjectUid == me) {
      throw const ValidationException('You cannot report yourself.');
    }
    await _col.add({
      'reporterUid': me,
      'reporterName': draft.reporterName,
      'subjectUid': draft.subjectUid,
      'subjectName': draft.subjectName,
      'subjectHandle': draft.subjectHandle,
      'kind': draft.kind.value,
      'postId': draft.postId,
      'reason': draft.reason.value,
      'text': draft.text.trim(),
      'status': ReportStatus.open.value,
      'subjectBanned': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }, operation: 'firestore reports submit');

  @override
  Stream<List<Report>> watchAll({int limit = 200}) => _col
      .orderBy('createdAt', descending: true)
      .limit(limit)
      .snapshots()
      .map(
        (snapshot) => [
          for (final doc in snapshot.docs)
            FirestoreMappers.report(doc.id, doc.data()),
        ],
      );

  @override
  Future<void> resolve(String id) => guardFirestore(() async {
    await _col.doc(id).update({
      'status': ReportStatus.resolved.value,
      'resolvedAt': FieldValue.serverTimestamp(),
      'resolvedBy': uid,
    });
  }, operation: 'firestore reports resolve');

  @override
  Future<void> banUser(String uid, {String? reportId, String? reason}) =>
      guardFirestore(() async {
        await _functions
            .httpsCallable(
              'adminBanUser',
              options: HttpsCallableOptions(
                timeout: const Duration(seconds: 120),
              ),
            )
            .call<Map<String, dynamic>>({
              'uid': uid,
              'reportId': ?reportId,
              'reason': ?reason,
            });
      }, operation: 'callable adminBanUser');

  CollectionReference<Map<String, dynamic>> get _myBlocks =>
      _db.collection('users').doc(_me).collection('blocks');

  @override
  Stream<Set<String>> watchBlocked() {
    final me = uid;
    if (me == null) return Stream.value(const {});
    return _db
        .collection('users')
        .doc(me)
        .collection('blocks')
        .snapshots()
        .map((snapshot) => {for (final doc in snapshot.docs) doc.id})
        .guarded(operation: 'firestore users/{uid}/blocks');
  }

  @override
  Future<void> blockUser(String uid) => guardFirestore(() async {
    if (uid == _me) {
      throw const ValidationException('You cannot block yourself.');
    }
    await _myBlocks.doc(uid).set({'at': FieldValue.serverTimestamp()});
  }, operation: 'firestore block');

  @override
  Future<void> unblockUser(String uid) => guardFirestore(() async {
    await _myBlocks.doc(uid).delete();
  }, operation: 'firestore unblock');

  @override
  Future<void> unbanUser(String uid) => guardFirestore(() async {
    await _functions
        .httpsCallable('adminUnbanUser')
        .call<Map<String, dynamic>>({'uid': uid});
  }, operation: 'callable adminUnbanUser');
}
