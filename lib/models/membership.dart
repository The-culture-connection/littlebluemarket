/// The monthly membership, as store product identifiers.
///
/// A recurring digital membership is Apple's and Google's business, not
/// Shopify's: it is a subscription to something inside the app, so it goes
/// through their billing and their cut. That is why the Chip in page has no
/// Monthly card — one-time chip-ins are ordinary store goods bought in the
/// ordinary store checkout, and the two must not be confused in the copy or
/// in the code.
///
/// **Nothing calls this yet.** `in_app_purchase` is in `pubspec.yaml` so the
/// Android manifest declares `com.android.vending.BILLING`, because Play
/// will not let a subscription product be configured until an uploaded build
/// declares it. The purchase flow, the restore, the server-side receipt
/// check and the badge are Phase 10.
abstract final class Membership {
  /// The App Store product, from Grace, 2026-09-29.
  static const appleProductId = 'lbm_member_monthly2';

  /// The Play product. Not set yet.
  ///
  /// Deliberately empty rather than a guess: a wrong identifier here fails
  /// at the till on somebody's phone, and the two stores do not have to
  /// agree on one. Phase 10 fills it in from the Play Console.
  static const googleProductId = '';

  /// Every identifier the app should query, for whichever store it is on.
  static Set<String> get productIds =>
      {appleProductId, googleProductId}..removeWhere((id) => id.isEmpty);

  /// Whether a store subscription can be offered on this build at all.
  static bool get isConfigured => productIds.isNotEmpty;
}
