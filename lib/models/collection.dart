import 'package:flutter/foundation.dart';

import 'formatting.dart';

/// A collection on the store: a category ("Bath, Beauty & Wellness") or an
/// initiative ("Woman Owned", "Ally Owned").
///
/// This is the store's real taxonomy. Product type is "physical" across the
/// live store and categorises nothing, and hashtags are the post vocabulary;
/// the collection is what the seller actually filed the product under.
@immutable
class Collection {
  const Collection({
    required this.handle,
    required this.title,
    required this.productCount,
    this.imageUrl,
  });

  /// The URL slug Shopify uses, e.g. `ally-owned`. Stable, and the document id.
  final String handle;
  final String title;
  final int productCount;
  final String? imageUrl;

  String get countLabel =>
      '${Fmt.count(productCount)} ${productCount == 1 ? 'product' : 'products'}';
}
