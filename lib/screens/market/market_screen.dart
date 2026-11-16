import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/repositories/dev_error_sink.dart' show kUnderFlutterTest;
import '../../models/models.dart';
import '../../router/nav.dart';
import '../../state/providers.dart';
import '../../widgets/primitives.dart';
import '../../widgets/screen.dart';
import 'collection_screen.dart' show CollectionTiles;
import 'market_shelves.dart';

/// The Market button: a shop window.
///
/// Grace, 2026-10-28, asked for the category tiles on their own here, and on
/// 2026-11-16 for more: "make the market look more appealing to shop. Maybe
/// the gift guide categories? Or we have some other categories like
/// community favorites and new. And all the ones by category like woman
/// owned... make the screen look more dynamic in general. make the
/// categories slightly larger, single file and slide left to right. Make it
/// look less cluttered."
///
/// So, top to bottom: the search pill, the gift guide's cover, then rows
/// that each slide sideways: categories, values, what is new, what people
/// are carting, and the shops themselves. One row of each rather than a
/// wall of tiles is what makes it less cluttered; each row hides itself
/// when it has nothing in it. The rows arrive one after another the first
/// time the screen opens, which is the "more dynamic".
class MarketScreen extends ConsumerWidget {
  const MarketScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
        child: SearchPill(
          label: 'Search goods, sellers, #tags',
          onTap: context.goToSearch,
        ),
      ),
      const GiftGuideCover(),
      const CollectionTiles(),
      const OwnershipRail(),
      ProductShelf(
        title: 'New arrivals',
        subtitle: 'Just in from the makers',
        products: ref
            .watch(collectionProductsProvider(kMarketShelves.first))
            .whenData((page) => page.items),
        onSeeAll: () => context.goToCollection(kMarketShelves.first),
      ),
      ProductShelf(
        title: 'Community favorites',
        subtitle: 'What the most people have in their carts',
        products: ref.watch(communityFavoritesProvider),
      ),
      const VendorRail(),
    ];

    return LbmScreen(
      appBar: LbmAppBar(
        title: 'Market',
        showBack: context.canPop(),
        actions: const [HomeButton()],
      ),
      child: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(collectionsProvider);
          ref.invalidate(collectionProductsProvider(kMarketShelves.first));
          ref.invalidate(communityFavoritesProvider);
          ref.invalidate(allVendorsProvider);
        },
        child: ListView(
          padding: const EdgeInsets.only(bottom: 28),
          children: [
            for (final (i, row) in rows.indexed) _Arrive(index: i, child: row),
          ],
        ),
      ),
    );
  }
}

/// Each row rises and fades in a beat after the one above it. Once, and
/// short: it is a welcome, not a wait. Not under test, where the rows must
/// be there on the first frame.
class _Arrive extends StatelessWidget {
  const _Arrive({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (kUnderFlutterTest) return child;
    final reduce = MediaQuery.disableAnimationsOf(context);
    if (reduce) return child;
    final delay = (index * 70).clamp(0, 420);
    final total = Duration(milliseconds: 380 + delay);
    final start = delay / total.inMilliseconds;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: total,
      curve: Interval(start, 1, curve: Curves.easeOutCubic),
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, 18 * (1 - t)),
          child: child,
        ),
      ),
      child: child,
    );
  }
}
