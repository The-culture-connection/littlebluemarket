import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/fixtures.dart';
import '../models/models.dart';
import '../router/nav.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'primitives.dart';
import 'product_art.dart';
import 'sheets.dart';

/// A listing in the feed.
class PostCard extends ConsumerWidget {
  const PostCard(this.product, {super.key});

  final Product product;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final seller = Fx.person(product.sellerId);

    return LbmCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PostHead(product: product, seller: seller),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: GestureDetector(
              onTap: () => context.goToPost(product.id),
              child: ProductArt(product, borderRadius: LbmRadius.imageR),
            ),
          ),
          PostActionBar(onComment: () => context.goToPost(product.id)),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _LikeLine(product: product),
                const SizedBox(height: 8),
                Text.rich(
                  TextSpan(
                    style: TextStyle(fontSize: 14, height: 1.5, color: c.ink),
                    children: [
                      TextSpan(
                        text: seller.handle,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      TextSpan(
                        text:
                            ' ${product.title} — ${product.shortDescription}.',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                TagChips(
                  product.tags,
                  onTap: (tag) => context.goToResults(tag),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        product.price,
                        style: LbmText.display.copyWith(
                          fontSize: 22,
                          color: c.ink,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: _RatingLine(product: product),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                PillButton(
                  'Buy',
                  small: true,
                  expand: false,
                  onPressed: () => requireProfile(
                    context,
                    ref,
                    () => showBuySheet(context, product),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PostHead extends StatelessWidget {
  const _PostHead({required this.product, required this.seller});

  final Product product;
  final Person seller;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      child: Row(
        children: [
          Avatar(seller, onTap: () => context.goToSeller(seller.id)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  seller.name,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                    color: c.ink,
                  ),
                ),
                Row(
                  children: [
                    Icon(Icons.place_outlined, size: 13, color: c.ink3),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        product.locationLabel(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.35,
                          color: c.ink3,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          CircleIconButton(
            icon: Icons.more_horiz_rounded,
            bare: true,
            tooltip: 'More',
            onPressed: () {},
          ),
        ],
      ),
    );
  }
}

/// Like, comment, and add-to-cart, shared by the feed card and the post screen.
///
/// One widget rather than two look-alikes: the row appeared verbatim in both
/// places, and the copies had already drifted apart in their callbacks.
class PostActionBar extends StatelessWidget {
  const PostActionBar({
    super.key,
    this.onLike,
    this.onComment,
    this.onAddToCart,
  });

  final VoidCallback? onLike;
  final VoidCallback? onComment;
  final VoidCallback? onAddToCart;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 11, 16, 4),
      child: Row(
        children: [
          _ActionIcon(
            icon: Icons.favorite_border_rounded,
            label: 'Like',
            onTap: onLike,
          ),
          const SizedBox(width: 16),
          _ActionIcon(
            icon: Icons.chat_bubble_outline_rounded,
            label: 'Comments',
            onTap: onComment,
          ),
          const Spacer(),
          _ActionIcon(
            icon: Icons.add_shopping_cart_rounded,
            label: 'Add to cart',
            onTap: onAddToCart,
          ),
        ],
      ),
    );
  }
}

class _ActionIcon extends StatelessWidget {
  const _ActionIcon({required this.icon, required this.label, this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: InkResponse(
        onTap: onTap ?? () {},
        radius: 22,
        child: Icon(icon, size: 23, color: context.c.ink),
      ),
    );
  }
}

class _LikeLine extends StatelessWidget {
  const _LikeLine({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Text.rich(
      TextSpan(
        style: LbmText.tiny.copyWith(color: c.ink2),
        children: [
          TextSpan(
            text: '${product.likes} likes',
            style: TextStyle(fontWeight: FontWeight.w700, color: c.ink),
          ),
          TextSpan(text: ' · ${product.commentCount} comments'),
        ],
      ),
    );
  }
}

class _RatingLine extends StatelessWidget {
  const _RatingLine({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stars(product.rating, size: 11),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            '${product.rating} (${product.ratingCount})',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: c.ink3,
              fontFeatures: kTabularFigures,
            ),
          ),
        ),
      ],
    );
  }
}

/// One review, as it appears on a post and on the reviews screen.
class ReviewRow extends StatelessWidget {
  const ReviewRow(this.review, {super.key});

  final Review review;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final author = Fx.person(review.authorId);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Avatar(
            author,
            size: AvatarSize.sm,
            onTap: () => context.goToSeller(author.id),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
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
                    const SizedBox(width: 7),
                    Stars(review.rating.toDouble(), size: 11),
                    const SizedBox(width: 7),
                    Text(
                      review.age,
                      style: LbmText.xtiny.copyWith(
                        color: c.ink2,
                        fontFeatures: kTabularFigures,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  review.text,
                  style: TextStyle(fontSize: 13.5, height: 1.5, color: c.ink2),
                ),
                if (review.tags.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  TagChips(
                    review.tags,
                    onTap: (tag) => context.goToResults(tag),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
