import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../router/nav.dart';
import '../screens/market/results_screen.dart';
import '../state/providers.dart';
import 'async.dart';
import 'primitives.dart';
import 'skeleton.dart';

/// A seller's products, three across.
///
/// Used on the public storefront and on the seller's own profile, so the two
/// cannot drift. Reads the catalog mirror by `sellerId`, which the backend
/// fills in when a vendor claims their shop — until then this is honestly
/// empty, and says so.
class SellerProductsGrid extends ConsumerWidget {
  const SellerProductsGrid({
    super.key,
    required this.sellerId,
    this.own = false,
  });

  final String sellerId;

  /// Whether this is the signed-in seller looking at their own shop. Changes
  /// the empty-state copy, nothing else.
  final bool own;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final products = ref.watch(sellerProductsProvider(sellerId));

    return LbmAsync<List<Product>>(
      products,
      skeleton: const GridSkeleton(count: 6),
      onRetry: () => ref.invalidate(sellerProductsProvider(sellerId)),
      isEmpty: (products) => products.isEmpty,
      // No padding and no borrowed listings. The prototype filled an empty
      // storefront with another seller's products, then duplicated the list to
      // fill out the grid.
      empty: own
          ? LbmEmpty(
              title: 'No products yet',
              body:
                  'They arrive from your store on their own a few seconds '
                  'after your shop is claimed.',
              action: PillButton(
                'Check again',
                small: true,
                expand: false,
                style: PillStyle.quiet,
                onPressed: () =>
                    ref.invalidate(sellerProductsProvider(sellerId)),
              ),
            )
          : const LbmEmpty(
              title: 'Nothing listed yet',
              body: 'This storefront is still being set up.',
            ),
      data: (products) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 7,
            crossAxisSpacing: 7,
          ),
          itemCount: products.length,
          itemBuilder: (context, i) => GridCell(
            product: products[i],
            badge: products[i].price,
            onTap: () => context.goToProduct(products[i].id),
          ),
        ),
      ),
    );
  }
}
