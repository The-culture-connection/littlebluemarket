import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../models/models.dart';
import '../repositories/repositories.dart';
import 'firestore_errors.dart';
import 'mappers.dart';

/// The `promos` collection: adverts and Little Blue announcements, live.
///
/// Reads are open to anyone, including a guest, because a popup is the first
/// thing a curious visitor might see. Writes are refused by the rules; the
/// two counters go through a callable, so a phone can add to a number it
/// cannot otherwise touch.
class FirestorePromoRepository implements PromoRepository {
  FirestorePromoRepository({
    required FirebaseFirestore firestore,
    required FirebaseFunctions functions,
  }) : _db = firestore,
       _functions = functions;

  final FirebaseFirestore _db;
  final FirebaseFunctions _functions;

  @override
  Future<List<Promo>> live({int limit = 20}) => guardFirestore(() async {
    // `active` is the only filter Firestore can serve here: a window is two
    // inequalities on two different fields, which it cannot index together.
    // The window is applied on the phone, over at most `limit` rows.
    final snapshot = await _db
        .collection('promos')
        .where('active', isEqualTo: true)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .get();
    final now = DateTime.now();
    final promos = [
      for (final doc in snapshot.docs)
        FirestoreMappers.promo(doc.id, doc.data()),
    ];
    return [
      for (final promo in promos)
        if (promo.isLiveAt(now)) promo,
    ];
  }, operation: 'firestore promos');

  @override
  Future<void> recordSeen(String id) => _record(id, 'seen');

  @override
  Future<void> recordTap(String id) => _record(id, 'tap');

  /// Never allowed to fail loudly: a counter that did not land must not put
  /// an error strip over a popup the person is already reading.
  Future<void> _record(String id, String event) async {
    try {
      await _functions
          .httpsCallable('promoRecord')
          .call<Map<String, dynamic>>({'id': id, 'event': event});
    } catch (_) {
      // Counted nowhere, seen anyway. The number is for Grace, not for the
      // person holding the phone.
    }
  }
}
