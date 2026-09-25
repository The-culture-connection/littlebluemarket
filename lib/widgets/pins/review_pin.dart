import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/feed_item.dart';
import '../../models/models.dart';
import '../../router/nav.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../primitives.dart';
import '../product_art.dart';
import 'pin_caption.dart';

/// Somebody's review, in the grid.
///
/// Square rather than natural, so a run of reviews reads as a different kind
/// of thing from a run of products without needing a label. The photograph is
/// the reviewer's own if they added one, otherwise the product's: a review
/// without a picture is still worth showing.
class ReviewPin extends ConsumerWidget {
  const ReviewPin({super.key, required this.item});

  ReviewPin.of(ReviewPost post, {Key? key})
    : this(key: key, item: ReviewItem(post));

  final ReviewItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final post = item.post;
    final reviewer = ref.watch(personProvider(post.authorId)).value;
    final product = ref.watch(productProvider(post.productId)).value;
    final photo = post.imageUrls.firstOrNull ?? product?.imageUrls.firstOrNull;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => context.goToPost(post.id),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            children: [
              ClipRRect(
                borderRadius: LbmRadius.imageR,
                child: AspectRatio(
                  aspectRatio: 1,
                  child: ColoredBox(
                    color: c.skyWash,
                    child: photo == null || photo.isEmpty
                        ? (product == null
                              ? const SizedBox.expand()
                              : ProductArt(product, square: true))
                        : ProductPhoto(
                            url: photo,
                            fallback: product == null
                                ? ColoredBox(color: c.skyMist)
                                : ProductArt(product, square: true),
                          ),
                  ),
                ),
              ),
              Positioned(
                left: 8,
                bottom: 8,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: LbmRadius.pillR,
                    boxShadow: c.shadowSoft,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: Stars(post.rating.toDouble(), size: 12),
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 7, 4, 0),
            child: Text(
              '“${post.text}”',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: LbmText.display.copyWith(
                fontSize: 13.5,
                height: 1.25,
                color: c.ink,
              ),
            ),
          ),
          PinCaption(
            title: '',
            maxLines: 1,
            author: reviewer,
            // "bought it" is the verified part: a review only exists for a
            // line the order pipeline recorded.
            byline: reviewer == null
                ? null
                : '${reviewer.name.split(RegExp(r'\s+')).first}'
                      '${post.purchaseId != null ? ' · bought it' : ''}',
          ),
        ],
      ),
    );
  }
}
