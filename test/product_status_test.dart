import 'package:flutter_test/flutter_test.dart';
import 'package:little_blue_market/data/firebase/mappers.dart';
import 'package:little_blue_market/models/models.dart';

/// A product deleted or archived on the store is gone for everyone; a draft
/// is the seller's alone; only an active one is on sale.
void main() {
  Product read(Map<String, dynamic> data) => FirestoreMappers.product('p1', {
    'title': 'Soap',
    'priceCents': 800,
    ...data,
  });

  test('the mirror status decides who sees a product', () {
    expect(read({'active': true, 'status': 'active'}).active, isTrue);
    expect(read({'active': true, 'status': 'active'}).isGone, isFalse);
    expect(read({'active': false, 'status': 'draft'}).isGone, isFalse);
    expect(read({'active': false, 'status': 'archived'}).isGone, isTrue);
    expect(read({'active': false, 'status': 'deleted'}).isGone, isTrue);
  });

  test('older rows without a status are read off their flags', () {
    expect(read({}).status, 'active');
    expect(read({'active': false}).status, 'draft');
    expect(read({'active': false, 'deletedAt': 1}).status, 'deleted');
    expect(read({'active': false, 'deletedAt': 1}).isGone, isTrue);
  });
}
