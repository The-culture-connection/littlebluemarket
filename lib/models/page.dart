import 'package:flutter/foundation.dart';

/// One page of results, plus how to ask for the next.
///
/// Cursors rather than offsets: Firestore pages by document snapshot and
/// Shopify by opaque cursor, and neither can honestly answer "give me results
/// 40 through 60" of a list that is changing underneath you.
@immutable
class Page<T> {
  const Page({required this.items, this.cursor});

  const Page.empty() : items = const [], cursor = null;

  final List<T> items;

  /// Null when there is nothing after this page.
  final String? cursor;

  bool get isEmpty => items.isEmpty;
  bool get hasMore => cursor != null;

  Page<T> operator +(Page<T> next) =>
      Page(items: [...items, ...next.items], cursor: next.cursor);
}
