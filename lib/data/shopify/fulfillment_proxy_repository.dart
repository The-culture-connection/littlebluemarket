import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../models/models.dart';
import '../firebase/firestore_errors.dart';
import '../firebase/mappers.dart';
import '../repositories/repositories.dart';

/// Shipments, in both directions.
///
/// Reads come from the order documents the pipeline maintains; the one write --
/// a seller marking an order shipped -- goes through a Cloud Function, because
/// creating a fulfilment needs credentials the app must never hold.
class FulfillmentProxyRepository implements FulfillmentRepository {
  FulfillmentProxyRepository({
    required FirebaseFirestore firestore,
    required FirebaseFunctions functions,
    required this.uid,
  }) : _db = firestore,
       _functions = functions;

  final FirebaseFirestore _db;
  final FirebaseFunctions _functions;
  final String? uid;

  /// Packages you sent as a seller.
  @override
  Stream<List<Shipment>> watchSending() => _shipments('sellerUids');

  /// Packages coming to you as a buyer.
  @override
  Stream<List<Shipment>> watchReceiving() => _shipments('buyerUid');

  Stream<List<Shipment>> _shipments(String field) {
    final id = uid;
    if (id == null) return Stream.value(const []);

    final query = field == 'buyerUid'
        ? _db.collection('orders').where(field, isEqualTo: id)
        : _db.collection('orders').where(field, arrayContains: id);

    return query
        .orderBy('placedAt', descending: true)
        .limit(50)
        .snapshots()
        .map((snapshot) {
          final shipments = <Shipment>[];
          for (final doc in snapshot.docs) {
            final list = doc.data()['shipments'];
            if (list is! List) continue;
            for (final item in list) {
              if (item is Map) {
                shipments.add(
                  FirestoreMappers.shipment(Map<String, dynamic>.from(item)),
                );
              }
            }
          }
          return shipments;
        })
        .guarded();
  }

  @override
  Future<void> addTracking({
    required String orderId,
    required String trackingNumber,
    required String carrier,
  }) => guardFirestore(() async {
    final tracking = trackingNumber.trim();
    if (tracking.isEmpty) {
      throw const ValidationException(
        'Enter a tracking number',
        field: 'trackingNumber',
      );
    }

    // One call, so the courier and the buyer learn the same number: the
    // function creates the fulfilment upstream and writes it onto the order.
    await _functions.httpsCallable('fulfillmentAddTracking').call({
      'orderId': orderId.trim(),
      'trackingNumber': tracking,
      'carrier': carrier,
    });
  });
}
