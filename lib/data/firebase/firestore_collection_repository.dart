import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/models.dart';
import '../repositories/repositories.dart';
import 'firestore_errors.dart';
import 'mappers.dart';

/// The store's collections and the products filed under them, from the
/// mirror. Both are written only by the backend.
class FirestoreCollectionRepository implements CollectionRepository {
  FirestoreCollectionRepository({required FirebaseFirestore firestore})
    : _db = firestore;

  final FirebaseFirestore _db;

  static const _pageSize = 30;

  @override
  Future<List<Collection>> collections() => guardFirestore(() async {
    final snapshot = await _db.collection('collections').get();
    final all = snapshot.docs
        .map((doc) => FirestoreMappers.collection(doc.id, doc.data()))
        // An empty collection is a heading with nothing under it.
        .where((c) => c.productCount > 0)
        .toList();
    all.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    return all;
  }, operation: 'firestore collections');

  @override
  Future<Collection> collection(String handle) => guardFirestore(() async {
    final doc = await _db.collection('collections').doc(handle).get();
    final data = doc.data();
    if (data == null) throw NotFoundException('collection', handle);
    return FirestoreMappers.collection(doc.id, data);
  }, operation: 'firestore collection');

  @override
  Future<Page<Product>> productsInCollection(String handle, {String? cursor}) =>
      guardFirestore(() async {
        final catalog = _db.collection('catalog');
        var query = catalog
            .where('collectionHandles', arrayContains: handle)
            .orderBy('createdAt', descending: true)
            .limit(_pageSize);
        if (cursor != null) {
          final anchor = await catalog.doc(cursor).get();
          if (anchor.exists) query = query.startAfterDocument(anchor);
        }
        final snapshot = await query.get();
        // Deactivated products stay in the mirror for old posts and orders;
        // a collection page is for browsing, so they are left out here.
        final items = [
          for (final doc in snapshot.docs)
            if (doc.data()['active'] != false)
              FirestoreMappers.product(doc.id, doc.data()),
        ];
        return Page(
          items: items,
          cursor: snapshot.docs.length < _pageSize
              ? null
              : snapshot.docs.last.id,
        );
      }, operation: 'firestore catalog productsInCollection');
}
