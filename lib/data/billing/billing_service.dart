/// The stores' own billing, as the app sees it.
///
/// Pure Dart on purpose, like [PushService] and the repositories: the live
/// implementation wraps `in_app_purchase`, the fixture one pretends, and no
/// screen knows which it has.
///
/// A recurring digital membership has to go through Apple and Google, so this
/// is the one piece of money in the app that does not go through Shopify. The
/// phone's only jobs are to show the price, start the purchase, and hand the
/// receipt to the server. **Whether somebody is a member is never decided
/// here**: the server asks the store and writes the answer, for the same
/// reason a seller cannot write their own revenue.
library;

import 'package:flutter/foundation.dart';

/// What the store says this subscription costs, in the buyer's own currency.
///
/// The price is a formatted string and not cents on purpose: the store
/// returns "$3.00", "£2.49", "¥400" already localised, and an app that
/// reformats it invents an exchange rate it does not have.
@immutable
class MembershipOffer {
  const MembershipOffer({
    required this.productId,
    required this.price,
    this.title = '',
    this.description = '',
  });

  final String productId;

  /// Ready to show, from the store. Never parsed.
  final String price;
  final String title;
  final String description;
}

/// How a purchase attempt ended.
enum PurchaseOutcome {
  /// The store took the money and gave us a receipt to verify.
  bought,

  /// They backed out. Not an error, and not worth a message.
  cancelled,

  /// They already had it: a restore, or buying on a second phone.
  restored,

  /// The store said no, or the phone could not reach it.
  failed,
}

/// A purchase, as it comes back from the store.
@immutable
class PurchaseReceipt {
  const PurchaseReceipt({
    required this.outcome,
    this.store = '',
    this.receipt = '',
    this.message = '',
  });

  const PurchaseReceipt.cancelled() : this(outcome: PurchaseOutcome.cancelled);

  const PurchaseReceipt.failed(String message)
    : this(outcome: PurchaseOutcome.failed, message: message);

  final PurchaseOutcome outcome;

  /// 'apple' or 'google', which is what the server needs to know who to ask.
  final String store;

  /// What the server sends to the store: the transaction id on Apple, the
  /// purchase token on Google. Not a thing to display, ever.
  final String receipt;

  /// Why it failed, in the store's words, for the strip at the bottom.
  final String message;

  bool get isWin =>
      outcome == PurchaseOutcome.bought || outcome == PurchaseOutcome.restored;
}

abstract interface class BillingService {
  /// Whether this device can buy at all. False in a browser, on an emulator
  /// without the Play Store, and while the store is unreachable.
  Future<bool> available();

  /// The subscription's price from the store, or null when the store has
  /// never heard of [productId]. Null is the honest answer that hides the
  /// card: a price we invented would be a price we might charge wrongly.
  Future<MembershipOffer?> offer(String productId);

  /// Starts the purchase and waits for the store to finish with it.
  ///
  /// Completes the purchase with the store before returning, so the phone
  /// does not get asked again on the next launch.
  Future<PurchaseReceipt> buy(String productId);

  /// "I already paid": asks the store for what this account owns.
  Future<PurchaseReceipt> restore(String productId);
}
