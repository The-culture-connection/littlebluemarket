import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/models.dart';
import '../repositories/repositories.dart';
import 'firestore_errors.dart';
import 'mappers.dart';

class FirestoreMessagingRepository implements MessagingRepository {
  FirestoreMessagingRepository({
    required FirebaseFirestore firestore,
    required this.uid,
  }) : _db = firestore;

  final FirebaseFirestore _db;
  final String? uid;

  String get _requireUid {
    final id = uid;
    if (id == null) throw const UnauthenticatedException();
    return id;
  }

  CollectionReference<Map<String, dynamic>> get _chatroom =>
      _db.collection('chatroom');

  CollectionReference<Map<String, dynamic>> get _conversations =>
      _db.collection('conversations');

  // ------------------------------------------------------------- chatroom

  @override
  Stream<List<Message>> watchChatroom({int limit = 100}) => _chatroom
      .orderBy('createdAt', descending: true)
      .limit(limit)
      .snapshots()
      .map(
        (snapshot) => snapshot.docs
            .map((doc) => FirestoreMappers.message(doc.id, doc.data()))
            // Queried newest-first so the limit keeps the *recent* messages,
            // then reversed, because a chat reads oldest to newest.
            .toList()
            .reversed
            .toList(),
      )
      .guarded();

  @override
  Future<void> sendToChatroom(String text) => guardFirestore(() async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    await _chatroom.add({
      'conversationId': Message.chatroomId,
      'authorId': _requireUid,
      'text': trimmed,
      'createdAt': FieldValue.serverTimestamp(),
    });
  });

  // ---------------------------------------------------------- conversations

  @override
  Stream<List<Conversation>> watchInbox() {
    final id = uid;
    if (id == null) return Stream.value(const []);

    return _conversations
        .where('participantIds', arrayContains: id)
        .orderBy('lastMessageAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map(
                (doc) =>
                    FirestoreMappers.conversation(doc.id, doc.data(), uid: id),
              )
              .toList(),
        )
        .guarded();
  }

  @override
  Future<String> conversationWith(String personId) =>
      guardFirestore(() async {
        final me = _requireUid;
        if (personId == me) {
          throw const ValidationException('You cannot message yourself');
        }

        // The id is derived from the sorted pair, so this is a lookup rather
        // than a search — and two people messaging each other at the same
        // moment cannot create two threads.
        final id = Conversation.idFor(me, personId);
        final doc = _conversations.doc(id);

        if (!(await doc.get()).exists) {
          await doc.set({
            'participantIds': [me, personId]..sort(),
            'preview': '',
            'unread': {me: 0, personId: 0},
            'lastMessageAt': FieldValue.serverTimestamp(),
            'createdAt': FieldValue.serverTimestamp(),
          });
        }
        return id;
      });

  @override
  Stream<List<Message>> watchConversation(String conversationId) =>
      _conversations
          .doc(conversationId)
          .collection('messages')
          .orderBy('createdAt')
          .limit(200)
          .snapshots()
          .map(
            (snapshot) => snapshot.docs
                .map((doc) => FirestoreMappers.message(doc.id, doc.data()))
                .toList(),
          )
          .guarded();

  @override
  Future<void> send({
    required String conversationId,
    required String text,
    String? attachedProductId,
  }) => guardFirestore(() async {
    final me = _requireUid;
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    final conversation = _conversations.doc(conversationId);
    final snapshot = await conversation.get();
    final participants = FirestoreMappers.strings(
      snapshot.data()?['participantIds'],
    );
    final other = participants.firstWhere(
      (id) => id != me,
      orElse: () => me,
    );

    // The message and the thread summary move together, so the inbox can never
    // show a preview for a message that failed to write.
    final batch = _db.batch();
    batch.set(conversation.collection('messages').doc(), {
      'conversationId': conversationId,
      'authorId': me,
      'text': trimmed,
      'attachedProductId': ?attachedProductId,
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.set(conversation, {
      'preview': trimmed,
      'lastMessageAt': FieldValue.serverTimestamp(),
      // Increment rather than set: the other side may be reading right now.
      'unread': {other: FieldValue.increment(1)},
    }, SetOptions(merge: true));
    await batch.commit();
  });

  @override
  Future<void> markRead(String conversationId) => guardFirestore(() async {
    await _conversations.doc(conversationId).set({
      'unread': {_requireUid: 0},
    }, SetOptions(merge: true));
  });
}
