import 'package:flutter/foundation.dart';

/// One of Little Blue Market's own pages, posted to the For you feed from
/// the admin website (Grace, 2026-10-28: "I want to show the shopify pages
/// on the homescreen when they are posted").
///
/// The page itself stays on the store, where it is edited. The feed carries
/// what a link preview would, plus the page's words and pictures as [blocks],
/// read when it was posted, so it opens on the app's own screen (Grace,
/// 2026-10-28: "able to be opened natively in the app"). A page with no
/// blocks (a lookup form, or one that could not be read) opens as the web
/// page instead.
@immutable
class StorePage {
  const StorePage({
    required this.id,
    required this.url,
    required this.title,
    this.blurb = '',
    this.imageUrl = '',
    this.blocks = const [],
    this.createdAt,
  });

  final String id;
  final String url;
  final String title;
  final String blurb;

  /// The page's own picture, or empty.
  final String imageUrl;
  final DateTime? createdAt;

  /// The page as the app draws it, in order.
  final List<PageBlock> blocks;

  bool get hasPhoto => imageUrl.isNotEmpty;

  /// Whether it opens on the app's own screen rather than as a web page.
  bool get readsInApp => blocks.isNotEmpty;
}

enum PageBlockKind {
  heading,
  text,
  bullet,
  image,
  button;

  static PageBlockKind? fromValue(String value) =>
      values.where((k) => k.name == value).firstOrNull;
}

/// One part of a store page: words, a picture, or a button. Written by the
/// backend (functions/src/store_page_content.ts) when the page is posted.
@immutable
class PageBlock {
  const PageBlock({
    required this.kind,
    this.text = '',
    this.url = '',
    this.link = '',
  });

  final PageBlockKind kind;

  /// The words of a heading, paragraph or bullet; a button's label.
  final String text;

  /// A picture's address, or where a button goes.
  final String url;

  /// Where a heading, paragraph or picture goes when tapped, or empty.
  final String link;
}
