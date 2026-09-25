import 'package:flutter/foundation.dart';

import 'formatting.dart';

/// Whether a message has actually reached the server.
///
/// An optimistic send renders immediately, so without this a failed message
/// looks identical to a delivered one.
enum MessageStatus { sending, sent, failed }

/// A message, in the open chatroom or in a one-to-one thread.
///
/// One type for both: they differ only in which conversation they belong to,
/// and the open room is simply the conversation with id [chatroomId].
///
/// This replaces ChatMessage and DmMessage. Those two still back the community
/// and messaging screens and are retired when those screens move onto the
/// messaging repository.
@immutable
class Message {
  const Message({
    required this.id,
    required this.conversationId,
    required this.authorId,
    required this.createdAt,
    required this.text,
    this.attachedProductId,
    this.status = MessageStatus.sent,
  });

  /// The single open chatroom everyone can post into.
  static const chatroomId = 'chatroom';

  final String id;
  final String conversationId;
  final String authorId;
  final DateTime createdAt;
  final String text;

  /// Set when a message is about a specific listing — "is this still
  /// available?", sent from a product page.
  final String? attachedProductId;

  final MessageStatus status;

  String get time => Fmt.clock(createdAt);

  bool get isPending => status == MessageStatus.sending;
  bool get hasFailed => status == MessageStatus.failed;

  Message copyWith({MessageStatus? status, String? id}) => Message(
    id: id ?? this.id,
    conversationId: conversationId,
    authorId: authorId,
    createdAt: createdAt,
    text: text,
    attachedProductId: attachedProductId,
    status: status ?? this.status,
  );
}

/// A one-to-one thread.
///
/// The id is the two participant uids sorted and joined, so opening a
/// conversation with someone is a lookup rather than a search, and two people
/// messaging each other at the same moment cannot create two threads.
@immutable
class Conversation {
  const Conversation({
    required this.id,
    required this.participantIds,
    required this.lastMessageAt,
    required this.preview,
    this.unread = 0,
  });

  final String id;
  final List<String> participantIds;
  final DateTime lastMessageAt;
  final String preview;
  final int unread;

  static String idFor(String a, String b) {
    final pair = [a, b]..sort();
    return pair.join('_');
  }

  /// The person who is not you.
  String otherThan(String uid) =>
      participantIds.firstWhere((id) => id != uid, orElse: () => uid);

  String get age => Fmt.inboxAge(lastMessageAt);

  Conversation copyWith({
    DateTime? lastMessageAt,
    String? preview,
    int? unread,
  }) => Conversation(
    id: id,
    participantIds: participantIds,
    lastMessageAt: lastMessageAt ?? this.lastMessageAt,
    preview: preview ?? this.preview,
    unread: unread ?? this.unread,
  );
}

/// What the open chatroom looks like right now, for the pin in the feed.
///
/// The pin has to say something is happening without making the person open
/// the room to find out, so it carries the last couple of messages and how
/// busy the last hour was rather than a count of everything ever said.
@immutable
class ChatMoment {
  const ChatMoment({
    this.latest = const [],
    this.lastHourCount = 0,
    this.hereNow = 0,
  });

  /// The last two messages, oldest first.
  final List<Message> latest;

  /// How many messages landed in the last hour. Zero is a real answer: the
  /// pin then says the room is quiet rather than inventing activity.
  final int lastHourCount;

  /// How many people are in the room this second.
  ///
  /// **Always 0.** There is no presence data anywhere in this system, and the
  /// mockup's "23 here now" is a drawing, not a number we have. The field is
  /// here so the pin has somewhere to read it from the day presence exists;
  /// until then no pin may print it. See `Planning/redesign-plan.md` §8.
  final int hereNow;

  bool get isQuiet => lastHourCount == 0;
}
