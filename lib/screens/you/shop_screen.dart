import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/feed_item.dart';
import '../../models/models.dart';
import '../../state/providers.dart';
import '../../state/session.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/async.dart';
import '../../widgets/masonry.dart';
import '../../widgets/pins/product_pin.dart';
import '../../widgets/primitives.dart';
import '../../widgets/screen.dart';
import '../../widgets/shipturtle.dart';
import '../../widgets/skeleton.dart';

/// A seller's own shop: what is live, what is waiting, and what it is worth.
///
/// There is no orders screen here and there will not be one. Orders,
/// shipping, tracking and payouts are Shipturtle's, and a second version of
/// them in this app would be a copy that goes stale and a seller who does
/// not know which one to believe. Every route into that world is a link out.
class ShopScreen extends ConsumerWidget {
  const ShopScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(meProvider);
    if (me == null) {
      return const LbmScreen(
        appBar: LbmAppBar(title: 'Your shop'),
        child: IdentitySkeleton(),
      );
    }

    final products = ref.watch(sellerProductsProvider(me.id));

    return LbmScreen(
      appBar: LbmAppBar(
        title: 'Your shop',
        actions: [
          CircleIconButton(
            icon: Icons.add_rounded,
            tooltip: 'Add a product',
            onPressed: () => context.push('/you/add-product'),
          ),
        ],
      ),
      child: RefreshIndicator(
        onRefresh: () async {
          ref
            ..invalidate(sellerProductsProvider(me.id))
            ..invalidate(listingsProvider);
          await Future<void>.delayed(const Duration(milliseconds: 400));
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(0, 4, 0, 32),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            _ShopStats(person: me),
            const _UnderReview(),
            const _ShipturtleNote(),
            const SectionHead('Live in your shop'),
            LbmAsync<List<Product>>(
              products,
              skeleton: const GridSkeleton(count: 4),
              isEmpty: (all) => all.isEmpty,
              empty: const LbmEmpty(
                title: 'Nothing live yet',
                body: 'Add a product and it appears here once approved.',
              ),
              data: (all) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _PhotoNudge(products: all),
                  LbmMasonry.fixed(
                    children: [
                      for (final product in all)
                        ProductPin(
                          key: ValueKey('mine_${product.id}'),
                          item: ProductItem(
                            ListingPost(
                              id: 'mine_${product.id}',
                              authorId: product.sellerId,
                              createdAt: DateTime.now(),
                              tags: product.tags,
                              likeCount: 0,
                              commentCount: 0,
                              likedByMe: false,
                              product: product,
                            ),
                            proof:
                                product.saveCount >=
                                ProductItem.proofThreshold,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// What the shop is worth knowing, and nothing it does not record.
class _ShopStats extends ConsumerWidget {
  const _ShopStats({required this.person});

  final Person person;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final products = ref.watch(sellerProductsProvider(person.id)).value;
    final carted = products?.fold<int>(0, (sum, p) => sum + p.saveCount);

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: LbmRadius.cardR,
          boxShadow: c.shadowSoft,
        ),
        child: Row(
          children: [
            Expanded(
              child: _Stat(
                value: person.grossSalesLabel,
                label: 'Total sales',
              ),
            ),
            Expanded(
              child: _Stat(
                value: products == null ? '—' : '${products.length}',
                label: 'Listings',
              ),
            ),
            Expanded(
              child: _Stat(
                // All-time, and the label says so. There is no weekly delta
                // anywhere in this system, so "this week" would be invented.
                value: carted == null ? '—' : Fmt.count(carted),
                label: 'Carted, all time',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          child: Text(
            value,
            maxLines: 1,
            style: LbmText.display.copyWith(
              fontSize: 20,
              color: c.ink,
              fontFeatures: kTabularFigures,
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          maxLines: 2,
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
          style: LbmText.pinMeta.copyWith(fontSize: 11, color: c.ink2),
        ),
      ],
    );
  }
}

/// Listings sent for approval and not yet live.
///
/// Approval happens in Shipturtle, so every row here is a way out to it
/// rather than a status this app maintains a second copy of.
class _UnderReview extends ConsumerWidget {
  const _UnderReview();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final listings = ref.watch(listingsProvider).value;
    if (listings == null) return const SizedBox.shrink();

    final waiting = [
      for (final listing in listings)
        if (listing.status != ListingStatus.live) listing,
    ];
    if (waiting.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHead(
          'Under review (${waiting.length})',
          trailing: InlineLink(
            'Open in Shipturtle',
            fontSize: 12.5,
            onTap: () => openShipturtle(context, ref),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: LbmCard(
            child: RowStack(
              children: [
                for (final listing in waiting)
                  ListRow(
                    title: Text(
                      listing.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(listing.status.label),
                    trailing: Icon(
                      Icons.open_in_new_rounded,
                      size: 18,
                      color: c.ink3,
                    ),
                    onTap: () => openShipturtle(context, ref),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Said once, plainly, so nobody goes looking for an orders screen.
class _ShipturtleNote extends ConsumerWidget {
  const _ShipturtleNote();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
      child: LbmCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        onTap: () => openShipturtle(context, ref),
        child: Row(
          children: [
            Icon(Icons.local_shipping_outlined, size: 20, color: c.skyDeep),
            const SizedBox(width: 11),
            Expanded(
              child: Text(
                'Orders and shipping are managed in Shipturtle, not here.',
                style: LbmText.pinMeta.copyWith(fontSize: 12.5, color: c.ink2),
              ),
            ),
            Icon(Icons.open_in_new_rounded, size: 18, color: c.ink3),
          ],
        ),
      ),
    );
  }
}

/// A gentle push on the listings that will not sell as they are.
///
/// Photographs are the whole grid; a listing with one is at a disadvantage
/// in it, and the seller cannot see that from their own page.
class _PhotoNudge extends StatelessWidget {
  const _PhotoNudge({required this.products});

  final List<Product> products;

  /// Below this a listing barely fills its pin.
  static const _wanted = 3;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final thin = [
      for (final product in products)
        if (product.imageUrls.length < _wanted) product,
    ];
    if (thin.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: c.accentMist,
          borderRadius: LbmRadius.cardR,
        ),
        child: Row(
          children: [
            Icon(Icons.add_a_photo_outlined, size: 20, color: c.accentText),
            const SizedBox(width: 11),
            Expanded(
              child: Text(
                thin.length == 1
                    ? '“${thin.first.title}” has fewer than $_wanted '
                          'photographs. The grid is photographs.'
                    : '${thin.length} of your listings have fewer than '
                          '$_wanted photographs. The grid is photographs.',
                style: LbmText.pinMeta.copyWith(
                  fontSize: 12.5,
                  color: c.accentText,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
