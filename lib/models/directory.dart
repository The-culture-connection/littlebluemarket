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

/// One business listing on littlebluecart.com, as the public mirror carries
/// it: what the website already shows to anyone, with term ids already
/// turned into names.
@immutable
class DirectoryListing {
  const DirectoryListing({
    required this.id,
    required this.ownerUid,
    required this.title,
    required this.status,
    required this.link,
    this.website = '',
    this.email = '',
    this.phone = '',
    this.storeLink = '',
    this.locationLabel = '',
    this.street = '',
    this.city = '',
    this.state = '',
    this.zip = '',
    this.address = '',
    this.categories = const [],
    this.tags = const [],
    this.locations = const [],
    this.plan = '',
    this.description = '',
    this.imageUrl = '',
    this.updatedAt,
  });

  /// The WordPress post id.
  final String id;

  /// The listing's own words, as far as the site shares them (about a
  /// sentence and a half).
  final String description;
  final String ownerUid;
  final String title;

  /// WordPress's own status: publish, pending, draft, future, private.
  final String status;

  /// The listing page on littlebluecart.com.
  final String link;
  final String website;
  final String email;
  final String phone;

  /// The seller's Little Blue Market storefront, when they filled it in.
  final String storeLink;

  /// The directory's own location label, e.g. "*Online/Virtual Business".
  final String locationLabel;
  final String street;
  final String city;
  final String state;
  final String zip;

  /// The full address on one line, as the site displays it.
  final String address;
  final List<String> categories;

  /// Ownership tags: Woman-Owned, BIPOC-Owned, Ally…
  final List<String> tags;

  /// Directory locations, usually a state name.
  final List<String> locations;
  final String plan;
  final String imageUrl;
  final DateTime? updatedAt;

  bool get isPublished => status == 'publish';

  String get statusLabel => switch (status) {
    'publish' => 'Published',
    'pending' => 'Under review',
    'draft' => 'Draft',
    'future' => 'Scheduled',
    'private' => 'Private',
    _ => status,
  };

  /// "FL", or the directory's location when the address has no state.
  String get stateLabel {
    if (state.isNotEmpty) return state;
    if (locations.isNotEmpty) return locations.first;
    return locationLabel.replaceFirst('*', '');
  }

  /// "DIRECTORY SHOWCASE PLAN" → "Showcase plan".
  String get planLabel {
    final words = plan
        .replaceFirst(RegExp('^DIRECTORY ', caseSensitive: false), '')
        .trim()
        .toLowerCase();
    if (words.isEmpty) return '';
    return words[0].toUpperCase() + words.substring(1);
  }

  Uri? get websiteUri {
    if (website.isEmpty) return null;
    final full = website.startsWith(RegExp('https?://'))
        ? website
        : 'https://$website';
    return Uri.tryParse(full);
  }

  Uri? get callUri {
    final digits = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    return digits.isEmpty ? null : Uri(scheme: 'tel', path: digits);
  }

  Uri? get emailUri => email.isEmpty ? null : Uri(scheme: 'mailto', path: email);

  /// A `geo:` search, which Android hands to whichever maps app is installed.
  Uri? get directionsUri => address.isEmpty
      ? null
      : Uri.parse('geo:0,0?q=${Uri.encodeComponent(address)}');

  Uri? get linkUri => link.isEmpty ? null : Uri.tryParse(link);
}
