import 'package:flutter/material.dart';

import '../../data/fixtures/fixture_data.dart';
import '../../models/models.dart';
import '../../router/nav.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/primitives.dart';
import '../../widgets/product_art.dart';
import '../../widgets/screen.dart';

/// Search results: products, then sellers, then reviews carrying the tag.
///
/// A review is indexed under the product it is attached to, so a tagged review
/// links back to its parent product rather than to its author.
class ResultsScreen extends StatefulWidget {
  const ResultsScreen({super.key, required this.query});

  final String query;

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  int _scope = 0;
  bool _nearMe = true;

  static const _scopes = ['All', 'Hashtags', 'Type'];

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final productIds = Fx.search(widget.query);
    final sellerIds = <String>{
      for (final id in productIds) Fx.product(id).sellerId,
    }.toList();
    final taggedReviews = Fx.reviewsTagged(widget.query, productIds);

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
                      for (var i = 0; i < _scopes.length; i++)
                        LbmChip(
                          _scopes[i],
                          style: i == _scope ? ChipStyle.on : ChipStyle.quiet,
                          onTap: () => setState(() => _scope = i),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                NearMeButton(
                  active: _nearMe,
                  onTap: () => setState(() => _nearMe = !_nearMe),
                ),
              ],
            ),
          ),

          SectionHead('${productIds.length} products'),
          _ProductGrid(productIds: productIds),

          SectionHead('${sellerIds.length} sellers'),
          LbmCard(
            margin: const EdgeInsets.symmetric(horizontal: 14),
            child: RowStack(
              children: [
                for (final id in sellerIds)
                  _SellerRow(person: Fx.person(id)),
              ],
            ),
          ),

          SectionHead('${taggedReviews.length} reviews tagged ${widget.query}'),
          LbmCard(
            margin: const EdgeInsets.symmetric(horizontal: 14),
            child: taggedReviews.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'No reviews carry this tag yet.',
                      style: LbmText.tiny.copyWith(color: c.ink3),
                    ),
                  )
                : RowStack(
                    children: [
                      for (final hit in taggedReviews)
                        _TaggedReviewRow(
                          productId: hit.productId,
                          review: hit.review,
                        ),
                    ],
                  ),
          ),
          const Puff(),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

/// The three-up grid of product tiles, each stamped with its price.
class _ProductGrid extends StatelessWidget {
  const _ProductGrid({required this.productIds});

  final List<String> productIds;

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
        itemCount: productIds.length,
        itemBuilder: (context, i) {
          final product = Fx.product(productIds[i]);
          return GridCell(
            product: product,
            badge: product.price,
            onTap: () => context.goToPost(product.id),
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

class _TaggedReviewRow extends StatelessWidget {
  const _TaggedReviewRow({required this.productId, required this.review});

  final String productId;
  final Review review;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final author = Fx.person(review.authorId);
    final product = Fx.product(productId);

    return ListRow(
      crossAxisAlignment: CrossAxisAlignment.start,
      leading: Avatar(author, size: AvatarSize.sm),
      onTap: () => context.goToReviews(productId),
      title: Row(
        children: [
          Flexible(
            child: Text(
              author.name,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: c.ink,
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
            InlineLink(
              'on ${product.title}',
              fontSize: 11.5,
              onTap: () => context.goToReviews(productId),
            ),
          ],
        ),
      ),
    );
  }
}
