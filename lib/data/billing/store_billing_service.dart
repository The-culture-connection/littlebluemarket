import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import 'billing_service.dart';

/// The real thing: Apple's and Google's billing, through `in_app_purchase`.
///
/// The plugin's shape is a stream of purchase updates rather than a future
/// per purchase, because a purchase can finish while the app is closed and
/// arrive at the next launch. This wraps that into one await, and leaves the
/// stream listening so a purchase that lands late is still completed.
class StoreBillingService implements BillingService {
  StoreBillingService({InAppPurchase? plugin})
    : _plugin = plugin ?? InAppPurchase.instance;

  final InAppPurchase _plugin;

  /// Whoever is currently waiting on a purchase of this product.
  final _waiting = <String, Completer<PurchaseReceipt>>{};
  StreamSubscription<List<PurchaseDetails>>? _updates;

  /// 'apple' or 'google'. The server needs to know who to ask, and the phone
  /// is the only one who knows which store it bought from.
  static String get _store =>
      Platform.isIOS || Platform.isMacOS ? 'apple' : 'google';

  @override
  Future<bool> available() async {
    // A browser has no store, and asking crashes rather than answering.
    if (kIsWeb) return false;
    try {
      return await _plugin.isAvailable();
    } on Exception {
      return false;
    }
  }

  @override
  Future<MembershipOffer?> offer(String productId) async {
    if (productId.isEmpty || !await available()) return null;
    final response = await _plugin.queryProductDetails({productId});
    final details = response.productDetails.firstWhereOrNull(
      (p) => p.id == productId,
    );
    if (details == null) return null;
    return MembershipOffer(
      productId: details.id,
      price: details.price,
      title: details.title,
      description: details.description,
    );
  }

  @override
  Future<PurchaseReceipt> buy(String productId) async {
    if (!await available()) {
      return const PurchaseReceipt.failed(
        'This phone cannot reach the app store right now.',
      );
    }
    final response = await _plugin.queryProductDetails({productId});
    final details = response.productDetails.firstWhereOrNull(
      (p) => p.id == productId,
    );
    if (details == null) {
      return const PurchaseReceipt.failed(
        'The store does not have that subscription yet.',
      );
    }

    _listen();
    final waiter = _waiting[productId] = Completer<PurchaseReceipt>();
    final started = await _plugin.buyNonConsumable(
      purchaseParam: PurchaseParam(productDetails: details),
    );
    if (!started) {
      _waiting.remove(productId);
      return const PurchaseReceipt.failed('The store would not start that.');
    }
    return waiter.future;
  }

  @override
  Future<PurchaseReceipt> restore(String productId) async {
    if (!await available()) {
      return const PurchaseReceipt.failed(
        'This phone cannot reach the app store right now.',
      );
    }
    _listen();
    final waiter = _waiting[productId] = Completer<PurchaseReceipt>();
    await _plugin.restorePurchases();
    // A restore is silent when there is nothing to restore: the stream simply
    // never mentions this product. Without a deadline the button would spin
    // for ever on the commonest case of all, which is not being a member.
    return waiter.future.timeout(
      const Duration(seconds: 12),
      onTimeout: () {
        _waiting.remove(productId);
        return const PurchaseReceipt.failed(
          'The store has no membership on this account.',
        );
      },
    );
  }

  void _listen() {
    _updates ??= _plugin.purchaseStream.listen(
      _onUpdates,
      onError: (Object error) {
        for (final waiter in _waiting.values.toList()) {
          if (!waiter.isCompleted) {
            waiter.complete(PurchaseReceipt.failed('$error'));
          }
        }
        _waiting.clear();
      },
    );
  }

  Future<void> _onUpdates(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      if (purchase.status == PurchaseStatus.pending) continue;

      // Always, and before anything else can go wrong: an uncompleted
      // purchase is re-delivered at every launch for ever, and on iOS it
      // blocks the next one.
      if (purchase.pendingCompletePurchase) {
        await _plugin.completePurchase(purchase);
      }

      final waiter = _waiting.remove(purchase.productID);
      if (waiter == null || waiter.isCompleted) continue;

      waiter.complete(switch (purchase.status) {
        PurchaseStatus.purchased => PurchaseReceipt(
          outcome: PurchaseOutcome.bought,
          store: _store,
          receipt: _receiptOf(purchase),
        ),
        PurchaseStatus.restored => PurchaseReceipt(
          outcome: PurchaseOutcome.restored,
          store: _store,
          receipt: _receiptOf(purchase),
        ),
        PurchaseStatus.canceled => const PurchaseReceipt.cancelled(),
        _ => PurchaseReceipt.failed(
          purchase.error?.message ?? 'The store would not take that.',
        ),
      });
    }
  }

  /// What the server sends back to the store.
  ///
  /// The two stores mean different things by "the receipt": Apple's server
  /// API looks up a transaction id, and Google's looks up the purchase token.
  /// `purchaseID` is the transaction id on iOS and the order id on Android,
  /// so Android has to use the verification data instead.
  static String _receiptOf(PurchaseDetails purchase) => _store == 'apple'
      ? (purchase.purchaseID ?? '')
      : purchase.verificationData.serverVerificationData;

  void dispose() {
    _updates?.cancel();
    _updates = null;
  }
}

extension _FirstOrNull<T> on List<T> {
  T? firstWhereOrNull(bool Function(T) test) {
    for (final item in this) {
      if (test(item)) return item;
    }
    return null;
  }
}
