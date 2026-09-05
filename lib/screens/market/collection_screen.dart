import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/models.dart';
import '../../router/nav.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/async.dart';
import '../../widgets/primitives.dart';
import '../../widgets/screen.dart';
import '../../widgets/skeleton.dart';
import 'results_screen.dart';

/// Everything filed under one collection, three across, newest first.
///
/// An initiative ("Ally Owned") and a category ("Bath, Beauty & Wellness")
/// are the same thing to the store, so they are the same screen here.
class CollectionScreen extends ConsumerWidget {
  const CollectionScreen({super.key, required this.handle});

  final String handle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final collection = ref.watch(collectionProvider(handle));
    final products = ref.watch(collectionProductsProvider(handle));

    return LbmScreen(
      appBar: LbmAppBar(
        title: collection.value?.title ?? 'Collection',
        actions: [
          CircleIconButton(
            icon: Icons.shopping_bag_outlined,
            tooltip: 'Your cart',
            badge: ref.watch(cartCountProvider) > 0,
            onPressed: () => context.goToCart(),
          ),
        ],
      ),
      child: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(collectionProvider(handle));
          ref.invalidate(collectionProductsProvider(handle));
        },
        child: ListView(
          padding: const EdgeInsets.only(top: 4, bottom: 26),
          children: [
            if (collection.value case final found?)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
                child: Text(
                  found.countLabel,
                  style: LbmText.tiny.copyWith(color: c.ink2),
                ),
              ),
            LbmAsync<List<Product>>(
              products,
              skeleton: const GridSkeleton(count: 6),
              onRetry: () => ref.invalidate(collectionProductsProvider(handle)),
              isEmpty: (items) => items.isEmpty,
              empty: const LbmEmpty(
                title: 'Nothing here yet',
                body:
                    'This collection is empty on the store, or the catalog '
                    'has not been imported yet.',
              ),
              data: (items) => Padding(
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
                  itemCount: items.length,
                  itemBuilder: (context, i) => GridCell(
                    product: items[i],
                    badge: items[i].price,
                    onTap: () => context.goToProduct(items[i].id),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The horizontal "Browse the shop" rail on the feed: one chip per
/// collection, in title order, hidden entirely when the store has none.
class CollectionRail extends ConsumerWidget {
  const CollectionRail({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final collections = ref.watch(collectionsProvider);

    return LbmAsync<List<Collection>>(
      collections,
      skeleton: const Padding(
        padding: EdgeInsets.fromLTRB(14, 0, 14, 12),
        child: ChipRailSkeleton(),
      ),
      errorBuilder: (_, _) => const SizedBox.shrink(),
      isEmpty: (items) => items.isEmpty,
      empty: const SizedBox.shrink(),
      data: (items) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 0, 0, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
              child: Text(
                'Browse the shop',
                style: LbmText.tiny.copyWith(
                  fontWeight: FontWeight.w800,
                  color: c.ink2,
                ),
              ),
            ),
            SizedBox(
              height: 32,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(width: 7),
                itemBuilder: (context, i) => LbmChip(
                  items[i].title,
                  onTap: () => context.goToCollection(items[i].handle),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
