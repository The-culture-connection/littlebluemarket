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
  const AppConfig({required this.registrationUrl, required this.shipturtleUrl});

  /// Where a new seller applies, on the website.
  final String registrationUrl;

  /// The vendor dashboard, where shipping is managed.
  final String shipturtleUrl;
}
