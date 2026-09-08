import 'package:flutter/foundation.dart';

import 'formatting.dart';

/// What "Link my directory account" came back with. [off] means the backend
/// has no directory configured yet (the silent launch-time call never
/// throws for that).
enum DirectoryLinkStatus { linked, alreadyLinked, notFound, off }

@immutable
class DirectoryLinkResult {
  const DirectoryLinkResult({
    required this.status,
    this.orders = 0,
    this.listings = 0,
    this.wpLogin,
    this.note,
  });

  final DirectoryLinkStatus status;
  final int orders;
  final int listings;

  /// The WordPress login the email matched, when it matched one.
  final String? wpLogin;

  /// Something to act on, in the backend's words.
  final String? note;
}

/// The `directory/{uid}` document: whether this account is joined to
/// littlebluecart.com, and what was found there. Written only by the backend.
@immutable
class DirectoryLink {
  const DirectoryLink({
    required this.linked,
    this.wpLogin = '',
    this.wpUserId = 0,
    this.orderCount = 0,
    this.listingCount = 0,
    this.linkedAt,
    this.checkedAt,
  });

  final bool linked;
  final String wpLogin;
  final int wpUserId;
  final int orderCount;
  final int listingCount;
  final DateTime? linkedAt;
  final DateTime? checkedAt;

  /// "Linked as grace" or "Linked" when the match was a customer record only.
  String get label => wpLogin.isEmpty ? 'Linked' : 'Linked as $wpLogin';
}

@immutable
class DirectoryOrderItem {
  const DirectoryOrderItem({
    required this.name,
    required this.quantity,
    required this.totalCents,
  });

  final String name;
  final int quantity;
  final int totalCents;

  String get label => quantity > 1 ? '$name ×$quantity' : name;
}

/// One WooCommerce order from littlebluecart.com.
@immutable
class DirectoryOrder {
  const DirectoryOrder({
    required this.id,
    required this.number,
    required this.status,
    required this.createdAt,
    required this.totalCents,
    required this.currency,
    required this.items,
    required this.viewUrl,
  });

  final String id;
  final String number;

  /// WooCommerce's own status slug: completed, processing, on-hold, pending,
  /// cancelled, refunded, failed.
  final String status;
  final DateTime createdAt;
  final int totalCents;
  final String currency;
  final List<DirectoryOrderItem> items;

  /// The order on the website's My account page.
  final String viewUrl;

  String get totalLabel => Fmt.money(totalCents);

  String get statusLabel => switch (status) {
    'completed' => 'Completed',
    'processing' => 'Processing',
    'on-hold' => 'On hold',
    'pending' => 'Pending payment',
    'cancelled' => 'Cancelled',
    'refunded' => 'Refunded',
    'failed' => 'Failed',
    _ => status.isEmpty ? '' : status[0].toUpperCase() + status.substring(1),
  };

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  /// "Sep 1, 2026".
  String get dateLabel =>
      '${_months[createdAt.month - 1]} ${createdAt.day}, ${createdAt.year}';

  /// "Tax the Rich Hoodie · Sticker ×2".
  String get summary => items.map((i) => i.label).join(' · ');
}
