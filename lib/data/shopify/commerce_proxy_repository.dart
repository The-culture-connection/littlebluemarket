// Firestore exports its own `Order` (an index direction); ours wins here.
import 'package:cloud_firestore/cloud_firestore.dart' hide Order;
import 'package:cloud_functions/cloud_functions.dart';

import '../../models/models.dart';
import '../firebase/firestore_errors.dart';
import '../firebase/mappers.dart';
import '../repositories/repositories.dart';
import 'commerce_mappers.dart';

/// Cart, checkout and orders.
///
/// The app holds no storefront credential and never calls the storefront. Every
/// commerce call is a Cloud Function, which carries the Firebase ID token
/// automatically — so the proxy knows who is asking without the client holding
/// anything worth stealing.
///
/// This class is the one meant to be thrown away. When the storefront is
/// replaced, [CommerceRepository] keeps its shape and only what is behind these
/// six methods changes.
class CommerceProxyRepository implements CommerceRepository {
  CommerceProxyRepository({
    required FirebaseFunctions functions,
    required FirebaseFirestore firestore,
    required this.uid,
  }) : _functions = functions,
       _db = firestore;

  final FirebaseFunctions _functions;
  final FirebaseFirestore _db;
  final String? uid;

  String get _requireUid {
    final id = uid;
    if (id == null) throw const UnauthenticatedException();
    return id;
  }

  Future<Map<String, dynamic>> _call(
    String name, [
    Map<String, dynamic>? payload,
  ]) => guardFirestore(() async {
    final result = await _functions
        .httpsCallable(name)
        .call<Map<String, dynamic>>(payload ?? const {});
    return result.data;
  }, operation: 'callable $name');

  /// The cart lives in our own store, so it renders instantly and offline and
  /// survives the storefront being swapped. Only the checkout handoff leaves.
  @override
  Stream<Cart> watchCart() {
    final id = uid;
    if (id == null) return Stream.value(const Cart.empty());

    return _db
        .collection('carts')
        .doc(id)
        .snapshots()
        .map((doc) => CommerceMappers.cart(doc.id, doc.data() ?? const {}))
        .guarded(operation: 'firestore carts/{uid}');
  }

  @override
  Future<Cart> addLine({
    required String productId,
    String? variantId,
    int quantity = 1,
  }) async {
    // Priced and stock-checked server-side. A client-supplied price would be
    // the obvious thing to tamper with.
    final data = await _call('commerceAddLine', {
      'productId': productId,
      'variantId': ?variantId,
      'quantity': quantity,
    });
    return CommerceMappers.cart(_requireUid, data);
  }

  @override
  Future<AddManyResult> addManyLines(List<String> productIds) async {
    final data = await _call('commerceAddManyLines', {
      'productIds': productIds,
    });
    final skippedRows = data['skipped'];
    return AddManyResult(
      cart: CommerceMappers.cart(
        _requireUid,
        Map<String, dynamic>.from(data['cart'] as Map),
      ),
      added: [
        if (data['added'] is List)
          for (final id in data['added'] as List) id.toString(),
      ],
      skipped: {
        if (skippedRows is List)
          for (final row in skippedRows)
            if (row is Map)
              row['productId'].toString(): row['reason'].toString(),
      },
    );
  }

  @override
  Future<Cart> updateLine({
    required String lineId,
    required int quantity,
  }) async {
    final data = await _call('commerceUpdateLine', {
      'lineId': lineId,
      'quantity': quantity,
    });
    return CommerceMappers.cart(_requireUid, data);
  }

  @override
  Future<Cart> removeLine(String lineId) async {
    final data = await _call('commerceRemoveLine', {'lineId': lineId});
    return CommerceMappers.cart(_requireUid, data);
  }

  @override
  Future<Cart> clearCart() async {
    final data = await _call('commerceClearCart');
    return CommerceMappers.cart(_requireUid, data);
  }

  @override
  Future<CheckoutHandoff> beginCheckout() async {
    final data = await _call('commerceBeginCheckout');
    final url = data['checkoutUrl'];
    if (url is! String) {
      throw const BackendException('Checkout did not return a URL');
    }
    // The function stamps this account onto the cart, which is what lets the
    // resulting order be attributed back here. Nothing about the returned
    // handoff claims the purchase happened.
    return CheckoutHandoff(
      cartId: FirestoreMappers.str(data['cartId']),
      webUrl: Uri.parse(url),
    );
  }

  @override
  Future<Page<Order>> orders({String? cursor}) => guardFirestore(() async {
    var query = _db
        .collection('orders')
        .where('buyerUid', isEqualTo: _requireUid)
        .orderBy('placedAt', descending: true)
        .limit(20);
    if (cursor != null) {
      final anchor = await _db.collection('orders').doc(cursor).get();
      if (anchor.exists) query = query.startAfterDocument(anchor);
    }

    final snapshot = await query.get();
    return Page(
      items: snapshot.docs
          .map((doc) => CommerceMappers.order(doc.id, doc.data()))
          .toList(),
      cursor: snapshot.docs.length < 20 ? null : snapshot.docs.last.id,
    );
  });

  @override
  Future<Order> order(String id) => guardFirestore(() async {
    final doc = await _db.collection('orders').doc(id).get();
    final data = doc.data();
    if (data == null) throw NotFoundException('order', id);
    return CommerceMappers.order(doc.id, data);
  });

  /// What this account has bought.
  ///
  /// Written by the order pipeline, so it covers orders placed on the website
  /// as well as in the app — which is what makes the two front doors one
  /// product.
  @override
  Stream<List<Purchase>> watchPurchases(String uid) => _db
      .collection('users')
      .doc(uid)
      .collection('purchases')
      .orderBy('purchasedAt', descending: true)
      .snapshots()
      .map(
        (snapshot) => snapshot.docs
            .map((doc) => FirestoreMappers.purchase(doc.id, doc.data()))
            .toList(),
      )
      .guarded(operation: 'firestore users/{uid}/purchases');
}
