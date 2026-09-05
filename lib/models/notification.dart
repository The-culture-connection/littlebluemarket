import 'package:flutter/foundation.dart';

import 'formatting.dart';

/// Why the bell lit up.
enum NotificationKind { mention, comment, other }

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
  });

  final String id;
  final NotificationKind kind;
  final String postId;
  final String fromUid;

  /// The first line of the post or comment, so the row reads as a sentence.
  final String text;
  final DateTime createdAt;
  final bool read;

  String get age => Fmt.relative(createdAt);

  String get headline => switch (kind) {
    NotificationKind.mention => 'mentioned you in a post',
    NotificationKind.comment => 'commented on your post',
    NotificationKind.other => 'sent you a note',
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
