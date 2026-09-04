import 'package:flutter/material.dart';

import '../../data/fixtures.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/post_card.dart';
import '../../widgets/primitives.dart';
import '../../widgets/product_art.dart';
import '../../widgets/screen.dart';

/// Every review for one product, newest first.
class ReviewsScreen extends StatelessWidget {
  const ReviewsScreen({super.key, required this.productId});

  final String productId;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final product = Fx.product(productId);
    final seller = Fx.person(product.sellerId);
    final reviews = Fx.reviewsFor(productId);

    return LbmScreen(
      appBar: const LbmAppBar(title: 'Reviews'),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          LbmCard(
            margin: const EdgeInsets.symmetric(horizontal: 14),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                SizedBox(
                  width: 64,
                  child: ProductArt(
                    product,
                    square: true,
                    borderRadius: const BorderRadius.all(Radius.circular(14)),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          height: 1.3,
                          color: c.ink,
                        ),
                      ),
                      Text(
                        '${seller.name} · ${product.price}',
                        style: LbmText.tiny.copyWith(color: c.ink2),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Stars(product.rating, size: 11),
                          const SizedBox(width: 6),
                          Text(
                            product.rating.toStringAsFixed(1),
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: c.ink,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            '(${product.ratingCount})',
                            style: LbmText.xtiny.copyWith(color: c.ink2),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SectionHead('Reviews live on the product, not the seller'),
          LbmCard(
            margin: const EdgeInsets.symmetric(horizontal: 14),
            child: RowStack(
              children: [for (final review in reviews) ReviewRow(review)],
            ),
          ),
          if (reviews.length < 3)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
              child: Text(
                'Showing ${reviews.length} of ${product.ratingCount}. Older '
                'reviews load as you scroll.',
                style: LbmText.tiny.copyWith(color: c.ink2),
              ),
            ),
          const Puff(),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
