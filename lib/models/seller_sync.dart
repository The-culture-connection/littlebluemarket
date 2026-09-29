import 'package:flutter/foundation.dart';

/// What "Check my seller status" came back with.
enum SellerSyncStatus { granted, alreadySeller, notFound, undecided }

@immutable
class SellerSyncResult {
  const SellerSyncResult({required this.status, this.vendorName, this.note});

  final SellerSyncStatus status;
  final String? vendorName;

  /// Why the roster match did not become a grant, in the backend's words.
  final String? note;
}

/// Links the app needs that differ between the dev and the real store.
@immutable
class AppConfig {
  const AppConfig({
    required this.registrationUrl,
    required this.shipturtleUrl,
    this.directoryAddListingUrl = '',
    this.donationChipInHandle = '',
    this.donationRoundUpHandle = '',
    this.membershipAppleProductId = '',
    this.membershipPlayProductId = '',
  });

  /// Where a new seller applies, on the website.
  final String registrationUrl;

  /// The vendor dashboard, where shipping is managed.
  final String shipturtleUrl;

  /// Where a business adds itself to the littlebluecart.com directory (the
  /// website form). Staging on dev, the live site in production.
  final String directoryAddListingUrl;

  /// The two hidden Shopify products that take donations. Empty means the
  /// environment has none, and every donation surface hides itself: the
  /// feature ships dark and is turned on by setting a value.
  final String donationChipInHandle;
  final String donationRoundUpHandle;

  /// The monthly membership, as each store calls it. Empty means that
  /// store has no such product and the Monthly card hides itself: the
  /// same dark ship as the donation handles above.
  final String membershipAppleProductId;
  final String membershipPlayProductId;

  bool get canChipIn => donationChipInHandle.isNotEmpty;
  bool get canRoundUp => donationRoundUpHandle.isNotEmpty;
}
