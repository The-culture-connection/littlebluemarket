import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../../models/models.dart';
import '../repositories/repositories.dart';
import 'firestore_errors.dart';
import 'mappers.dart';

class FirestoreProfileRepository implements ProfileRepository {
  FirestoreProfileRepository({
    required FirebaseFirestore firestore,
    required FirebaseStorage storage,
    required FirebaseFunctions functions,
    required FirebaseAuth auth,
    required this.uid,
  }) : _db = firestore,
       _storage = storage,
       _functions = functions,
       _auth = auth;

  final FirebaseFirestore _db;
  final FirebaseStorage _storage;
  final FirebaseFunctions _functions;
  final FirebaseAuth _auth;

  /// Null while signed out. Every write checks it rather than assuming.
  final String? uid;

  CollectionReference<Map<String, dynamic>> get _users =>
      _db.collection('users');

  String get _requireUid {
    final id = uid;
    if (id == null) throw const UnauthenticatedException();
    return id;
  }

  @override
  Stream<Person?> watchPerson(String id) => _users
      .doc(id)
      .snapshots()
      .map((doc) {
        final data = doc.data();
        // Null rather than throwing: "authenticated but no profile yet" is a
        // state the app renders, not an error.
        return data == null ? null : FirestoreMappers.person(doc.id, data);
      })
      .guarded(operation: 'firestore users/{uid}');

  @override
  Future<Person> person(String id) => guardFirestore(() async {
    final doc = await _users.doc(id).get();
    final data = doc.data();
    if (data == null) throw NotFoundException('person', id);
    return FirestoreMappers.person(doc.id, data);
  });

  @override
  Future<List<Person>> people(List<String> ids) => guardFirestore(() async {
    if (ids.isEmpty) return const [];

    // whereIn caps at 30 values, so a long list is fetched in chunks rather
    // than silently truncated.
    const chunkSize = 30;
    final people = <Person>[];
    for (var i = 0; i < ids.length; i += chunkSize) {
      final chunk = ids.sublist(
        i,
        i + chunkSize > ids.length ? ids.length : i + chunkSize,
      );
      final snapshot = await _users
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      people.addAll(
        snapshot.docs.map((doc) => FirestoreMappers.person(doc.id, doc.data())),
      );
    }
    return people;
  });

  @override
  Future<List<Person>> searchPeople(String query, {int limit = 10}) =>
      guardFirestore(() async {
        final normalized = query.trim().toLowerCase().replaceFirst('@', '');
        if (normalized.isEmpty) return const [];

        // A prefix scan on the normalised handle.  is the highest code
        // point Firestore will order, so this is "everything starting with".
        final snapshot = await _users
            .where('handleLower', isGreaterThanOrEqualTo: normalized)
            .where('handleLower', isLessThan: '$normalized')
            .limit(limit)
            .get();
        return snapshot.docs
            .map((doc) => FirestoreMappers.person(doc.id, doc.data()))
            .toList();
      });

  @override
  Future<void> updateProfile(ProfileEdit edit) => guardFirestore(() async {
    final id = _requireUid;

    final handle = edit.handle?.trim();
    if (handle != null && !await handleAvailable(handle)) {
      throw const ValidationException('That handle is taken', field: 'handle');
    }

    // The first save *creates* the profile, and the rules insist a new
    // document carries its money counters at zero — a client that could omit
    // them could also invent them. Written here, once, and never again: on an
    // existing document these fields are locked to the order pipeline.
    final exists = (await _users.doc(id).get()).exists;

    await _users.doc(id).set({
      if (!exists) ...{
        'revenueCents': 0,
        'grossSalesCents': 0,
        'purchaseCount': 0,
        'postCount': 0,
        'createdAt': FieldValue.serverTimestamp(),
      },
      if (edit.name != null) 'name': edit.name!.trim(),
      if (handle != null) ...{
        'handle': handle,
        // Stored lowercase alongside the display form, because Firestore
        // cannot do a case-insensitive query.
        'handleLower': handle.toLowerCase().replaceFirst('@', ''),
      },
      if (edit.bio != null) 'bio': edit.bio!.trim(),
      if (edit.tags != null) 'tags': edit.tags,
      if (edit.avatarUrl != null) 'avatarUrl': edit.avatarUrl,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }, operation: 'firestore users/{uid} updateProfile');

  @override
  Future<String> uploadAvatar(List<int> bytes, {required String contentType}) =>
      guardFirestore(() async {
        final id = _requireUid;
        final ref = _storage.ref('avatars/$id/profile.jpg');
        await ref.putData(
          Uint8List.fromList(bytes),
          SettableMetadata(contentType: contentType),
        );
        final url = await ref.getDownloadURL();
        await _users.doc(id).set({'avatarUrl': url}, SetOptions(merge: true));
        return url;
      });

  @override
  Future<bool> handleAvailable(String handle) => guardFirestore(() async {
    final normalized = handle.trim().toLowerCase().replaceFirst('@', '');
    if (normalized.isEmpty) return false;

    final snapshot = await _users
        .where('handleLower', isEqualTo: normalized)
        .limit(1)
        .get();
    if (snapshot.docs.isEmpty) return true;
    // Keeping your own handle is not a collision.
    return snapshot.docs.first.id == uid;
  });

  @override
  Future<SellerGrant> requestSellerStatus(String claimCode) =>
      guardFirestore(() async {
        _requireUid;

        // Nothing about the grant is decided here. The callable checks the
        // verified email claim, consumes the code, reserves the vendor name
        // and writes `sellers/{uid}` in one transaction — all of it on
        // documents no client may write.
        final result = await _functions
            .httpsCallable('sellerClaimVendor')
            .call<Map<String, dynamic>>({'claimCode': claimCode.trim()});

        final data = result.data;

        // The grant is a **custom claim**, which reaches the client only on
        // the next token refresh — up to an hour. Forcing it here is what
        // makes the Products tab appear now rather than tomorrow, and a
        // seller staring at an unchanged screen would reasonably conclude
        // the claim failed.
        await _auth.currentUser?.getIdToken(true);

        return SellerGrant(
          vendorName: FirestoreMappers.str(data['vendorName']),
          shipturtleVendorId: data['shipturtleVendorId'] as String?,
        );
      }, operation: 'callable sellerClaimVendor');

  @override
  Future<LinkResult> linkStoreAccounts() => guardFirestore(() async {
    _requireUid;
    // No arguments: the function reads the email from the verified token,
    // never from the request. A client-supplied address would let anyone
    // inherit a stranger's order history.
    final result = await _functions
        .httpsCallable('linkAccounts')
        .call<Map<String, dynamic>>(const {});
    final data = result.data;
    return LinkResult(
      linkedCustomer: FirestoreMappers.boolean(data['linkedCustomer']),
      linkedVendor: FirestoreMappers.boolean(data['linkedVendor']),
      backfilledOrders: FirestoreMappers.integer(data['backfilledOrders']),
      backfilledItems: FirestoreMappers.integer(data['backfilledItems']),
      alreadyLinked: FirestoreMappers.boolean(data['alreadyLinked']),
    );
  }, operation: 'callable linkAccounts');

  @override
  Future<List<Address>> addresses() => guardFirestore(() async {
    final snapshot = await _users
        .doc(_requireUid)
        .collection('addresses')
        .get();
    return snapshot.docs
        .map((doc) => FirestoreMappers.address(doc.id, doc.data()))
        .toList();
  });

  @override
  Future<void> saveAddress(Address address) => guardFirestore(() async {
    final collection = _users.doc(_requireUid).collection('addresses');
    final data = FirestoreMappers.addressToJson(address);

    if (address.isDefault) {
      // Exactly one default, so clearing the others is part of the same write.
      final batch = _db.batch();
      final existing = await collection
          .where('isDefault', isEqualTo: true)
          .get();
      for (final doc in existing.docs) {
        batch.update(doc.reference, {'isDefault': false});
      }
      final target = address.id == null
          ? collection.doc()
          : collection.doc(address.id);
      batch.set(target, data, SetOptions(merge: true));
      await batch.commit();
      return;
    }

    if (address.id == null) {
      await collection.add(data);
    } else {
      await collection.doc(address.id).set(data, SetOptions(merge: true));
    }
  });

  @override
  Future<void> deleteAddress(String id) => guardFirestore(
    () => _users.doc(_requireUid).collection('addresses').doc(id).delete(),
  );
}
