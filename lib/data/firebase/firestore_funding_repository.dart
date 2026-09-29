import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/funding.dart';
import '../repositories/funding_repository.dart';
import 'firestore_errors.dart';

/// `funding/{yyyy-mm}`: readable by members, written only by the order
/// webhook and by Grace.
class FirestoreFundingRepository implements FundingRepository {
  FirestoreFundingRepository({required FirebaseFirestore firestore})
    : _db = firestore;

  final FirebaseFirestore _db;

  @override
  Future<Funding?> month(String month) => guardFirestore(() async {
    if (month.isEmpty) return null;
    final doc = await _db.collection('funding').doc(month).get();
    final data = doc.data();
    if (data == null) return null;

    // Read one field at a time rather than through a shared mapper: this is
    // the only place these fields exist, and the shape is the thing the
    // transparency block promises to be honest about.
    final costs = <String, int>{};
    final raw = data['costs'];
    if (raw is Map) {
      for (final entry in raw.entries) {
        final label = entry.key.toString();
        final value = entry.value;
        final cents = value is num ? value.round() : int.tryParse('$value');
        if (label.isNotEmpty && cents != null) costs[label] = cents;
      }
    }

    int cents(Object? value) => value is num ? value.round() : 0;
    return Funding(
      month: doc.id,
      raisedCents: cents(data['raisedCents']),
      budgetCents: cents(data['budgetCents']),
      donors: cents(data['donors']),
      costs: costs,
    );
  }, operation: 'firestore funding/$month');
}
