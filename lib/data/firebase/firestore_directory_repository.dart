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


  CollectionReference<Map<String, dynamic>> get _listings =>
      _db.collection('directoryListings');

  /// How many listings one page of a category screen holds.
  static const _pageSize = 24;

  /// A search reads at most this many candidates before ranking on the
  /// phone, the same bound the catalogue's own search uses.
  static const _searchLimit = 60;

  @override
  Stream<List<DirectoryCategory>> watchDirectoryCategories() => _db
      .collection('directoryCategories')
      .orderBy('count', descending: true)
      .orderBy('name')
      .limit(60)
      .snapshots()
      .map(
        (snapshot) => [
          for (final doc in snapshot.docs)
            DirectoryCategory(
              slug: doc.id,
              name: FirestoreMappers.str(doc.data()['name'], doc.id),
              count: FirestoreMappers.integer(doc.data()['count']),
            ),
        ],
      )
      .guarded(operation: 'firestore directoryCategories');

  @override
  Future<Page<DirectoryListing>> listingsInCategory(
    String slug, {
    String? cursor,
  }) => guardFirestore(() async {
    var query = _listings
        .where('status', isEqualTo: 'publish')
        .where('categorySlugs', arrayContains: slug)
        .orderBy('updatedAt', descending: true)
        .limit(_pageSize);
    if (cursor != null) {
      final anchor = await _listings.doc(cursor).get();
      if (anchor.exists) query = query.startAfterDocument(anchor);
    }
    final snapshot = await query.get();
    return Page(
      items: [
        for (final doc in snapshot.docs)
          FirestoreMappers.directoryListing(doc.id, doc.data()),
      ],
      cursor: snapshot.docs.length < _pageSize ? null : snapshot.docs.last.id,
    );
  }, operation: 'firestore directoryListings (category)');

  @override
  Future<List<DirectoryListing>> searchDirectory(String query) =>
      guardFirestore(() async {
        final text = query.trim().toLowerCase();
        if (text.isEmpty) return const <DirectoryListing>[];

        // One word from the indexed array, which is the business's name, its
        // categories and its city. Not a substring match; that is the honest
        // limit of what Firestore can index, and the same limit the
        // catalogue's search already lives with.
        final words = text
            .split(RegExp('[^a-z0-9]+'))
            .where((w) => w.isNotEmpty)
            .toList();
        final byWord = words.isEmpty
            ? null
            : await _listings
                  .where('status', isEqualTo: 'publish')
                  .where('titleWords', arrayContains: words.first)
                  .limit(_searchLimit)
                  .get();

        // A multi-word query also takes names that start with the whole
        // phrase, which one word cannot express ("found house" for
        // "Found House Ceramics").
        final byPrefix = text.contains(' ')
            ? await _listings
                  .where('status', isEqualTo: 'publish')
                  .where('titleLower', isGreaterThanOrEqualTo: text)
                  .where('titleLower', isLessThan: '$text\uf8ff')
                  .limit(_pageSize)
                  .get()
            : null;

        final seen = <String>{};
        final hits = <DirectoryListing>[];
        for (final snapshot in [byWord, byPrefix]) {
          for (final doc in snapshot?.docs ?? const []) {
            if (!seen.add(doc.id)) continue;
            hits.add(FirestoreMappers.directoryListing(doc.id, doc.data()));
          }
        }
        // A name that starts with what was typed is the better answer, so it
        // sorts first; everything else keeps the order it came back in.
        hits.sort((a, b) {
          final aStarts = a.title.toLowerCase().startsWith(text) ? 0 : 1;
          final bStarts = b.title.toLowerCase().startsWith(text) ? 0 : 1;
          return aStarts.compareTo(bStarts);
        });
        return hits;
      }, operation: 'firestore directoryListings (search)');
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
