import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/feed_item.dart';
import '../../models/models.dart';
import '../../router/nav.dart';
import '../../state/providers.dart';
import '../cart_pill.dart';
import '../product_art.dart';
import 'pin_caption.dart';

/// A listing in the grid.
///
/// The photograph is the card: no white frame, no fixed ratio, nothing
/// between the image and the paper but its own rounded corners. The only
/// thing drawn on top of it is the orchid cart pill, because adding to the
/// cart is the one action a pin offers and the accent is reserved for it.
class ProductPin extends ConsumerWidget {
  const ProductPin({super.key, required this.item});

  ProductPin.of(ListingPost post, {Key? key, bool proof = false})
    : this(key: key, item: ProductItem(post, proof: proof));

  final ProductItem item;

  /// How many carts a listing has to be in before the pin says so.
  ///
  /// Below this it is not social proof, it is just a number.
  static const proofThreshold = 50;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final product = item.product;
    final seller = ref.watch(personProvider(product.sellerId)).value;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => context.goToProduct(product.id),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            children: [
              NaturalPhoto(
                url: product.imageUrls.firstOrNull ?? '',
                fallback: ProductArt(product),
              ),
              if (item.proof)
                Positioned(
                  left: 8,
                  top: 8,
                  child: PinBadge(
                    '${product.saveCount} carted',
                    icon: Icons.shopping_cart_outlined,
                  ),
                ),
              Positioned(
                right: 8,
                bottom: 8,
                child: CartPill(productId: product.id),
              ),
            ],
          ),
          PinCaption(
            title: product.title,
            author: seller,
            trailing: PinPrice(product.priceCents),
          ),
        ],
      ),
    );
  }
}
