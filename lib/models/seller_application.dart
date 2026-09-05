import 'package:flutter/foundation.dart';

import 'formatting.dart';

/// Where an application to sell stands.
enum ApplicationStatus {
  submitted('Under review'),
  approved('Approved'),
  declined('Declined');

  const ApplicationStatus(this.label);
  final String label;

  static ApplicationStatus parse(String? value) =>
      ApplicationStatus.values.firstWhere(
        (s) => s.name == value,
        orElse: () => ApplicationStatus.submitted,
      );
}

/// A member asking to sell, and what the admin said.
@immutable
class SellerApplication {
  const SellerApplication({
    required this.uid,
    required this.status,
    required this.shopName,
    required this.appliedEmail,
    required this.createdAt,
    this.storeUrl = '',
    this.vendorEmail = '',
    this.note = '',
    this.vendorName,
    this.reason,
  });

  final String uid;
  final ApplicationStatus status;
  final String shopName;
  final String appliedEmail;
  final String storeUrl;

  /// The email they use in Shipturtle, when they have one there already.
  final String vendorEmail;
  final String note;

  /// The vendor string the admin approved them as.
  final String? vendorName;

  /// Why it was declined, in the admin's words.
  final String? reason;
  final DateTime createdAt;

  String get age => Fmt.relative(createdAt);
}

/// What the Apply to sell form hands over.
@immutable
class SellerApplicationDraft {
  const SellerApplicationDraft({
    required this.shopName,
    this.storeUrl = '',
    this.vendorEmail = '',
    this.note = '',
  });

  final String shopName;
  final String storeUrl;
  final String vendorEmail;
  final String note;
}
