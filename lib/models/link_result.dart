import 'package:flutter/foundation.dart';

/// What linking an app account to the store found.
///
/// Returned by `ProfileRepository.linkStoreAccounts`, which the session calls
/// once for every verified, unlinked account. A buyer with history gets
/// [backfilledOrders]; a vendor gets [linkedVendor], which is not yet a grant
/// (that is the claim code, or the roster match on the backend).
@immutable
class LinkResult {
  const LinkResult({
    this.linkedCustomer = false,
    this.linkedVendor = false,
    this.backfilledOrders = 0,
    this.backfilledItems = 0,
    this.alreadyLinked = false,
  });

  final bool linkedCustomer;
  final bool linkedVendor;
  final int backfilledOrders;
  final int backfilledItems;

  /// Nothing new happened: the account was linked on an earlier call.
  final bool alreadyLinked;
}
