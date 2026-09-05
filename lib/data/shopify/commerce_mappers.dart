import '../../models/models.dart';
import '../firebase/mappers.dart';

/// Commerce payloads in, app models out.
///
/// Kept apart from the Firestore mappers because these are a different wire
/// format for some of the same types, which is exactly the case a single
/// `fromJson` on the model would have to pretend did not exist.
///
/// Nothing above this file knows what the storefront calls anything.
abstract final class CommerceMappers {
  static Cart cart(String id, Map<String, dynamic> data) {
    final lines = data['lines'];
    return Cart(
      id: FirestoreMappers.str(data['id'], id),
      lines: [
        if (lines is List)
          for (final item in lines)
            if (item is Map) cartLine(Map<String, dynamic>.from(item)),
      ],
      // Null until the provider has quoted them. Absent is different from
      // zero, and showing zero shipping would be a lie the checkout corrects.
      shippingCents: data['shippingCents'] == null
          ? null
          : FirestoreMappers.integer(data['shippingCents']),
      taxCents: data['taxCents'] == null
          ? null
          : FirestoreMappers.integer(data['taxCents']),
      currencyCode: FirestoreMappers.str(data['currencyCode'], 'USD'),
    );
  }

  static CartLine cartLine(Map<String, dynamic> data) => CartLine(
    id: FirestoreMappers.str(data['id']),
    productId: FirestoreMappers.str(data['productId']),
    variantId: FirestoreMappers.str(data['variantId']),
    title: FirestoreMappers.str(data['title']),
    variantTitle: FirestoreMappers.str(data['variantTitle']),
    unitPriceCents: FirestoreMappers.integer(data['unitPriceCents']),
    quantity: FirestoreMappers.integer(data['quantity'], 1),
    // Carried per line because a multi-vendor order splits by seller, and the
    // pipeline has to know who to credit.
    sellerId: FirestoreMappers.str(data['sellerUid']),
    imageUrl: data['imageUrl'] as String?,
  );

  static Order order(String id, Map<String, dynamic> data) {
    final lines = data['lines'];
    final shipments = data['shipments'];
    final shipTo = data['shipTo'];

    return Order(
      id: id,
      number: FirestoreMappers.str(data['number'], '#$id'),
      placedAt: FirestoreMappers.time(data['placedAt']),
      status: orderStatus(data['status']),
      totalCents: FirestoreMappers.integer(data['totalCents']),
      lines: [
        if (lines is List)
          for (final item in lines)
            if (item is Map) orderLine(Map<String, dynamic>.from(item)),
      ],
      shipTo: shipTo is Map
          ? FirestoreMappers.address('', Map<String, dynamic>.from(shipTo))
          : null,
      shipments: [
        if (shipments is List)
          for (final item in shipments)
            if (item is Map)
              FirestoreMappers.shipment(Map<String, dynamic>.from(item)),
      ],
    );
  }

  static OrderLine orderLine(Map<String, dynamic> data) => OrderLine(
    id: FirestoreMappers.str(data['id']),
    productId: FirestoreMappers.str(data['productId']),
    variantId: FirestoreMappers.str(data['variantId']),
    title: FirestoreMappers.str(data['title']),
    variantTitle: FirestoreMappers.str(data['variantTitle']),
    unitPriceCents: FirestoreMappers.integer(data['unitPriceCents']),
    quantity: FirestoreMappers.integer(data['quantity'], 1),
    sellerId: FirestoreMappers.str(data['sellerUid']),
    imageUrl: data['imageUrl'] as String?,
  );

  /// Flattens the provider's much richer status matrix.
  ///
  /// A storefront distinguishes financial status from fulfilment status and
  /// has a dozen values across the two. Screens should not have to learn that,
  /// so the normalising happens here, once, on the way in.
  static OrderStatus orderStatus(Object? value) =>
      switch (FirestoreMappers.str(value)) {
        'paid' => OrderStatus.paid,
        'partially_fulfilled' ||
        'partiallyFulfilled' => OrderStatus.partiallyFulfilled,
        'fulfilled' || 'shipped' => OrderStatus.fulfilled,
        'cancelled' || 'canceled' => OrderStatus.cancelled,
        'refunded' || 'partially_refunded' => OrderStatus.refunded,
        _ => OrderStatus.pending,
      };
}
