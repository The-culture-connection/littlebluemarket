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
    this.mentions = const {},
  });

  /// An announcement's resolved `@handles`, lowercased, each with the uid it
  /// meant when it was written. Empty for everything else.
  final Map<String, String> mentions;

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

/// The `@handle`s a text names, in order, without duplicates.
///
/// Handles are letters, digits, dots, underscores and hyphens; an email
/// address is not a mention. The hyphen matters: every shop nobody has
/// signed up for carries a derived handle with the words joined by one, so
/// without it `@romantique-books` named `@romantique`, who does not exist.
///
/// A trailing dot or hyphen is punctuation rather than part of the name.
List<String> parseMentionHandles(String text) {
  final seen = <String>{};
  final out = <String>[];
  for (final match
      in RegExp(r'(?<![\w.])@([A-Za-z0-9_.-]+)').allMatches(text)) {
    final handle = match.group(1)!.replaceAll(RegExp(r'[.-]+$'), '');
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

/// The words of a query, folded the way the catalogue indexes them:
/// lowercase, letters and digits only, one-letter noise dropped.
List<String> queryWords(String query) => [
  for (final word in query.toLowerCase().split(RegExp(r'[^a-z0-9]+')))
    if (word.length > 1) word,
];

/// The spellings of one word worth looking for.
///
/// A tester searched "caramels" and found nothing, because the shop calls it
/// "Sea Salt Caramel" and `array-contains` is exact (Grace, 2026-09-23).
/// This is not stemming and does not pretend to be: it is the plural rules
/// English keeps to often enough to be worth four lines, and it is applied to
/// the query rather than to the index, so nothing has to be re-mirrored.
List<String> wordVariants(String word) {
  final w = word.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  if (w.isEmpty) return const [];
  final out = <String>{w};
  if (w.length > 4 && w.endsWith('ies')) {
    out.add('${w.substring(0, w.length - 3)}y');
  }
  if (w.length > 3 && w.endsWith('es')) out.add(w.substring(0, w.length - 2));
  if (w.length > 3 && w.endsWith('s')) out.add(w.substring(0, w.length - 1));
  if (!w.endsWith('s')) {
    out
      ..add('${w}s')
      ..add('${w}es');
  }
  if (w.length > 2 && w.endsWith('y')) {
    out.add('${w.substring(0, w.length - 1)}ies');
  }
  return out.toList();
}

/// Every spelling worth looking for across a whole query, most distinctive
/// word first, capped at [limit] because `array-contains-any` takes 30.
List<String> queryVariants(String query, {int limit = 30}) {
  final words = queryWords(query)
    ..sort((a, b) => b.length.compareTo(a.length));
  final out = <String>{};
  for (final word in words) {
    for (final variant in wordVariants(word)) {
      if (out.length >= limit) return out.toList();
      out.add(variant);
    }
  }
  return out.toList();
}

/// How many of [query]'s words [haystack] contains, for ranking.
///
/// Zero means nothing matched. Deliberately not "all or nothing": someone
/// searching "caramel candy" should be shown the caramels rather than an
/// empty screen because the shop never wrote the word "candy".
int wordsMatched(String haystack, String query) {
  final text = haystack.toLowerCase();
  var found = 0;
  for (final word in queryWords(query)) {
    if (wordVariants(word).any(text.contains)) found += 1;
  }
  return found;
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
