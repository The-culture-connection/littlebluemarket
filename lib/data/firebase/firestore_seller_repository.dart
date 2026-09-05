import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../../models/models.dart';
import '../repositories/repositories.dart';
import 'firestore_errors.dart';
import 'mappers.dart';

/// The seller write path: drafts in `listings/`, photos in Storage, and the
/// one callable that turns a draft into a store product.
///
/// The phone never talks to Shopify. It writes its own draft (rules allow
/// exactly that), uploads its own photos (rules allow exactly that), and sends
/// the draft's *id* to the function, which re-reads everything.
class FirestoreSellerRepository implements SellerRepository {
  FirestoreSellerRepository({
    required FirebaseFirestore firestore,
    required FirebaseStorage storage,
    required FirebaseFunctions functions,
    required String? uid,
  }) : _db = firestore,
       _storage = storage,
       _functions = functions,
       _uid = uid;

  final FirebaseFirestore _db;
  final FirebaseStorage _storage;
  final FirebaseFunctions _functions;
  final String? _uid;

  String get _requireUid {
    final uid = _uid;
    if (uid == null) throw const UnauthenticatedException();
    return uid;
  }

  CollectionReference<Map<String, dynamic>> get _listings =>
      _db.collection('listings');

  @override
  Stream<List<Listing>> watchListings() {
    final uid = _uid;
    if (uid == null) return Stream.value(const []);
    return _listings
        .where('sellerUid', isEqualTo: uid)
        .orderBy('updatedAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => [
            for (final doc in snapshot.docs) _listing(doc.id, doc.data()),
          ],
        )
        .guarded(operation: 'firestore listings watch');
  }

  @override
  Future<String> saveDraft(ListingDraft draft, {String? id}) =>
      guardFirestore(() async {
        final uid = _requireUid;
        final ref = id == null ? _listings.doc() : _listings.doc(id);
        final data = <String, Object?>{
          ...draft.toMap(),
          'sellerUid': uid,
          'updatedAt': FieldValue.serverTimestamp(),
        };
        if (id == null) {
          await ref.set({
            ...data,
            'status': 'draft',
            'createdAt': FieldValue.serverTimestamp(),
          });
        } else {
          // Content only. Status and the outcome fields are the function's,
          // and the rules refuse them from here.
          await ref.set(data, SetOptions(merge: true));
        }
        return ref.id;
      }, operation: 'firestore listings saveDraft');

  @override
  Future<String> uploadListingPhoto(
    List<int> bytes, {
    required String contentType,
  }) => guardFirestore(() async {
    final uid = _requireUid;
    final ext = contentType == 'image/png' ? 'png' : 'jpg';
    final name = '${DateTime.now().millisecondsSinceEpoch}.$ext';
    final ref = _storage.ref('listings/$uid/$name');
    await ref.putData(
      Uint8List.fromList(bytes),
      SettableMetadata(contentType: contentType),
    );
    return ref.getDownloadURL();
  }, operation: 'storage listings upload');

  @override
  Future<PublishResult> publishListing(String listingId) =>
      guardFirestore(() async {
        final result = await _functions
            .httpsCallable(
              'sellerPublishListing',
              options: HttpsCallableOptions(
                timeout: const Duration(seconds: 130),
              ),
            )
            .call<Map<String, dynamic>>({'listingId': listingId});
        final data = result.data;
        return PublishResult(
          shopifyProductId: FirestoreMappers.str(data['shopifyProductId']),
          adopted: FirestoreMappers.boolean(data['adopted']),
          stockSet: FirestoreMappers.boolean(data['stockSet'], true),
        );
      }, operation: 'callable sellerPublishListing');

  @override
  Future<List<ProductCategory>> searchCategories(String query) =>
      guardFirestore(() async {
        if (query.trim().length < 2) return const [];
        final result = await _functions
            .httpsCallable('sellerSearchCategories')
            .call<Map<String, dynamic>>({'query': query.trim()});
        final rows = result.data['categories'];
        return [
          if (rows is List)
            for (final row in rows)
              if (row is Map)
                ProductCategory(
                  id: FirestoreMappers.str(row['id']),
                  name: FirestoreMappers.str(row['name']),
                  fullName: FirestoreMappers.str(row['fullName']),
                  isLeaf: FirestoreMappers.boolean(row['isLeaf'], true),
                ),
        ];
      }, operation: 'callable sellerSearchCategories');

  @override
  Future<void> deleteDraft(String id) => guardFirestore(
    () => _listings.doc(id).delete(),
    operation: 'firestore listings delete',
  );

  static Listing _listing(String id, Map<String, dynamic> data) {
    final updated = data['updatedAt'];
    return Listing(
      id: id,
      sellerUid: FirestoreMappers.str(data['sellerUid']),
      status: ListingStatus.parse(data['status'] as String?),
      title: FirestoreMappers.str(data['title'], 'Untitled'),
      description: FirestoreMappers.str(data['description']),
      priceCents: FirestoreMappers.integer(data['priceCents']),
      quantity: FirestoreMappers.integer(data['quantity']),
      sku: data['sku'] is String ? data['sku'] as String : null,
      imageUrls: FirestoreMappers.strings(data['imageUrls']),
      collectionHandles: FirestoreMappers.strings(data['collectionHandles']),
      tags: FirestoreMappers.strings(data['tags']),
      error: data['error'] is String ? data['error'] as String : null,
      shopifyProductId: data['shopifyProductId'] is String
          ? data['shopifyProductId'] as String
          : null,
      updatedAt: updated is Timestamp ? updated.toDate() : DateTime.now(),
    );
  }
}
