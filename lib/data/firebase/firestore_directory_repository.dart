import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../models/models.dart';
import '../repositories/repositories.dart';
import 'firestore_errors.dart';
import 'mappers.dart';

/// The directory link, live: the server-only `directory/{uid}` document,
/// the mirrored website orders, and the one callable that writes both.
class FirestoreDirectoryRepository implements DirectoryRepository {
  FirestoreDirectoryRepository({
    required FirebaseFirestore firestore,
    required FirebaseFunctions functions,
    required this.uid,
  }) : _db = firestore,
       _functions = functions;

  final FirebaseFirestore _db;
  final FirebaseFunctions _functions;

  /// Null while signed out.
  final String? uid;

  String get _requireUid {
    final id = uid;
    if (id == null) throw const UnauthenticatedException();
    return id;
  }

  @override
  Stream<DirectoryLink?> watchLink() {
    final id = uid;
    if (id == null) return Stream.value(null);
    return _db
        .collection('directory')
        .doc(id)
        .snapshots()
        .map((doc) {
          final data = doc.data();
          return data == null ? null : FirestoreMappers.directoryLink(data);
        })
        .guarded(operation: 'firestore directory/{uid}');
  }

  @override
  Stream<List<DirectoryOrder>> watchOrders() {
    final id = uid;
    if (id == null) return Stream.value(const []);
    return _db
        .collection('users')
        .doc(id)
        .collection('directoryOrders')
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .map(
          (snapshot) => [
            for (final doc in snapshot.docs)
              FirestoreMappers.directoryOrder(doc.id, doc.data()),
          ],
        )
        .guarded(operation: 'firestore users/{uid}/directoryOrders');
  }

  @override
  Stream<List<DirectoryListing>> watchMyListings() {
    final id = uid;
    if (id == null) return Stream.value(const []);
    return _db
        .collection('directoryListings')
        .where('ownerUid', isEqualTo: id)
        .orderBy('updatedAt', descending: true)
        .limit(100)
        .snapshots()
        .map(
          (snapshot) => [
            for (final doc in snapshot.docs)
              FirestoreMappers.directoryListing(doc.id, doc.data()),
          ],
        )
        .guarded(operation: 'firestore directoryListings (mine)');
  }

  @override
  Stream<DirectoryListing?> watchListing(String id) => _db
      .collection('directoryListings')
      .doc(id)
      .snapshots()
      .map((doc) {
        final data = doc.data();
        return data == null
            ? null
            : FirestoreMappers.directoryListing(doc.id, data);
      })
      .guarded(operation: 'firestore directoryListings/{id}');

  @override
  Stream<List<DirectoryListing>> watchPublishedListingsOf(String ownerUid) =>
      _db
          .collection('directoryListings')
          .where('ownerUid', isEqualTo: ownerUid)
          .where('status', isEqualTo: 'publish')
          .orderBy('updatedAt', descending: true)
          .limit(100)
          .snapshots()
          .map(
            (snapshot) => [
              for (final doc in snapshot.docs)
                FirestoreMappers.directoryListing(doc.id, doc.data()),
            ],
          )
          .guarded(operation: 'firestore directoryListings (published)');

  CollectionReference<Map<String, dynamic>> get _products =>
      _db.collection('directoryProducts');

  Stream<List<Product>> _productsOf(String ownerUid) => _products
      .where('ownerUid', isEqualTo: ownerUid)
      .orderBy('createdAt', descending: true)
      .limit(100)
      .snapshots()
      .map(
        (snapshot) => [
          for (final doc in snapshot.docs)
            FirestoreMappers.directoryProduct(doc.id, doc.data()),
        ],
      )
      .guarded(operation: 'firestore directoryProducts');

  @override
  Stream<List<Product>> watchMyProducts() {
    final id = uid;
    if (id == null) return Stream.value(const []);
    return _productsOf(id);
  }

  @override
  Stream<List<Product>> watchProductsOf(String ownerUid) =>
      _productsOf(ownerUid);

  @override
  Future<String> saveProduct(NewDirectoryProduct draft, {String? id}) =>
      guardFirestore(() async {
        _requireUid;
        final result = await _functions
            .httpsCallable(
              'directoryProductSave',
              options: HttpsCallableOptions(
                timeout: const Duration(seconds: 60),
              ),
            )
            .call<Map<String, dynamic>>({...draft.toMap(), 'id': ?id});
        return FirestoreMappers.str(result.data['id']);
      }, operation: 'callable directoryProductSave');

  @override
  Future<void> reportPurchase(String productId) => guardFirestore(() async {
    _requireUid;
    await _functions
        .httpsCallable('directoryPurchaseReport')
        .call<Map<String, dynamic>>({'productId': productId});
  }, operation: 'callable directoryPurchaseReport');

  @override
  Future<void> deleteProduct(String id) => guardFirestore(() async {
    _requireUid;
    await _functions
        .httpsCallable('directoryProductDelete')
        .call<Map<String, dynamic>>({'id': id});
  }, operation: 'callable directoryProductDelete');

  @override
  Future<({String name, String handle})> applyListingProfile() =>
      guardFirestore(() async {
        _requireUid;
        final result = await _functions
            .httpsCallable('directoryApplyProfile')
            .call<Map<String, dynamic>>(const {});
        return (
          name: FirestoreMappers.str(result.data['name']),
          handle: FirestoreMappers.str(result.data['handle']),
        );
      }, operation: 'callable directoryApplyProfile');

  @override
  Future<DirectoryLinkResult> link({bool auto = false}) =>
      guardFirestore(() async {
        _requireUid;
        // No email in the request: the function reads it from the verified
        // token, the same rule as linkAccounts.
        final result = await _functions
            .httpsCallable(
              'directoryLinkMe',
              options: HttpsCallableOptions(
                timeout: const Duration(seconds: 120),
              ),
            )
            .call<Map<String, dynamic>>({'auto': auto});
        final data = result.data;
        return DirectoryLinkResult(
          status: switch (FirestoreMappers.str(data['status'])) {
            'linked' => DirectoryLinkStatus.linked,
            'alreadyLinked' => DirectoryLinkStatus.alreadyLinked,
            'off' => DirectoryLinkStatus.off,
            _ => DirectoryLinkStatus.notFound,
          },
          orders: FirestoreMappers.integer(data['orders']),
          listings: FirestoreMappers.integer(data['listings']),
          wpLogin: data['wpLogin'] is String ? data['wpLogin'] as String : null,
          note: data['note'] is String ? data['note'] as String : null,
        );
      }, operation: 'callable directoryLinkMe');
}
