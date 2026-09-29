import '../billing/billing_service.dart';

/// A store that always works, for the demo and the tests.
///
/// It reports a price and takes a purchase without a network or a real till,
/// so the Monthly card can be tapped through in `run-fixtures` and asserted
/// on in a widget test. The receipt it hands back is obviously fake, which is
/// the point: the live path is the only one that produces a real one, and the
/// server would refuse this.
class FixtureBillingService implements BillingService {
  FixtureBillingService({this.storeHasProduct = true});

  /// False to stand in for a store that has never heard of the product,
  /// which is what hides the card.
  final bool storeHasProduct;

  /// What the last purchase attempt was for, so a test can check it.
  String? lastBought;

  /// Set by a test that wants to see the "they backed out" path.
  PurchaseOutcome nextOutcome = PurchaseOutcome.bought;

  @override
  Future<bool> available() async => true;

  @override
  Future<MembershipOffer?> offer(String productId) async {
    if (!storeHasProduct || productId.isEmpty) return null;
    return MembershipOffer(
      productId: productId,
      price: r'$3.00',
      title: 'Little Blue Market member',
      description: 'A month of keeping the lights on.',
    );
  }

  @override
  Future<PurchaseReceipt> buy(String productId) async {
    lastBought = productId;
    return switch (nextOutcome) {
      PurchaseOutcome.cancelled => const PurchaseReceipt.cancelled(),
      PurchaseOutcome.failed => const PurchaseReceipt.failed(
        'The store would not take that.',
      ),
      final outcome => PurchaseReceipt(
        outcome: outcome,
        store: 'google',
        receipt: 'fixture-receipt',
      ),
    };
  }

  @override
  Future<PurchaseReceipt> restore(String productId) => buy(productId);
}
