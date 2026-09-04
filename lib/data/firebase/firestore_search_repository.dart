import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/models.dart';
import '../repositories/repositories.dart';
import 'firestore_errors.dart';
import 'geohash.dart';
import 'mappers.dart';

/// Search over the catalog mirror.
///
/// Firestore genuinely cannot serve this query. "Goods and services matching a
/// word, within N miles" needs a text match and a geo range at once, and it
/// supports neither together nor full-text at all. So:
///
///  * **With a radius**, the geohash prefix scan runs first — that is the one
///    filter Firestore does well — and the text match is applied over the
///    candidate set, which is small because it is bounded by distance.
///  * **Without a radius**, tags and product type are matched in the query
///    (they are exact), and free text falls back to a prefix scan on a
///    normalised title field.
///
/// This is honest at the current catalogue size and does not pretend to be a
/// search engine. When the catalogue outgrows it, this class is what gets
/// replaced with a Typesense or Algolia call — which is exactly why
/// [SearchRepository] is a separate interface from [CatalogRepository].
class FirestoreSearchRepository implements SearchRepository {
  FirestoreSearchRepository({
    required FirebaseFirestore firestore,
    required this.uid,
  }) : _db = firestore;

  final FirebaseFirestore _db;
  final String? uid;

  CollectionReference<Map<String, dynamic>> get _catalog =>
      _db.collection('catalog');

  /// How many candidates a geo scan will pull back before ranking. Generous
  /// enough to be complete at this size, bounded so a wide radius cannot read
  /// the whole collection.
  static const _candidateLimit = 300;

  @override
  Future<SearchResults> search(SearchFilters filters, {String? cursor}) =>
      guardFirestore(() async {
        final query = filters.query.trim();
        if (query.isEmpty) return const SearchResults.empty();

        final products = filters.isGeoConstrained
            ? await _geoSearch(filters)
            : await _plainSearch(filters);

        final sellers = filters.scope == SearchScope.productType
            ? const <Person>[]
            : await _sellers(query);

        final reviews = query.startsWith('#')
            ? await _taggedReviews(query)
            : const <TaggedReview>[];

        return SearchResults(
          products: _sorted(products, filters),
          sellers: sellers,
          reviews: reviews,
        );
      });

  /// Bound by distance first, then match text over what comes back.
  Future<List<Product>> _geoSearch(SearchFilters filters) async {
    final origin = filters.origin!;
    final ranges = Geohash.coverRanges(
      origin.lat,
      origin.lng,
      filters.radiusMiles,
    );

    // Each prefix range is its own query; Firestore has no OR across ranges.
    final snapshots = await Future.wait([
      for (final (start, end) in ranges)
        _catalog
            .where('geohash', isGreaterThanOrEqualTo: start)
            .where('geohash', isLessThan: end)
            .limit(_candidateLimit ~/ ranges.length + 1)
            .get(),
    ]);

    final seen = <String>{};
    final candidates = <Product>[];
    for (final snapshot in snapshots) {
      for (final doc in snapshot.docs) {
        if (!seen.add(doc.id)) continue;
        candidates.add(FirestoreMappers.product(doc.id, doc.data()));
      }
    }

    return [
      for (final product in candidates)
        // A box overlapping the circle is not the same as a point inside it,
        // so the exact distance filter is what stops a listing 25 miles away
        // showing up in a 20-mile search.
        if (product.lat != null &&
            product.lng != null &&
            Geohash.within(
              product.lat!,
              product.lng!,
              origin.lat,
              origin.lng,
              filters.radiusMiles,
            ) &&
            _matches(product, filters))
          product,
    ];
  }

  /// No radius: let Firestore do what it can, then filter the rest.
  Future<List<Product>> _plainSearch(SearchFilters filters) async {
    final query = filters.query.trim();
    final lower = query.toLowerCase();

    Query<Map<String, dynamic>> base = _catalog;
    switch (filters.scope) {
      case SearchScope.hashtags:
        base = base.where('tags', arrayContains: query);
      case SearchScope.productType:
        base = base.where('typeSlug', isEqualTo: _slug(query));
      case SearchScope.sellers:
        base = base.where('sellerHandleLower', isEqualTo: lower.replaceFirst('@', ''));
      case SearchScope.keywords:
      case SearchScope.all:
        if (query.startsWith('#')) {
          base = base.where('tags', arrayContains: query);
        } else {
          // Prefix scan on a normalised title. Not a substring match — that is
          // the honest limit of what Firestore can index.
          base = base
              .where('titleLower', isGreaterThanOrEqualTo: lower)
              .where('titleLower', isLessThan: '$lower');
        }
    }

    final snapshot = await base.limit(_candidateLimit).get();
    final products = snapshot.docs
        .map((doc) => FirestoreMappers.product(doc.id, doc.data()))
        .toList();

    // `all` also wants type and description hits, which the single query above
    // could not include.
    if (filters.scope != SearchScope.all) return products;

    final byType = await _catalog
        .where('typeSlug', isEqualTo: _slug(query))
        .limit(50)
        .get();
    final seen = products.map((p) => p.id).toSet();
    for (final doc in byType.docs) {
      if (seen.add(doc.id)) {
        products.add(FirestoreMappers.product(doc.id, doc.data()));
      }
    }
    return products;
  }

  bool _matches(Product product, SearchFilters filters) {
    final query = filters.query.trim();
    final lower = query.toLowerCase();

    return switch (filters.scope) {
      SearchScope.hashtags => product.tags.contains(query),
      SearchScope.productType => product.type.toLowerCase().contains(lower),
      SearchScope.sellers => product.sellerId.toLowerCase().contains(lower),
      SearchScope.keywords =>
        product.title.toLowerCase().contains(lower) ||
            product.description.toLowerCase().contains(lower),
      SearchScope.all =>
        product.tags.contains(query) ||
            product.title.toLowerCase().contains(lower) ||
            product.type.toLowerCase().contains(lower) ||
            product.description.toLowerCase().contains(lower),
    };
  }

  Future<List<Person>> _sellers(String query) async {
    final lower = query.toLowerCase().replaceFirst('@', '');
    final snapshot = await _db
        .collection('users')
        .where('isSeller', isEqualTo: true)
        .where('handleLower', isGreaterThanOrEqualTo: lower)
        .where('handleLower', isLessThan: '$lower')
        .limit(10)
        .get();
    return snapshot.docs
        .map((doc) => FirestoreMappers.person(doc.id, doc.data()))
        .toList();
  }

  Future<List<TaggedReview>> _taggedReviews(String tag) async {
    final snapshot = await _db
        .collectionGroup('reviews')
        .where('tags', arrayContains: tag)
        .orderBy('createdAt', descending: true)
        .limit(20)
        .get();
    return [
      for (final doc in snapshot.docs)
        TaggedReview(
          productId: doc.reference.parent.parent?.id ?? '',
          review: FirestoreMappers.review(doc.data()),
        ),
    ];
  }

  List<Product> _sorted(List<Product> products, SearchFilters filters) {
    final sorted = [...products];
    switch (filters.sort) {
      case SortOrder.priceLowToHigh:
        sorted.sort((a, b) => a.priceCents.compareTo(b.priceCents));
      case SortOrder.topRated:
        sorted.sort((a, b) => b.rating.compareTo(a.rating));
      case SortOrder.nearest:
        final origin = filters.origin;
        if (origin != null) {
          double distance(Product p) => p.lat == null || p.lng == null
              ? double.infinity
              : Geo.milesBetween(origin.lat, origin.lng, p.lat!, p.lng!);
          sorted.sort((a, b) => distance(a).compareTo(distance(b)));
        }
      case SortOrder.newest:
      case SortOrder.relevance:
        break;
    }
    return sorted;
  }

  String _slug(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');

  // Recent searches are per person and small, so they live on the user
  // document rather than in their own collection.
  DocumentReference<Map<String, dynamic>>? get _me =>
      uid == null ? null : _db.collection('users').doc(uid);

  @override
  Future<List<String>> recentSearches() => guardFirestore(() async {
    final doc = _me;
    if (doc == null) return const [];
    final snapshot = await doc.get();
    return FirestoreMappers.strings(snapshot.data()?['recentSearches']);
  });

  @override
  Future<void> recordSearch(String query) => guardFirestore(() async {
    final doc = _me;
    final trimmed = query.trim();
    if (doc == null || trimmed.isEmpty) return;

    final current = await recentSearches();
    final next = [
      trimmed,
      ...current.where((q) => q.toLowerCase() != trimmed.toLowerCase()),
    ].take(8).toList();
    await doc.set({'recentSearches': next}, SetOptions(merge: true));
  });

  @override
  Future<void> removeRecentSearch(String query) => guardFirestore(() async {
    final doc = _me;
    if (doc == null) return;
    await doc.set({
      'recentSearches': FieldValue.arrayRemove([query]),
    }, SetOptions(merge: true));
  });

  @override
  Future<void> clearRecentSearches() => guardFirestore(() async {
    final doc = _me;
    if (doc == null) return;
    await doc.set({'recentSearches': <String>[]}, SetOptions(merge: true));
  });
}
