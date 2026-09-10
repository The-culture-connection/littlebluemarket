import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import '../../models/models.dart';
import '../repositories/dev_error_sink.dart';
import '../repositories/repositories.dart';
import 'firestore_errors.dart';
import 'mappers.dart';

/// `feedback/{id}` plus `feedback/{uid}/{id}.png` in Storage.
///
/// The screenshot's download URL is written onto the document, so the admin
/// screen and the admin website show it without a second lookup.
class FirestoreFeedbackRepository implements FeedbackRepository {
  FirestoreFeedbackRepository({
    required FirebaseFirestore firestore,
    required FirebaseStorage storage,
    required this.uid,
  }) : _db = firestore,
       _storage = storage;

  final FirebaseFirestore _db;
  final FirebaseStorage _storage;
  final String? uid;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('feedback');

  @override
  Future<void> submit(NewFeedback draft, {List<int>? screenshot}) =>
      guardFirestore(() async {
        final me = uid;
        if (me == null) {
          throw const PermissionException('Sign in to send a note.');
        }
        if (!draft.isValid) {
          throw const ValidationException('Say what happened, in a few words.');
        }
        final doc = _col.doc();
        String? url;
        if (screenshot != null && draft.includeScreenshot) {
          // Best effort. A failed upload must not lose the note: the words
          // are the report, the picture is a bonus, and this used to throw
          // and drop the whole thing.
          try {
            final ref = _storage.ref('feedback/$me/${doc.id}.png');
            await ref.putData(
              Uint8List.fromList(screenshot),
              SettableMetadata(contentType: 'image/png'),
            );
            url = await ref.getDownloadURL();
          } on Object catch (error) {
            DevErrorSink.report(
              error,
              StackTrace.current,
              'feedback screenshot',
            );
          }
        }
        await doc.set({
          'uid': me,
          'kind': draft.kind.value,
          'text': draft.text.trim(),
          'route': draft.route,
          'platform': defaultTargetPlatform.name,
          'status': FeedbackStatus.open.value,
          'fromName': draft.fromName,
          'isGuest': draft.isGuest,
          'screenshotUrl': url,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }, operation: 'firestore feedback submit');

  @override
  Stream<List<FeedbackItem>> watchAll({int limit = 100}) => _col
      .orderBy('createdAt', descending: true)
      .limit(limit)
      .snapshots()
      .map(
        (snapshot) => [
          for (final doc in snapshot.docs)
            FirestoreMappers.feedback(doc.id, doc.data()),
        ],
      );

  @override
  Future<void> setStatus(String id, FeedbackStatus status) =>
      guardFirestore(() async {
        await _col.doc(id).update({
          'status': status.value,
          'statusAt': FieldValue.serverTimestamp(),
        });
      }, operation: 'firestore feedback setStatus');
}
