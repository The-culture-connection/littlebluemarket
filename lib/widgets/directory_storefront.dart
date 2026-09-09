import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/models.dart';
import '../router/nav.dart';
import '../screens/market/results_screen.dart';
import '../state/providers.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'async.dart';
import 'primitives.dart';

/// The littlebluecart.com half of a Products tab (Stage 13).
///
/// A directory business has no Shopify shop, so its Products tab is the
/// listing's photos on top and the products it sells on its own website
/// below. A business that is also a Market seller keeps both: the Shopify
/// grid goes first and this comes after it, nothing deleted.

/// Whether someone has anything from the directory to show: a published
/// listing or a website-link product. Decided by the public collections, so
/// no field on the profile is needed.
final hasDirectoryStorefrontProvider = Provider.family<bool, String>((
  ref,
  personId,
) {
  final listings = ref.watch(directoryListingsOfProvider(personId)).value;
  final products = ref.watch(directoryProductsOfProvider(personId)).value;
  return (listings?.isNotEmpty ?? false) || (products?.isNotEmpty ?? false);
});

/// The listing's photos, one per mirrored listing, in a horizontal strip.
/// Nothing at all when there are none.
class DirectoryPhotoStrip extends ConsumerWidget {
  const DirectoryPhotoStrip({super.key, required this.ownerUid, this.own = false});

  final String ownerUid;

  /// The owner sees pending listings' photos too; a visitor only published.
  final bool own;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final listings = own
        ? ref.watch(myDirectoryListingsProvider)
        : ref.watch(directoryListingsOfProvider(ownerUid));
    final urls = [
      for (final l in listings.value ?? const <DirectoryListing>[])
        if (l.imageUrl.isNotEmpty) l.imageUrl,
    ];
    if (urls.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 132,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
        itemCount: urls.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) => ClipRRect(
          borderRadius: LbmRadius.imageR,
          child: Image.network(
            urls[i],
            width: 156,
            height: 116,
            fit: BoxFit.cover,
            cacheWidth: 312,
            errorBuilder: (_, _, _) => Container(
              width: 156,
              height: 116,
              color: c.skyWash,
            ),
          ),
        ),
      ),
    );
  }
}

/// The website-link products, three across, with Add a product for the owner.
class DirectoryProductsGrid extends ConsumerWidget {
  const DirectoryProductsGrid({
    super.key,
    required this.ownerUid,
    this.own = false,
    this.heading,
  });

  final String ownerUid;
  final bool own;

  /// A small heading above the grid, when this sits under a Shopify grid
  /// and needs to say why the Buy buttons differ.
  final String? heading;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final products = ref.watch(directoryProductsOfProvider(ownerUid));
    return LbmAsync<List<Product>>(
      products,
      skeleton: const SizedBox(height: 60),
      errorBuilder: (_, _) => const SizedBox.shrink(),
      data: (list) {
        if (list.isEmpty && !own) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (heading != null && list.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
                child: Text(
                  heading!,
                  style: LbmText.xtiny.copyWith(color: c.ink3),
                ),
              ),
            if (own)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                child: PillButton(
                  list.isEmpty
                      ? 'Add a product (sold on my website)'
                      : 'Add another product',
                  icon: Icons.add_rounded,
                  style: PillStyle.quiet,
                  onPressed: () => context.push('/you/directory-product'),
                ),
              ),
            if (list.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: EdgeInsets.zero,
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        mainAxisSpacing: 7,
                        crossAxisSpacing: 7,
                      ),
                  itemCount: list.length,
                  itemBuilder: (context, i) => GridCell(
                    product: list[i],
                    badge: list[i].price,
                    onTap: () => own
                        ? context.push(
                            '/you/directory-product/'
                            '${list[i].id.substring(Product.externalPrefix.length)}',
                          )
                        : context.goToProduct(list[i].id),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
