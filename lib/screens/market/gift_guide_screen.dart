// Flutter's own Page (a Navigator route) is not wanted here; Page is the
// app's page-of-results model.
import 'package:flutter/material.dart' hide Page;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/models.dart';
import '../../router/nav.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/async.dart';
import '../../widgets/primitives.dart';
import '../../widgets/product_art.dart';
import '../../widgets/screen.dart';
import '../../widgets/skeleton.dart';
import 'collection_screen.dart' show PhotoTile, ShelfHeading;
import 'results_screen.dart' show GridCell;

/// The Holiday Gift Guide, on the app's own screen (Grace, 2026-11-16: "It
/// should bring up products and work like they are within the app and not
/// on a webpage").
///
/// The website's sections in the website's order, every tile a collection
/// that opens on the app's collection screen: the products, the cart
/// button, the seller, the reviews. See `lib/models/gift_guide.dart` for
/// where the list comes from and how it stays current.
class GiftGuideScreen extends ConsumerWidget {
  const GiftGuideScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const guide = kGiftGuide;
    final collections = ref.watch(collectionsProvider);
    final byHandle = {
      for (final x in collections.value ?? const <Collection>[]) x.handle: x,
    };

    // A tile whose collections the store has emptied or taken down is left
    // off. Until the list arrives, or if it cannot, every tile is drawn
    // with the guide's own name for it: a slow connection should not empty
    // the guide.
    final known = collections.hasValue && byHandle.isNotEmpty;
    bool shows(GiftGuideEntry e) =>
        !known || e.handles.any(byHandle.containsKey);

    final sections = [
      for (final section in guide.sections)
        if (section.entries.any(shows)) section,
    ];

    return LbmScreen(
      appBar: LbmAppBar(
        title: 'Gift Guide',
        showBack: context.canPop(),
        actions: const [HomeButton()],
      ),
      child: RefreshIndicator(
        onRefresh: () async => ref.invalidate(collectionsProvider),
        child: ListView(
          padding: const EdgeInsets.only(bottom: 28),
          children: [
            const _Hero(guide: guide),
            if (sections.isEmpty)
              const LbmEmpty(
                title: 'The gift guide is being restocked',
                body: 'Check back soon. New gift ideas go in every week.',
              ),
            for (final section in sections) ...[
              ShelfHeading(section.title, subtitle: section.blurb),
              _TileGrid(
                entries: section.entries.where(shows).toList(),
                byHandle: byHandle,
              ),
            ],
            if (sections.isNotEmpty) _Closing(guide: guide),
          ],
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.guide});

  final GiftGuide guide;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
      child: ClipRRect(
        borderRadius: const BorderRadius.all(Radius.circular(22)),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: const Alignment(-0.7, -0.9),
              end: const Alignment(0.7, 0.9),
              colors: c.heroGradient,
              stops: LbmColors.heroStops,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // At its own shape, and nothing at all if it does not load:
              // a failed picture must not keep its space.
              ProductPhoto(
                url: guide.heroImageUrl,
                fit: BoxFit.fitWidth,
                cacheWidth: 1000,
                fallback: const SizedBox.shrink(),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      guide.kicker.toUpperCase(),
                      style: LbmText.pinMeta.copyWith(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.4,
                        color: LbmConst.onGradient.withValues(alpha: 0.85),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Semantics(
                      header: true,
                      child: Text(
                        guide.title,
                        style: LbmText.headline.copyWith(
                          fontSize: 25,
                          color: LbmConst.onGradient,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      guide.tagline,
                      style: LbmText.pinMeta.copyWith(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: LbmConst.onGradient.withValues(alpha: 0.92),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Two across, square, like the website's tiles.
class _TileGrid extends StatelessWidget {
  const _TileGrid({required this.entries, required this.byHandle});

  final List<GiftGuideEntry> entries;
  final Map<String, Collection> byHandle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: GridView.count(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        children: [
          for (final entry in entries)
            PhotoTile(
              title: entry.title,
              fontSize: 14,
              imageUrl:
                  entry.imageUrl ??
                  entry.handles
                      .map((h) => byHandle[h]?.imageUrl)
                      .where((u) => u != null && u.isNotEmpty)
                      .firstOrNull,
              onTap: () => entry.isSingle
                  ? context.goToCollection(entry.handles.single)
                  : context.goToGiftGuideEntry(entry.id),
            ),
        ],
      ),
    );
  }
}

class _Closing extends StatelessWidget {
  const _Closing({required this.guide});

  final GiftGuide guide;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return LbmCard(
      margin: const EdgeInsets.fromLTRB(14, 24, 14, 0),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            guide.closingTitle,
            style: LbmText.display.copyWith(fontSize: 21, color: c.ink),
          ),
          const SizedBox(height: 8),
          Text(guide.closingBody, style: LbmText.tiny.copyWith(color: c.ink2)),
        ],
      ),
    );
  }
}

/// One tile of the guide that is several collections, all on one screen:
/// Sandee's picks for the home, for self care and to wear.
class GiftGuideEntryScreen extends ConsumerWidget {
  const GiftGuideEntryScreen({super.key, required this.entryId});

  final String entryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entry = kGiftGuide.entry(entryId);
    final byHandle = {
      for (final x in ref.watch(collectionsProvider).value ?? const []) x.handle: x,
    };

    return LbmScreen(
      appBar: LbmAppBar(
        title: entry?.title ?? 'Gift Guide',
        showBack: context.canPop(),
        actions: const [HomeButton()],
      ),
      child: entry == null
          ? const LbmEmpty(
              title: 'This part of the guide has moved',
              body: 'Go back to the gift guide to see what is in it now.',
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 28),
              children: [
                for (final handle in entry.handles)
                  _CollectionBlock(
                    handle: handle,
                    title: byHandle[handle]?.title,
                  ),
              ],
            ),
    );
  }
}

/// One collection's first page under its own heading, three across.
class _CollectionBlock extends ConsumerWidget {
  const _CollectionBlock({
    required this.handle,
    required this.title,
  });

  final String handle;
  final String? title;

  /// "Sandee's Picks - Home" under "Sandee's Market Picks" reads as "Home".
  String get _heading {
    final full = title ?? handle;
    final dash = full.lastIndexOf(' - ');
    return dash > 0 ? full.substring(dash + 3) : full;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final products = ref.watch(collectionProductsProvider(handle));
    return LbmAsync<Page<Product>>(
      products,
      skeleton: const Padding(
        padding: EdgeInsets.fromLTRB(14, 20, 14, 0),
        child: GridSkeleton(count: 3),
      ),
      onRetry: () => ref.invalidate(collectionProductsProvider(handle)),
      isEmpty: (page) => page.items.where(isShoppable).isEmpty,
      empty: const SizedBox.shrink(),
      data: (page) {
        final items = page.items.where(isShoppable).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ShelfHeading(
              _heading,
              onSeeAll: page.cursor == null
                  ? null
                  : () => context.goToCollection(handle),
            ),
            Padding(
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
          ],
        );
      },
    );
  }
}
