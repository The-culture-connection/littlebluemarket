import 'package:flutter/foundation.dart';

/// Emoji reactions on messages (Grace, 2026-11-04: "for chats, forums, and
/// messages allow to long press and react with emojis to messages").
///
/// Stored on the message as `reactions.{uid} = emoji`: one reaction each,
/// WhatsApp-style, changed by picking another and taken back by picking the
/// same one again. The rules let a member touch only their own entry.

/// The row a long press offers first, the blue heart leading (Grace,
/// 2026-11-04: "make the heart blue for reactions"). Any other emoji is one
/// tap further, on the + beside them.
const quickReactions = ['💙', '👍', '😂', '😮', '😢', '🙏'];

/// Which message a reaction is on. Each kind lives somewhere different.
@immutable
sealed class ReactionTarget {
  const ReactionTarget();

  /// For analytics: which kind of message.
  String get kind;
}

/// A message in the open chat.
final class ChatReactionTarget extends ReactionTarget {
  const ChatReactionTarget(this.messageId);
  final String messageId;
  @override
  String get kind => 'chat';
}

/// A direct message.
final class DmReactionTarget extends ReactionTarget {
  const DmReactionTarget(this.conversationId, this.messageId);
  final String conversationId;
  final String messageId;
  @override
  String get kind => 'dm';
}

/// The opening post of a forum thread.
final class ThreadReactionTarget extends ReactionTarget {
  const ThreadReactionTarget(this.threadId);
  final String threadId;
  @override
  String get kind => 'thread';
}

/// A reply in a forum thread.
final class ReplyReactionTarget extends ReactionTarget {
  const ReplyReactionTarget(this.threadId, this.commentId);
  final String threadId;
  final String commentId;
  @override
  String get kind => 'thread_reply';
}

/// One emoji under a message: how many, and whether one of them is yours.
typedef ReactionCount = ({String emoji, int count, bool mine});

/// The chips under a message, most used first, ties in the order of
/// [quickReactions] and then alphabetically, so they do not jump around as
/// the map comes back in a different order. Pure.
List<ReactionCount> reactionSummary(
  Map<String, String> reactions,
  String? me,
) {
  final counts = <String, int>{};
  for (final emoji in reactions.values) {
    if (emoji.isEmpty) continue;
    counts[emoji] = (counts[emoji] ?? 0) + 1;
  }
  final mine = me == null ? null : reactions[me];
  int rank(String e) {
    final i = quickReactions.indexOf(e);
    return i < 0 ? quickReactions.length : i;
  }

  final emojis = counts.keys.toList()
    ..sort((a, b) {
      final byCount = counts[b]!.compareTo(counts[a]!);
      if (byCount != 0) return byCount;
      final byRank = rank(a).compareTo(rank(b));
      return byRank != 0 ? byRank : a.compareTo(b);
    });
  return [
    for (final e in emojis) (emoji: e, count: counts[e]!, mine: e == mine),
  ];
}

/// What picking [emoji] does to a reaction that is currently [current]:
/// the same one again takes it back (null), anything else replaces it.
/// Pure.
String? toggledReaction(String? current, String emoji) =>
    current == emoji ? null : emoji;
