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
    Map<String, int> centsMap(Object? raw) {
      final out = <String, int>{};
      if (raw is! Map) return out;
      for (final entry in raw.entries) {
        final label = entry.key.toString();
        final value = entry.value;
        final cents = value is num ? value.round() : int.tryParse('$value');
        if (label.isNotEmpty && cents != null) out[label] = cents;
      }
      return out;
    }

    final costs = centsMap(data['costs']);
    // Where it came from, by name. The webhook writes 'shopify'; Phase 10's
    // membership adds its own key without a migration.
    final sources = centsMap(data['sources']);

    int cents(Object? value) => value is num ? value.round() : 0;
    return Funding(
      month: doc.id,
      raisedCents: cents(data['raisedCents']),
      budgetCents: cents(data['budgetCents']),
      donors: cents(data['donors']),
      costs: costs,
      sources: sources,
    );
  }, operation: 'firestore funding/$month');
}
