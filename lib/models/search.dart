import 'package:flutter/foundation.dart';

import 'models.dart';

/// What a query is being matched against.
///
/// One enum for the whole app. The prototype had two different chip lists —
/// four scopes on the search screen, three on the results screen — and neither
/// filtered anything.
enum SearchScope {
  all('All'),
  hashtags('Hashtags'),
  keywords('Keywords'),
  sellers('Sellers'),
  productType('Type');

  const SearchScope(this.label);
  final String label;
}

enum SortOrder {
  relevance('Relevance'),
  nearest('Nearest'),
  newest('Newest'),
  priceLowToHigh('Price'),
  topRated('Top rated');

  const SortOrder(this.label);
  final String label;
}

/// Where the person searching is, and how far they are willing to go.
@immutable
class SearchOrigin {
  const SearchOrigin({
    required this.lat,
    required this.lng,
    required this.label,
    this.fromDevice = false,
  });

  final double lat;
  final double lng;

  /// What to show in the UI: "Current location", or a typed address.
  final String label;

  /// True when this came from the device rather than a typed address, which is
  /// what lets the UI offer to re-locate.
  final bool fromDevice;

  @override
  bool operator ==(Object other) =>
      other is SearchOrigin &&
      other.lat == lat &&
      other.lng == lng &&
      other.label == label &&
      other.fromDevice == fromDevice;

  @override
  int get hashCode => Object.hash(lat, lng, label, fromDevice);
}

/// A whole search, as one value.
///
/// Value equality is not decoration here: this is the argument to a provider
/// family, and without it every rebuild would look like a new search and
/// refetch.
@immutable
class SearchFilters {
  const SearchFilters({
    this.query = '',
    this.scope = SearchScope.all,
    this.origin,
    this.radiusMiles = defaultRadiusMiles,
    this.nearMe = false,
    this.sort = SortOrder.relevance,
  });

  /// The product's default vicinity.
  static const defaultRadiusMiles = 20.0;

  final String query;
  final SearchScope scope;

  /// Null until the person has granted location or typed an address.
  final SearchOrigin? origin;
  final double radiusMiles;

  /// Whether to constrain by [radiusMiles] at all. Distinct from having an
  /// [origin]: we may know where someone is and still be showing them
  /// everything.
  final bool nearMe;

  final SortOrder sort;

  /// A radius filter is only meaningful once we know where to measure from.
  bool get isGeoConstrained => nearMe && origin != null;

  bool get isEmpty => query.trim().isEmpty;

  SearchFilters copyWith({
    String? query,
    SearchScope? scope,
    SearchOrigin? origin,
    double? radiusMiles,
    bool? nearMe,
    SortOrder? sort,
    bool clearOrigin = false,
  }) => SearchFilters(
    query: query ?? this.query,
    scope: scope ?? this.scope,
    origin: clearOrigin ? null : (origin ?? this.origin),
    radiusMiles: radiusMiles ?? this.radiusMiles,
    nearMe: nearMe ?? this.nearMe,
    sort: sort ?? this.sort,
  );

  @override
  bool operator ==(Object other) =>
      other is SearchFilters &&
      other.query == query &&
      other.scope == scope &&
      other.origin == origin &&
      other.radiusMiles == radiusMiles &&
      other.nearMe == nearMe &&
      other.sort == sort;

  @override
  int get hashCode =>
      Object.hash(query, scope, origin, radiusMiles, nearMe, sort);

  @override
  String toString() =>
      'SearchFilters($query, $scope, near=$nearMe, r=$radiusMiles, $sort)';
}

/// A review that matched, with the product it hangs off.
///
/// A review is indexed under its parent product, never under its author, which
/// is what lets a hashtag search surface it with a link back to the listing.
@immutable
class TaggedReview {
  const TaggedReview({required this.productId, required this.review});

  final String productId;
  final Review review;
}

/// Everything one search turned up.
@immutable
class SearchResults {
  const SearchResults({
    this.products = const [],
    this.sellers = const [],
    this.reviews = const [],
    this.cursor,
  });

  const SearchResults.empty() : this();

  final List<Product> products;
  final List<Person> sellers;
  final List<TaggedReview> reviews;
  final String? cursor;

  /// True only when nothing at all matched. Screens need this because a real
  /// backend genuinely returns nothing, which the fixture search never did.
  bool get isEmpty => products.isEmpty && sellers.isEmpty && reviews.isEmpty;

  bool get hasMore => cursor != null;

  int get totalCount => products.length + sellers.length + reviews.length;
}
