import 'package:flutter/foundation.dart';

import 'formatting.dart';

/// Why the bell lit up.
enum NotificationKind {
  mention,
  comment,
  review,
  forumThread,
  forumReply,
  newProduct,

  /// Someone you follow posted.
  newPost,
  announcement,
  other,
}

/// One entry under the bell. Written only by the backend.
@immutable
class AppNotification {
  const AppNotification({
    required this.id,
    required this.kind,
    required this.postId,
    required this.fromUid,
    required this.text,
    required this.createdAt,
    this.read = false,
    this.route,
    this.title,
  });

  final String id;
  final NotificationKind kind;
  final String postId;
  final String fromUid;

  /// The first line of the post or comment, so the row reads as a sentence.
  final String text;
  final DateTime createdAt;
  final bool read;

  /// Where a tap goes. Older entries have none and open their post.
  final String? route;

  /// An announcement's own title. Everything else is named after a person.
  final String? title;

  String get age => Fmt.relative(createdAt);

  String get headline => switch (kind) {
    NotificationKind.mention => 'mentioned you in a post',
    NotificationKind.comment => 'commented on your post',
    NotificationKind.review => 'reviewed your product',
    NotificationKind.forumThread => 'started a thread in a forum you joined',
    NotificationKind.forumReply => 'replied in a thread you are in',
    NotificationKind.newProduct => 'added something new',
    NotificationKind.newPost => 'posted something new',
    NotificationKind.announcement => '',
    NotificationKind.other => 'sent you a note',
  };
}

/// The notification switches. Every one defaults to on; a muted forum
/// silences the bell as well as the push for that forum.
@immutable
class NotificationPrefs {
  const NotificationPrefs({
    this.mentions = true,
    this.comments = true,
    this.forums = true,
    this.reviews = true,
    this.newProducts = true,
    this.newPosts = true,
    this.announcements = true,
    this.mutedForums = const [],
    this.announcementsSeenAt,
  });

  final bool mentions;
  final bool comments;
  final bool forums;
  final bool reviews;
  final bool newProducts;

  /// A post from someone you follow (the Notify me button on a profile).
  final bool newPosts;
  final bool announcements;
  final List<String> mutedForums;

  /// Announcements are one document for everyone, so "read" is a stamp on
  /// the account rather than a flag on each: anything newer is unread.
  final DateTime? announcementsSeenAt;

  NotificationPrefs copyWith({
    bool? mentions,
    bool? comments,
    bool? forums,
    bool? reviews,
    bool? newProducts,
    bool? newPosts,
    bool? announcements,
    List<String>? mutedForums,
    DateTime? announcementsSeenAt,
  }) => NotificationPrefs(
    mentions: mentions ?? this.mentions,
    comments: comments ?? this.comments,
    forums: forums ?? this.forums,
    reviews: reviews ?? this.reviews,
    newProducts: newProducts ?? this.newProducts,
    newPosts: newPosts ?? this.newPosts,
    announcements: announcements ?? this.announcements,
    mutedForums: mutedForums ?? this.mutedForums,
    announcementsSeenAt: announcementsSeenAt ?? this.announcementsSeenAt,
  );

  Map<String, Object> toMap() => {
    'mentions': mentions,
    'comments': comments,
    'forums': forums,
    'reviews': reviews,
    'newProducts': newProducts,
    'newPosts': newPosts,
    'announcements': announcements,
    'mutedForums': mutedForums,
  };
}

/// The `@handle`s a text names, in order, without duplicates. Handles are
/// letters, digits, dots and underscores; an email address is not a mention.
List<String> parseMentionHandles(String text) {
  final seen = <String>{};
  final out = <String>[];
  for (final match in RegExp(r'(?<![\w.])@([A-Za-z0-9_.]+)').allMatches(text)) {
    final handle = match.group(1)!.replaceAll(RegExp(r'\.+$'), '');
    if (handle.isEmpty) continue;
    final key = handle.toLowerCase();
    if (seen.add(key)) out.add(handle);
  }
  return out;
}

/// The `#hashtags` a text carries, in order, without duplicates (case
/// folded), each kept as typed. Every post can carry tags; nobody should
/// have to fill a separate field to say what a post is about.
List<String> parseHashtags(String text) {
  final seen = <String>{};
  final out = <String>[];
  for (final match in RegExp(r'#(\w+)').allMatches(text)) {
    final tag = '#${match.group(1)!}';
    if (seen.add(tag.toLowerCase())) out.add(tag);
  }
  return out;
}

/// The lowercase mirror of a set of hashtags, deduped: what a profile stores
/// in `tagsLower` so a search finds it whatever case it was typed in.
List<String> lowerTags(Iterable<String> tags) {
  final seen = <String>{};
  for (final raw in tags) {
    final tag = raw.trim().toLowerCase();
    if (tag.isEmpty) continue;
    seen.add(tag.startsWith('#') ? tag : '#$tag');
  }
  return seen.toList();
}

/// A search that must find every word, not only the first.
bool matchesAllWords(String haystack, String query) {
  final text = haystack.toLowerCase();
  final words = query
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty);
  for (final word in words) {
    if (!text.contains(word)) return false;
  }
  return true;
}

/// Something to try when a search found nothing.
@immutable
class SearchSuggestion {
  const SearchSuggestion.query(this.label, this.query)
    : collectionHandle = null;
  const SearchSuggestion.collection(this.label, this.collectionHandle)
    : query = null;

  final String label;
  final String? query;
  final String? collectionHandle;
}
