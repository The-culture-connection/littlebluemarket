import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/repositories.dart';
import '../models/models.dart';
import '../router/nav.dart';
import '../screens/market/results_screen.dart';
import '../state/providers.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'async.dart';
import 'composers.dart';
import 'primitives.dart';
import 'sheets.dart';
import 'skeleton.dart';

/// A seller's products, three across.
///
/// Used on the public storefront and on the seller's own profile, so the two
/// cannot drift. Reads the catalog mirror by `sellerId`, which the backend
/// fills in when a vendor claims their shop — until then this is honestly
/// empty, and says so.
class SellerProductsGrid extends ConsumerStatefulWidget {
  const SellerProductsGrid({
    super.key,
    required this.sellerId,
    this.own = false,
  });

  final String sellerId;

  /// Whether this is the signed-in seller looking at their own shop. Changes
  /// the empty-state copy and adds the button that posts one, nothing else.
  final bool own;

  @override
  ConsumerState<SellerProductsGrid> createState() => _SellerProductsGridState();
}

class _SellerProductsGridState extends ConsumerState<SellerProductsGrid> {
  /// Pages after the first. The first stays live off the stream, so a
  /// product mirrored a moment ago still appears without a pull.
  final _more = <Product>[];
  String? _cursor;
  bool _loadingMore = false;
  String? _moreError;

  /// The last id the first page ended on, once it has been seen. Stops the
  /// cursor being re-seeded on every rebuild, which would otherwise forget
  /// the end of the list and fetch page two forever.
  String? _seededFrom;

  Future<void> _loadMore() async {
    final cursor = _cursor;
    if (cursor == null || _loadingMore) return;
    setState(() {
      _loadingMore = true;
      _moreError = null;
    });
    try {
      final page = await ref
          .read(catalogRepositoryProvider)
          .productsBySeller(widget.sellerId, cursor: cursor);
      if (!mounted) return;
      setState(() {
        _more.addAll(page.items);
        _cursor = page.cursor;
        _loadingMore = false;
      });
    } on RepositoryException catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingMore = false;
        _moreError = describeError(error).body;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final sellerId = widget.sellerId;
    final own = widget.own;
    final raw = ref.watch(sellerProductsProvider(sellerId));

    // Seeded from the **unfiltered** first page: the cursor is a document
    // id the server pages from, so it has to be the last document read,
    // not the last one this screen chose to draw.
    final firstPage = raw.value;
    if (firstPage != null && firstPage.isNotEmpty) {
      final last = firstPage.last.id;
      if (_seededFrom != last) {
        _seededFrom = last;
        _cursor = firstPage.length < 30 ? null : last;
        _more.clear();
      }
    }

    // The seller sees what is on sale and what is under review; everyone
    // else sees what is on sale. Deleted and archived products show to nobody.
    // Keyed by id on the way through, because a live first page can arrive
    // again carrying a product a later page already added.
    final products = raw.whenData((all) {
      final byId = <String, Product>{};
      for (final p in [...all, ..._more]) {
        if (own ? !p.isGone : p.active) byId[p.id] = p;
      }
      return byId.values.toList();
    });

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
        child: Column(
          children: [
            GridView.builder(
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
                // Products stopped posting themselves on 2026-09-24. A
                // seller who wants one in the feed says so, here, on the
                // tile: this is the only place they are all laid out, and
                // it is where Grace asked for it. The tap still opens the
                // product, so posting needs its own target.
                actionIcon: own ? Icons.campaign_outlined : null,
                actionLabel: 'Post this to the feed',
                onAction: own
                    ? () => showLbmSheet(
                        context,
                        (_) => ListingComposer(product: products[i]),
                      )
                    : null,
              ),
            ),
            // The shop's header says how many products it has, and most
            // shops on the market have more than the thirty a page holds.
            // Without this the figure and the tiles disagree, which is the
            // complaint that started all of it (Grace, 2026-09-23: "only 27
            // products per category").
            if (_moreError != null) ...[
              const SizedBox(height: 12),
              // A line, not a card: the tiles above it are fine, and only
              // the next page failed. Same shape as the collection screen.
              Text(
                _moreError!,
                style: LbmText.tiny.copyWith(
                  color: context.c.clay,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              PillButton(
                'Try again',
                small: true,
                expand: false,
                style: PillStyle.quiet,
                onPressed: _loadingMore ? null : _loadMore,
              ),
            ] else if (_cursor != null) ...[
              const SizedBox(height: 12),
              PillButton(
                _loadingMore ? 'Loading' : 'Load more',
                small: true,
                expand: false,
                style: PillStyle.quiet,
                onPressed: _loadingMore ? null : _loadMore,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
