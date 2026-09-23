// Flutter's own Page (a Navigator route) is not wanted here; Page is the
// app's page-of-results model.
import 'package:flutter/material.dart' hide Page;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/market_taxonomy.dart';
import '../../models/models.dart';
import '../../router/nav.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../data/repositories/repositories.dart';
import '../../widgets/async.dart';
import '../../widgets/primitives.dart';
import '../../widgets/screen.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/sort_bar.dart';
import 'results_screen.dart';

/// Everything filed under one collection, three across, newest first.
///
/// An initiative ("Ally Owned") and a category ("Bath, Beauty & Wellness")
/// are the same thing to the store, so they are the same screen here.
///
/// Paged: the repository hands back thirty at a time and the pages after the
/// first are kept here. A tester counted twenty-seven listings in a category
/// and reasonably concluded that was all of them (Grace, 2026-09-23).
class CollectionScreen extends ConsumerStatefulWidget {
  const CollectionScreen({super.key, required this.handle});

  final String handle;

  @override
  ConsumerState<CollectionScreen> createState() => _CollectionScreenState();
}

class _CollectionScreenState extends ConsumerState<CollectionScreen> {
  /// Everything after the first page, which the provider owns.
  final _more = <Product>[];
  String? _cursor;
  bool _loadingMore = false;
  String? _moreError;

  /// Set once the first page has been seen, so [_cursor] is not re-seeded
  /// from it on every rebuild and the end of the list is not forgotten.
  String? _seededFrom;

  SortOrder _sort = SortOrder.relevance;

  void _reset() {
    _more.clear();
    _cursor = null;
    _seededFrom = null;
    _moreError = null;
  }

  Future<void> _loadMore() async {
    final cursor = _cursor;
    if (cursor == null || _loadingMore) return;
    setState(() {
      _loadingMore = true;
      _moreError = null;
    });
    try {
      final page = await ref
          .read(collectionRepositoryProvider)
          .productsInCollection(widget.handle, cursor: cursor);
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
    final c = context.c;
    final collection = ref.watch(collectionProvider(widget.handle));
    final first = ref.watch(collectionProductsProvider(widget.handle));

    // Seed the cursor from the first page once it arrives, and again if the
    // provider is invalidated by a pull to refresh.
    if (first.value case final page? when _seededFrom != widget.handle) {
      _seededFrom = widget.handle;
      _cursor = page.cursor;
    }

    return LbmScreen(
      appBar: LbmAppBar(title: collection.value?.title ?? 'Collection'),
      child: RefreshIndicator(
        onRefresh: () async {
          setState(_reset);
          ref.invalidate(collectionProvider(widget.handle));
          ref.invalidate(collectionProductsProvider(widget.handle));
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
            // Inside a heading: the narrower ones under it. A heading holds
            // everything its subcategories hold, so these narrow the view
            // rather than reveal anything the heading was hiding.
            _Subcategories(parent: widget.handle),
            LbmAsync<Page<Product>>(
              first,
              skeleton: const GridSkeleton(count: 6),
              onRetry: () =>
                  ref.invalidate(collectionProductsProvider(widget.handle)),
              isEmpty: (page) => page.items.isEmpty,
              empty: const LbmEmpty(
                title: 'Nothing here yet',
                body:
                    'This collection is empty on the store, or the catalog '
                    'has not been imported yet.',
              ),
              data: (page) {
                final items = sortProducts([...page.items, ..._more], _sort);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                      child: SortBar(
                        sort: _sort,
                        // How many are actually on the screen, so "27" is a
                        // fact about this list rather than about the store.
                        count: items.length,
                        onChanged: (sort) => setState(() => _sort = sort),
                      ),
                    ),
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
                        itemCount: items.length,
                        itemBuilder: (context, i) => GridCell(
                          product: items[i],
                          badge: items[i].price,
                          onTap: () => context.goToProduct(items[i].id),
                        ),
                      ),
                    ),
                    if (_moreError != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
                        child: Text(
                          _moreError!,
                          style: LbmText.tiny.copyWith(
                            color: c.clay,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    if (_cursor != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 16, 14, 0),
                        child: PillButton(
                          _loadingMore ? 'Loading' : 'Load more',
                          style: PillStyle.quiet,
                          onPressed: _loadingMore ? null : _loadMore,
                        ),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
                        child: Text(
                          "That's everything in here.",
                          textAlign: TextAlign.center,
                          style: LbmText.tiny.copyWith(color: c.ink3),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// The horizontal "Browse the Market" rail on the feed: one chip per
/// heading, in Grace's order, hidden entirely when the store has none.
///
/// Not every collection. The store has a hundred, including seasonal ones
/// and seller spotlights, and all of them on one rail made it useless as a
/// front door (Grace, 2026-09-14). `kMarketCategories` is the seven she
/// picked; the subcategories live inside each heading's own screen.
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
      data: (all) {
        final byHandle = {for (final c in all) c.handle: c};
        final items = [
          for (final handle in kMarketCategoryHandles) ?byHandle[handle],
        ];
        if (items.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(0, 0, 0, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                child: Text(
                  'Browse the Market',
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
        );
      },
    );
  }
}

/// The subcategories under one heading, as a wrapped row of chips.
///
/// Silent for anything that is not one of the seven, and silent for a
/// subcategory the store no longer has, so a collection renamed in Shopify
/// costs a missing chip rather than a dead one.
class _Subcategories extends ConsumerWidget {
  const _Subcategories({required this.parent});

  final String parent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final children = marketChildrenOf(parent);
    if (children.isEmpty) return const SizedBox.shrink();
    final all = ref.watch(collectionsProvider).value ?? const <Collection>[];
    final byHandle = {for (final c in all) c.handle: c};
    final shown = [for (final handle in children) ?byHandle[handle]];
    if (shown.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      child: Wrap(
        spacing: 7,
        runSpacing: 7,
        children: [
          for (final child in shown)
            LbmChip(
              child.title,
              onTap: () => context.goToCollection(child.handle),
            ),
        ],
      ),
    );
  }
}
