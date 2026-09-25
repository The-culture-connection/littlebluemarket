import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/feed_item.dart';
import '../../models/models.dart';
import '../../router/nav.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../product_art.dart';
import 'pin_caption.dart';

/// Somebody's cart, posted, as a four-up collage.
///
/// The items are the **snapshot** the post was made from, never the live
/// products. A cart changes by the minute; a post that quietly restocked
/// itself, or emptied at checkout, is a bug people notice at once.
class CartPin extends ConsumerWidget {
  const CartPin({super.key, required this.item, this.onAddAll});

  CartPin.of(CartPost post, {Key? key, VoidCallback? onAddAll})
    : this(key: key, item: CartItem(post), onAddAll: onAddAll);

  final CartItem item;

  /// Adds every snapshot line at once. Wired by the feed, which owns the
  /// repository call; the pin only draws the affordance.
  final VoidCallback? onAddAll;

  /// Four tiles fit a column; the fourth becomes "+N" when there are more.
  static const _tiles = 4;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final post = item.post;
    final author = ref.watch(personProvider(post.authorId)).value;
    final items = post.items;
    // When there are more than four, the fourth cell becomes the counter, so
    // only three photographs are shown and the counter stands for everything
    // else — including the one whose place it took.
    final hasMore = items.length > _tiles;
    final shown = items.take(hasMore ? _tiles - 1 : _tiles).toList();
    final hidden = items.length - shown.length;

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
                child: ColoredBox(
                  color: c.skyMist,
                  child: GridView.count(
                    crossAxisCount: 2,
                    mainAxisSpacing: 3,
                    crossAxisSpacing: 3,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      for (final line in shown)
                        _CollageTile(url: line.imageUrl, title: line.title),
                      if (hidden > 0)
                        ColoredBox(
                          color: c.ink,
                          child: Center(
                            child: Text(
                              '+$hidden',
                              style: LbmText.display.copyWith(
                                fontSize: 16,
                                color: c.surface,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Positioned(right: 2, top: 2, child: PinMore(post: post)),
            ],
          ),
          PinCaption(
            title: post.caption?.isNotEmpty == true
                ? post.caption!
                : "${author?.name.split(RegExp(r'\s+')).first ?? 'A'}'s cart",
            author: author,
            byline: '${post.itemCount} things',
            trailing: onAddAll == null
                ? null
                : GestureDetector(
                    onTap: onAddAll,
                    child: Text(
                      'Add all',
                      style: LbmText.pinMeta.copyWith(
                        color: c.accentText,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _CollageTile extends StatelessWidget {
  const _CollageTile({required this.url, required this.title});

  final String? url;
  final String title;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    if (url == null || url!.isEmpty) {
      return ColoredBox(
        color: c.skyWash,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Text(
              title,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: LbmText.pinMeta.copyWith(color: c.ink3),
            ),
          ),
        ),
      );
    }
    return ColoredBox(
      color: c.skyWash,
      child: ProductPhoto(
        url: url!,
        cacheWidth: 300,
        fallback: ColoredBox(color: c.skyWash),
      ),
    );
  }
}
