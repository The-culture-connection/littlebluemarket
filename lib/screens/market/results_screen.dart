import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

/// Search results: products, then sellers, then reviews carrying the tag.
///
/// A review is indexed under the product it is attached to, so a tagged review
/// links back to its parent product rather than to its author.
class ResultsScreen extends ConsumerStatefulWidget {
  const ResultsScreen({super.key, required this.query});

  final String query;

  @override
  ConsumerState<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends ConsumerState<ResultsScreen> {
  @override
  void initState() {
    super.initState();
    // The query arrives in the route; the filters own it from here, so the
    // scope chips and the radius apply to it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(searchFiltersProvider.notifier).setQuery(widget.query);
    });
  }

  @override
  Widget build(BuildContext context) {
    final filters = ref.watch(searchFiltersProvider);
    // Until the post-frame callback lands, search what the route asked for.
    final active = filters.query == widget.query
        ? filters
        : filters.copyWith(query: widget.query);
    final results = ref.watch(searchResultsProvider(active));

    return LbmScreen(
      appBar: LbmAppBar(
        titleWidget: SearchPill(label: widget.query, strong: true),
      ),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 2, 14, 4),
            child: Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: [
                      // These filter for real now, and they are the same
                      // SearchScope the search screen uses — the prototype had
                      // two different cosmetic lists.
                      for (final scope in SearchScope.values)
                        LbmChip(
                          scope.label,
                          style: scope == active.scope
                              ? ChipStyle.on
                              : ChipStyle.quiet,
                          onTap: () => ref
                              .read(searchFiltersProvider.notifier)
                              .setScope(scope),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                NearMeButton(
                  active: active.nearMe,
                  onTap: () =>
                      ref.read(searchFiltersProvider.notifier).toggleNearMe(),
                ),
              ],
            ),
          ),
          LbmAsync<SearchResults>(
            results,
            skeleton: const _ResultsSkeleton(),
            onRetry: () => ref.invalidate(searchResultsProvider(active)),
            isEmpty: (results) => results.isEmpty,
            empty: LbmEmpty(
              title: 'Nothing for “${widget.query}”',
              body: active.isGeoConstrained
                  ? 'Try a wider radius, or turn off Near me.'
                  : 'Try a different word, or one of the hashtags.',
            ),
            data: (results) => _Results(results: results, query: widget.query),
          ),
          const Puff(),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

class _Results extends StatelessWidget {
  const _Results({required this.results, required this.query});

  final SearchResults results;
  final String query;

  @override
  Widget build(BuildContext context) {
    final c = context.c;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The counts live inside the loaded data on purpose: while a search is
        // running there is no honest number to print.
        if (results.products.isNotEmpty) ...[
          SectionHead('${results.products.length} products'),
          _ProductGrid(products: results.products),
        ],
        if (results.sellers.isNotEmpty) ...[
          SectionHead('${results.sellers.length} sellers'),
          LbmCard(
            margin: const EdgeInsets.symmetric(horizontal: 14),
            child: RowStack(
              children: [
                for (final person in results.sellers) _SellerRow(person: person),
              ],
            ),
          ),
        ],
        if (results.reviews.isNotEmpty) ...[
          SectionHead('${results.reviews.length} reviews tagged $query'),
          LbmCard(
            margin: const EdgeInsets.symmetric(horizontal: 14),
            child: RowStack(
              children: [
                for (final hit in results.reviews)
                  _TaggedReviewRow(productId: hit.productId, review: hit.review),
              ],
            ),
          ),
        ] else
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
            child: Text(
              'No reviews carry this tag yet.',
              style: LbmText.tiny.copyWith(color: c.ink3),
            ),
          ),
      ],
    );
  }
}

class _ResultsSkeleton extends StatelessWidget {
  const _ResultsSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        SizedBox(height: 12),
        GridSkeleton(count: 6),
        SizedBox(height: 18),
        ListRowSkeleton(rows: 2),
      ],
    );
  }
}

/// The three-up grid of product tiles, each stamped with its price.
class _ProductGrid extends StatelessWidget {
  const _ProductGrid({required this.products});

  final List<Product> products;

  @override
  Widget build(BuildContext context) {
    return Padding(
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
        itemBuilder: (context, i) {
          final product = products[i];
          return GridCell(
            product: product,
            badge: product.price,
            onTap: () => context.goToProduct(product.id),
          );
        },
      ),
    );
  }
}

/// A square product tile with an optional corner stamp.
class GridCell extends StatelessWidget {
  const GridCell({
    super.key,
    required this.product,
    this.badge,
    required this.onTap,
  });

  final Product product;
  final String? badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return GestureDetector(
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.all(Radius.circular(14)),
          boxShadow: c.shadowSoft,
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: ProductArt(
                product,
                square: true,
                borderRadius: const BorderRadius.all(Radius.circular(14)),
              ),
            ),
            if (badge != null)
              Positioned(
                right: 5,
                top: 5,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.92),
                    borderRadius: LbmRadius.pillR,
                  ),
                  child: Text(
                    badge!,
                    style: const TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      color: LbmConst.artInk,
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

class _SellerRow extends StatelessWidget {
  const _SellerRow({required this.person});

  final Person person;

  @override
  Widget build(BuildContext context) {
    return ListRow(
      leading: Avatar(person),
      title: Text(person.name),
      subtitle: Text(
        '${person.handle} · ${person.tags.join(' ')}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const LbmChip('View', fontSize: 11),
      onTap: () => context.goToSeller(person.id),
    );
  }
}

class _TaggedReviewRow extends ConsumerWidget {
  const _TaggedReviewRow({required this.productId, required this.review});

  final String productId;
  final Review review;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final author = ref.watch(personProvider(review.authorId));
    final product = ref.watch(productProvider(productId));

    return ListRow(
      crossAxisAlignment: CrossAxisAlignment.start,
      leading: LbmAsync<Person>(
        author,
        skeleton: const LbmSkeleton(width: 34, height: 34, radius: 17),
        errorBuilder: (_, _) =>
            const LbmSkeleton(width: 34, height: 34, radius: 17),
        data: (person) => Avatar(person, size: AvatarSize.sm),
      ),
      onTap: () => context.goToReviews(productId),
      title: Row(
        children: [
          Flexible(
            child: LbmAsync<Person>(
              author,
              skeleton: const LbmSkeleton(width: 90, height: 12),
              errorBuilder: (_, _) => const SizedBox.shrink(),
              data: (person) => Text(
                person.name,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: c.ink,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Stars(review.rating.toDouble(), size: 11),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '“${review.text}”',
              style: TextStyle(fontSize: 12.5, height: 1.5, color: c.ink2),
            ),
            const SizedBox(height: 5),
            LbmAsync<Product>(
              product,
              skeleton: const LbmSkeleton(width: 120, height: 11),
              errorBuilder: (_, _) => const SizedBox.shrink(),
              data: (product) => InlineLink(
                'on ${product.title}',
                fontSize: 11.5,
                onTap: () => context.goToReviews(productId),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
