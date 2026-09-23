import 'package:flutter/foundation.dart';

import 'models.dart';

/// What a query is being matched against.
///
/// One enum for the whole app. The prototype had two different chip lists —
/// four scopes on the search screen, three on the results screen — and neither
/// filtered anything.
/// The scope a query arriving from a link should be searched in: a hashtag
/// as a hashtag, anything else across everything.
SearchScope scopeFor(String query) => query.trimLeft().startsWith('#')
    ? SearchScope.hashtags
    : SearchScope.all;

enum SearchScope {
  all('All'),
  hashtags('Hashtags'),
  keywords('Keywords'),
  sellers('Sellers'),
  productType('Type');

  const SearchScope(this.label);
  final String label;
}

/// How a list of listings is ordered.
///
/// Three of these read three different counts, and the difference matters:
/// [bestSellers] reads what has actually been bought, [mostPopular] reads how
/// many people have ever added it to a cart (the affinity signal on Little
/// Blue Market, where there is no like), and [topRated] reads the reviews.
enum SortOrder {
  relevance('Relevance'),
  bestSellers('Best sellers'),
  mostPopular('Most popular'),
  priceLowToHigh('Price: low to high'),
  priceHighToLow('Price: high to low'),
  topRated('Top rated'),
  newest('Newest'),
  nearest('Nearest');

  const SortOrder(this.label);
  final String label;

  /// Everything except [nearest], which needs somewhere to measure from and
  /// is offered by the Near me button rather than by the sort sheet.
  static List<SortOrder> get offered =>
      values.where((s) => s != SortOrder.nearest).toList();
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

/// Puts listings in the order [sort] asks for.
///
/// Here rather than in a repository because both of them needed it and the
/// two copies had already drifted: the fixture one and the Firestore one
/// disagreed about what Newest meant, which is exactly the kind of thing
/// nobody notices until a tester does.
///
/// Stable and total: every comparison falls back to the title, so a shelf of
/// listings with the same count does not reshuffle itself between two reads
/// of the same search.
List<Product> sortProducts(
  List<Product> products,
  SortOrder sort, {
  SearchOrigin? origin,
}) {
  final sorted = [...products];
  int byTitle(Product a, Product b) =>
      a.title.toLowerCase().compareTo(b.title.toLowerCase());
  int then(int first, Product a, Product b) =>
      first != 0 ? first : byTitle(a, b);

  switch (sort) {
    case SortOrder.bestSellers:
      sorted.sort((a, b) => then(b.soldCount.compareTo(a.soldCount), a, b));
    case SortOrder.mostPopular:
      sorted.sort((a, b) => then(b.saveCount.compareTo(a.saveCount), a, b));
    case SortOrder.priceLowToHigh:
      sorted.sort((a, b) => then(a.priceCents.compareTo(b.priceCents), a, b));
    case SortOrder.priceHighToLow:
      sorted.sort((a, b) => then(b.priceCents.compareTo(a.priceCents), a, b));
    case SortOrder.topRated:
      // A five-star listing with one review is not better than a 4.8 with
      // ninety, so the count breaks the tie before the title does.
      sorted.sort((a, b) {
        final byStars = b.rating.compareTo(a.rating);
        if (byStars != 0) return byStars;
        return then(b.ratingCount.compareTo(a.ratingCount), a, b);
      });
    case SortOrder.newest:
      // A mirror row written before `createdAt` existed sorts last rather
      // than first: unknown is not new.
      sorted.sort((a, b) {
        final at = a.createdAt;
        final bt = b.createdAt;
        if (at == null && bt == null) return byTitle(a, b);
        if (at == null) return 1;
        if (bt == null) return -1;
        return then(bt.compareTo(at), a, b);
      });
    case SortOrder.nearest:
      if (origin == null) break;
      double distance(Product p) => p.lat == null || p.lng == null
          ? double.infinity
          : Geo.milesBetween(origin.lat, origin.lng, p.lat!, p.lng!);
      sorted.sort((a, b) => then(distance(a).compareTo(distance(b)), a, b));
    case SortOrder.relevance:
      // Whatever order the search produced: that is what relevance means
      // here, and pretending otherwise would be a lie about the ranking.
      break;
  }
  return sorted;
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
