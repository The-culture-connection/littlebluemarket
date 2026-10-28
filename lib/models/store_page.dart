import 'package:flutter/foundation.dart';

/// One of Little Blue Market's own pages, posted to the For you feed from
/// the admin website (Grace, 2026-10-28: "I want to show the shopify pages
/// on the homescreen when they are posted").
///
/// The page itself stays on the store, where it is edited; the feed carries
/// only what a link preview would, and opens the page over the app.
@immutable
class StorePage {
  const StorePage({
    required this.id,
    required this.url,
    required this.title,
    this.blurb = '',
    this.imageUrl = '',
    this.createdAt,
  });

  final String id;
  final String url;
  final String title;
  final String blurb;

  /// The page's own picture, or empty.
  final String imageUrl;
  final DateTime? createdAt;

  bool get hasPhoto => imageUrl.isNotEmpty;
}
