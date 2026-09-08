import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../models/models.dart';
import '../repositories/repositories.dart';
import 'firestore_errors.dart';
import 'mappers.dart';

/// The merchant's calls. Each one is a callable that checks the admin claim
/// itself; this class only shapes the request and reads the answer back.
class FirestoreAdminRepository implements AdminRepository {
  FirestoreAdminRepository({
    required FirebaseFirestore firestore,
    required FirebaseFunctions functions,
  }) : _db = firestore,
       _functions = functions;

  final FirebaseFirestore _db;
  final FirebaseFunctions _functions;

  @override
  Future<Announcement> sendAnnouncement(NewAnnouncement draft) =>
      guardFirestore(() async {
        final result = await _functions
            .httpsCallable(
              'adminSendAnnouncement',
              options: HttpsCallableOptions(
                timeout: const Duration(seconds: 60),
              ),
            )
            .call<Map<String, dynamic>>({
              'title': draft.title.trim(),
              'body': draft.body.trim(),
              'audience': draft.audience.value,
              'route': draft.route,
            });
        final id = FirestoreMappers.str(result.data['id']);
        final doc = await _db.collection('announcements').doc(id).get();
        final data = doc.data();
        if (data == null) {
          return Announcement(
            id: id,
            title: draft.title.trim(),
            body: draft.body.trim(),
            audience: draft.audience,
            route: draft.route,
            createdAt: DateTime.now(),
          );
        }
        return FirestoreMappers.announcement(doc.id, data);
      }, operation: 'callable adminSendAnnouncement');

  @override
  Future<BackfillProgress> rebuildBuyerIndex() => guardFirestore(() async {
    final callable = _functions.httpsCallable(
      'adminBackfillBuyerIndex',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 310)),
    );
    var reset = true;
    String? cursor;
    // A page of people per call; the function keeps its own cursor, so a
    // dropped connection resumes rather than restarts.
    for (var page = 0; page < 200; page++) {
      final result = await callable.call<Map<String, dynamic>>({
        'reset': reset,
        'cursor': ?cursor,
      });
      reset = false;
      final data = result.data;
      final done = FirestoreMappers.boolean(data['done']);
      cursor = data['nextCursor'] is String ? data['nextCursor'] as String : null;
      if (done || cursor == null) {
        return BackfillProgress(
          processed: FirestoreMappers.integer(data['processed']),
          total: FirestoreMappers.integer(data['indexed']),
          done: true,
        );
      }
    }
    throw const BackendException('The rebuild did not finish in 200 pages.');
  }, operation: 'callable adminBackfillBuyerIndex');
}
