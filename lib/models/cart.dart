import 'package:flutter/foundation.dart';

import 'formatting.dart';

/// One line in the cart.
///
/// Denormalised on purpose: title, image and unit price are copied in at the
/// moment of adding, so the cart renders without a second round trip and a
/// price change mid-session cannot silently rewrite what someone thought they
/// were buying. The authoritative price is re-read at checkout.
@immutable
class CartLine {
  const CartLine({
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

  /// Line id, not product id — the same product in two variants is two lines.
  final String id;
  final String productId;
  final String variantId;
  final String title;
  final String variantTitle;
  final int unitPriceCents;
  final int quantity;

  /// Carried per line because a multi-vendor order splits by seller, and the
  /// order pipeline needs to know who to credit.
  final String sellerId;

  final String? imageUrl;

  int get subtotalCents => unitPriceCents * quantity;

  String get unitPrice => Fmt.money(unitPriceCents);
  String get subtotal => Fmt.money(subtotalCents);

  CartLine copyWith({int? quantity}) => CartLine(
    id: id,
    productId: productId,
    variantId: variantId,
    title: title,
    variantTitle: variantTitle,
    unitPriceCents: unitPriceCents,
    quantity: quantity ?? this.quantity,
    sellerId: sellerId,
    imageUrl: imageUrl,
  );
}

/// The cart.
///
/// Shipping and tax are nullable because only the checkout provider can compute
/// them: showing an invented total and then a different one at checkout is the
/// kind of thing that loses a sale. Until they are known the UI shows a
/// subtotal and says so.
@immutable
class Cart {
  const Cart({
    required this.id,
    required this.lines,
    this.shippingCents,
    this.taxCents,
    this.currencyCode = 'USD',
  });

  const Cart.empty() : this(id: '', lines: const []);

  final String id;
  final List<CartLine> lines;
  final int? shippingCents;
  final int? taxCents;
  final String currencyCode;

  bool get isEmpty => lines.isEmpty;

  int get itemCount => lines.fold(0, (sum, line) => sum + line.quantity);

  int get subtotalCents =>
      lines.fold(0, (sum, line) => sum + line.subtotalCents);

  /// Null until the provider has quoted shipping and tax.
  int? get totalCents {
    if (shippingCents == null || taxCents == null) return null;
    return subtotalCents + shippingCents! + taxCents!;
  }

  /// The distinct sellers in the cart. A multi-vendor cart is normal here, and
  /// it is what the order pipeline splits on.
  Set<String> get sellerIds => {for (final line in lines) line.sellerId};

  String get subtotal => Fmt.money(subtotalCents);

  CartLine? lineFor(String variantId) {
    for (final line in lines) {
      if (line.variantId == variantId) return line;
    }
    return null;
  }

  Cart copyWith({
    List<CartLine>? lines,
    int? shippingCents,
    int? taxCents,
    bool clearQuote = false,
  }) => Cart(
    id: id,
    lines: lines ?? this.lines,
    shippingCents: clearQuote ? null : (shippingCents ?? this.shippingCents),
    taxCents: clearQuote ? null : (taxCents ?? this.taxCents),
    currencyCode: currencyCode,
  );
}

/// Everything the app needs to hand a cart to a checkout it does not own.
///
/// [webUrl] is opened in a sheet. The app must not treat returning from that
/// sheet as proof of purchase — only the paid webhook is proof — so nothing
/// here reports success.
@immutable
class CheckoutHandoff {
  const CheckoutHandoff({required this.cartId, required this.webUrl});

  final String cartId;
  final Uri webUrl;
}
