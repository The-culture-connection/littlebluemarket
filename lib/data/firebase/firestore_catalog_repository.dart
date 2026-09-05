import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../models/models.dart';
import '../repositories/repositories.dart';
import 'firestore_errors.dart';
import 'mappers.dart';

/// Listings, read from the Firestore mirror of the storefront.
///
/// This is the piece that makes the storefront replaceable. The feed, the
/// grids and search all read documents whose field names are ours, kept in step
/// by a sync function — so they are one cheap query, they work offline, and on
/// the day the storefront goes away the mirror *is* the catalog.
///
/// The single exception is [liveVariants], which asks the commerce proxy,
/// because overselling something is worse than a spinner.
class FirestoreCatalogRepository implements CatalogRepository {
  FirestoreCatalogRepository({
    required FirebaseFirestore firestore,
    required FirebaseFunctions functions,
  }) : _db = firestore,
       _functions = functions;

  final FirebaseFirestore _db;
  final FirebaseFunctions _functions;

  CollectionReference<Map<String, dynamic>> get _catalog =>
      _db.collection('catalog');

  @override
  Future<Product> product(String id) => guardFirestore(() async {
    final doc = await _catalog.doc(id).get();
    final data = doc.data();
    // Throws rather than substituting another product. The prototype's
    // fallback meant a bad deep link showed the wrong listing.
    if (data == null) throw NotFoundException('product', id);
    return FirestoreMappers.product(doc.id, data);
  }, operation: 'firestore catalog product');

  @override
  Future<ProductSpec> spec(String id) => guardFirestore(() async {
    final doc = await _catalog.doc(id).collection('spec').doc('detail').get();
    final data = doc.data();
    if (data == null) throw NotFoundException('spec', id);
    return FirestoreMappers.spec(data);
  }, operation: 'firestore catalog spec');

  @override
  Future<List<Product>> productsByIds(List<String> ids) =>
      guardFirestore(() async {
        if (ids.isEmpty) return const [];

        final found = <String, Product>{};
        const chunkSize = 30;
        for (var i = 0; i < ids.length; i += chunkSize) {
          final chunk = ids.sublist(
            i,
            i + chunkSize > ids.length ? ids.length : i + chunkSize,
          );
          final snapshot = await _catalog
              .where(FieldPath.documentId, whereIn: chunk)
              .get();
          for (final doc in snapshot.docs) {
            found[doc.id] = FirestoreMappers.product(doc.id, doc.data());
          }
        }

        // Ordered to match the request, and ids that no longer exist are
        // skipped: a stale reference costs one card, not the screen.
        return [
          for (final id in ids)
            ?found[id],
        ];
      }, operation: 'firestore catalog productsByIds');

  @override
  Future<Page<Product>> productsBySeller(String sellerId, {String? cursor}) =>
      guardFirestore(() async {
        var query = _catalog
            .where('sellerId', isEqualTo: sellerId)
            .orderBy('createdAt', descending: true)
            .limit(30);
        if (cursor != null) {
          final anchor = await _catalog.doc(cursor).get();
          if (anchor.exists) query = query.startAfterDocument(anchor);
        }

        final snapshot = await query.get();
        return Page(
          items: snapshot.docs
              .map((doc) => FirestoreMappers.product(doc.id, doc.data()))
              .toList(),
          cursor: snapshot.docs.length < 30 ? null : snapshot.docs.last.id,
        );
      }, operation: 'firestore catalog productsBySeller');

  @override
  Future<List<Variant>> liveVariants(String productId) =>
      guardFirestore(() async {
        // The only read that must not be served from the mirror: stock is the
        // one field where being a few minutes stale sells something twice.
        final result = await _functions
            .httpsCallable('commerceLiveVariants')
            .call<Map<String, dynamic>>({'productId': productId});

        final variants = result.data['variants'];
        if (variants is! List) throw NotFoundException('product', productId);
        return [
          for (final item in variants)
            if (item is Map)
              FirestoreMappers.variant(Map<String, dynamic>.from(item)),
        ];
      }, operation: 'callable commerceLiveVariants');

  @override
  Future<List<TagCount>> popularTags({int limit = 8}) =>
      guardFirestore(() async {
        final snapshot = await _db
            .collection('hashtags')
            .orderBy('postCount', descending: true)
            .limit(limit)
            .get();
        return snapshot.docs
            .map(
              (doc) => TagCount(
                FirestoreMappers.str(doc.data()['tag'], '#${doc.id}'),
                FirestoreMappers.integer(doc.data()['postCount']),
              ),
            )
            .toList();
      }, operation: 'firestore catalog popularTags');
}
