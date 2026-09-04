import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/models.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/async.dart';
import '../../widgets/post_card.dart';
import '../../widgets/primitives.dart';
import '../../widgets/product_art.dart';
import '../../widgets/screen.dart';
import '../../widgets/skeleton.dart';

/// Every review for one product, newest first.
class ReviewsScreen extends ConsumerWidget {
  const ReviewsScreen({super.key, required this.productId});

  final String productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(productDetailProvider(productId));
    final reviews = ref.watch(reviewsProvider(productId));

    return LbmScreen(
      appBar: const LbmAppBar(title: 'Reviews'),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          LbmAsync<ProductDetail>(
            detail,
            skeleton: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14),
              child: ListRowSkeleton(rows: 1),
            ),
            onRetry: () => ref.invalidate(productDetailProvider(productId)),
            data: (detail) => _ProductHeader(detail: detail),
          ),
          const SectionHead('Reviews live on the product, not the seller'),
          LbmAsync<List<Review>>(
            reviews,
            skeleton: const ListRowSkeleton(rows: 3),
            isEmpty: (reviews) => reviews.isEmpty,
            empty: const LbmEmpty(
              title: 'No reviews yet',
              body: 'The first one arrives after somebody buys.',
            ),
            data: (reviews) => LbmCard(
              margin: const EdgeInsets.symmetric(horizontal: 14),
              child: RowStack(
                children: [for (final review in reviews) ReviewRow(review)],
              ),
            ),
          ),
          const Puff(),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

class _ProductHeader extends StatelessWidget {
  const _ProductHeader({required this.detail});

  final ProductDetail detail;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final product = detail.product;
    final rating = detail.rating;

    return LbmCard(
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
                  '${detail.seller.name} · ${product.price}',
                  style: LbmText.tiny.copyWith(color: c.ink2),
                ),
                const SizedBox(height: 4),
                if (rating.isEmpty)
                  Text(
                    'No ratings yet',
                    style: LbmText.xtiny.copyWith(color: c.ink2),
                  )
                else
                  Row(
                    children: [
                      Stars(rating.average, size: 11),
                      const SizedBox(width: 6),
                      Text(
                        rating.average.toStringAsFixed(1),
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: c.ink,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        '(${Fmt.count(rating.total)})',
                        style: LbmText.xtiny.copyWith(color: c.ink2),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
