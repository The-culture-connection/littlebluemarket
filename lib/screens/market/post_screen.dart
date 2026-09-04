import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/fixtures.dart';
import '../../router/nav.dart';
import '../../state/session.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/post_card.dart';
import '../../widgets/primitives.dart';
import '../../widgets/product_art.dart';
import '../../widgets/screen.dart';
import '../../widgets/sheets.dart';

/// A post on its own.
///
/// The avatar row taps through to that seller's feed. The reviews below are
/// tied to this product, not to the seller.
class PostScreen extends ConsumerWidget {
  const PostScreen({super.key, required this.productId});

  final String productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final product = Fx.product(productId);
    final seller = Fx.person(product.sellerId);
    final reviews = Fx.reviewsFor(productId);
    final isGuest = ref.watch(isGuestProvider);

    return LbmScreen(
      appBar: LbmAppBar(
        title: 'Post',
        actions: [
          CircleIconButton(
            icon: Icons.more_horiz_rounded,
            tooltip: 'More',
            onPressed: () {},
          ),
        ],
      ),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          LbmCard(
            margin: const EdgeInsets.symmetric(horizontal: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                  child: Row(
                    children: [
                      Avatar(
                        seller,
                        onTap: () => context.goToSeller(seller.id),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => context.goToSeller(seller.id),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text.rich(
                                TextSpan(
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    height: 1.2,
                                    color: c.ink,
                                  ),
                                  children: [
                                    TextSpan(text: '${seller.name} '),
                                    TextSpan(
                                      text: seller.handle,
                                      style: TextStyle(color: c.skyDeep),
                                    ),
                                  ],
                                ),
                              ),
                              Row(
                                children: [
                                  Icon(
                                    Icons.place_outlined,
                                    size: 13,
                                    color: c.ink3,
                                  ),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      '${product.location} · tap for their feed',
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
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: ProductArt(product, borderRadius: LbmRadius.imageR),
                ),
                const _PostActionRow(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 2, 16, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text.rich(
                        TextSpan(
                          style: LbmText.tiny.copyWith(color: c.ink2),
                          children: [
                            TextSpan(
                              text: '${product.likes} likes',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: c.ink,
                              ),
                            ),
                            TextSpan(
                              text: ' · ${product.commentCount} comments',
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        product.title,
                        style: LbmText.display.copyWith(
                          fontSize: 21,
                          height: 1.2,
                          color: c.ink,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        product.description,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.55,
                          color: c.ink2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TagChips(
                        product.tags,
                        onTap: (tag) => context.goToResults(tag),
                        trailing: [
                          LbmChip(product.type, style: ChipStyle.quiet),
                        ],
                      ),
                    ],
                  ),
                ),
                ListRow(
                  divided: true,
                  title: const Text('Product details'),
                  subtitle: const Text(
                    'Options, materials, shipping, returns',
                  ),
                  trailing: Icon(
                    Icons.chevron_right_rounded,
                    color: c.ink3,
                    size: 22,
                  ),
                  onTap: () => context.goToProduct(productId),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          product.price,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: LbmText.display.copyWith(
                            fontSize: 22,
                            color: c.ink,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: PillButton(
                          isGuest ? 'Buy · sign up' : 'Buy',
                          onPressed: () => requireProfile(
                            context,
                            ref,
                            () => showBuySheet(context, product),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          SectionHead(
            'Reviews of this product',
            trailing: InlineLink(
              'See all ${product.ratingCount}',
              onTap: () => context.goToReviews(productId),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
            child: Row(
              children: [
                Stars(product.rating, size: 14),
                const SizedBox(width: 10),
                Text(
                  product.rating.toStringAsFixed(1),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: c.ink,
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'from ${product.ratingCount} verified buyers',
                    style: LbmText.tiny.copyWith(color: c.ink2),
                  ),
                ),
              ],
            ),
          ),
          LbmCard(
            margin: const EdgeInsets.symmetric(horizontal: 14),
            child: reviews.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'No reviews yet — be the first after you buy.',
                      style: LbmText.tiny.copyWith(color: c.ink2),
                    ),
                  )
                : RowStack(
                    children: [
                      for (final review in reviews.take(2)) ReviewRow(review),
                    ],
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: PillButton(
              'Read all reviews',
              style: PillStyle.quiet,
              onPressed: () => context.goToReviews(productId),
            ),
          ),
        ],
      ),
    );
  }
}

class _PostActionRow extends StatelessWidget {
  const _PostActionRow();

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    Widget icon(IconData data, String label) => Semantics(
      button: true,
      label: label,
      child: InkResponse(
        onTap: () {},
        radius: 22,
        child: Icon(data, size: 23, color: c.ink),
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 11, 16, 4),
      child: Row(
        children: [
          icon(Icons.favorite_border_rounded, 'Like'),
          const SizedBox(width: 16),
          icon(Icons.chat_bubble_outline_rounded, 'Comment'),
          const SizedBox(width: 16),
          icon(Icons.send_outlined, 'Share'),
          const Spacer(),
          icon(Icons.bookmark_border_rounded, 'Save'),
        ],
      ),
    );
  }
}
