import 'package:flutter/foundation.dart';

import 'models.dart';

/// Where an order is in its life.
///
/// Deliberately coarse. The commerce provider has a much richer vocabulary, and
/// flattening it to these six is the mapper's job — screens should not have to
/// learn a provider's financial-and-fulfilment status matrix.
enum OrderStatus {
  pending('Pending'),
  paid('Paid'),
  partiallyFulfilled('Partly shipped'),
  fulfilled('Shipped'),
  cancelled('Cancelled'),
  refunded('Refunded');

  const OrderStatus(this.label);
  final String label;

  bool get isOpen =>
      this == pending || this == paid || this == partiallyFulfilled;
}

/// One purchased line.
///
/// [sellerId] is resolved by the order pipeline from the vendor mapping, and is
/// what credits the right seller's revenue.
@immutable
class OrderLine {
  const OrderLine({
    required this.id,
    required this.productId,
    required this.variantId,
    required this.title,
    required this.variantTitle,
    required this.unitPriceCents,
    required this.quantity,
    required this.sellerId,
    this.imageUrl,
  });

  final String id;
  final String productId;
  final String variantId;
  final String title;
  final String variantTitle;
  final int unitPriceCents;
  final int quantity;
  final String sellerId;
  final String? imageUrl;

  int get subtotalCents => unitPriceCents * quantity;
  String get subtotal => Fmt.money(subtotalCents);
}

/// An order, as the app understands it.
///
/// Written only by the order pipeline reacting to a paid webhook, never by a
/// client. An order placed on the website looks exactly like one placed in the
/// app once it lands here, which is what makes the two front doors one product.
@immutable
class Order {
  const Order({
    required this.id,
    required this.number,
    required this.placedAt,
    required this.status,
    required this.lines,
    required this.totalCents,
    this.shipTo,
    this.shipments = const [],
  });

  /// The provider's order id, and also the document id — which is what makes
  /// replaying a webhook idempotent.
  final String id;

  /// The human-facing order number, e.g. "#4471".
  final String number;
  final DateTime placedAt;
  final OrderStatus status;
  final List<OrderLine> lines;
  final int totalCents;
  final Address? shipTo;
  final List<Shipment> shipments;

  String get total => Fmt.money(totalCents);
  String get age => Fmt.relative(placedAt);

  int get itemCount => lines.fold(0, (sum, line) => sum + line.quantity);

  Set<String> get sellerIds => {for (final line in lines) line.sellerId};

  /// What this order is worth to one seller. A multi-vendor order credits each
  /// seller only for their own lines.
  int revenueForSeller(String sellerId) => lines
      .where((line) => line.sellerId == sellerId)
      .fold(0, (sum, line) => sum + line.subtotalCents);
}

/// A single thing someone bought and now owns.
///
/// Flattened out of [Order] because that is how it is used: the profile lists
/// what you bought, and the review composer needs the specific line you are
/// entitled to review. One order of three items produces three of these.
@immutable
class Purchase {
  const Purchase({
    required this.id,
    required this.orderId,
    required this.productId,
    required this.title,
    required this.purchasedAt,
    required this.sellerId,
    this.imageUrl,
    this.delivered = false,
    this.reviewed = false,
  });

  final String id;
  final String orderId;
  final String productId;
  final String title;
  final DateTime purchasedAt;
  final String sellerId;
  final String? imageUrl;
  final bool delivered;

  /// Drives the "Reviewed" badge, which the prototype faked from grid position.
  final bool reviewed;

  /// You may review anything you bought. Delivery is not required, because a
  /// service is never delivered in the shipping sense.
  bool get canReview => !reviewed;

  String get age => Fmt.relative(purchasedAt);
}

/// What the composer hands over when someone writes a review.
@immutable
class NewReview {
  const NewReview({
    required this.productId,
    required this.rating,
    required this.text,
    this.purchaseId,
    this.tags = const [],
    this.imageUrls = const [],
    this.mentionedUids = const [],
  });

  final String productId;
  final int rating;
  final String text;
  final String? purchaseId;
  final List<String> tags;
  final List<String> imageUrls;
  final List<String> mentionedUids;
}
