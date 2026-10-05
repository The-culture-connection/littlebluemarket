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
                child: AspectRatio(
                  aspectRatio: 1,
                  child: ColoredBox(
                    color: c.skyMist,
                    child: _Collage(
                      items: shown,
                      hidden: hidden,
                    ),
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

/// The photographs of a posted cart, laid out so there is never a hole.
///
/// A fixed two-by-two grid left empty cells whenever somebody posted a cart
/// with one, two or three things in it, which is most of them: the pin came
/// out as one photo and a pale blue block (Grace, with a screenshot). Each
/// count gets its own arrangement instead, and every one of them fills the
/// square completely.
class _Collage extends StatelessWidget {
  const _Collage({required this.items, required this.hidden});

  final List<CartPostItem> items;

  /// How many more the post holds than are shown, drawn as "+N" in the last
  /// cell. Zero means every item is a photograph.
  final int hidden;

  static const _gap = 3.0;

  @override
  Widget build(BuildContext context) {
    final cells = <Widget>[
      for (final line in items)
        _CollageTile(url: line.imageUrl, title: line.title),
      if (hidden > 0) _MoreTile(hidden: hidden),
    ];

    // Stretched, every one of them: a Row centres its children by default,
    // so each cell sized itself to its photograph and left pale bands above
    // and below rather than filling the square.
    return switch (cells.length) {
      0 => const SizedBox.expand(),
      1 => SizedBox.expand(child: cells.first),
      2 => Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: cells[0]),
          const SizedBox(width: _gap),
          Expanded(child: cells[1]),
        ],
      ),
      // One tall on the left, two stacked on the right.
      3 => Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: cells[0]),
          const SizedBox(width: _gap),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: cells[1]),
                const SizedBox(height: _gap),
                Expanded(child: cells[2]),
              ],
            ),
          ),
        ],
      ),
      _ => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: cells[0]),
                const SizedBox(width: _gap),
                Expanded(child: cells[1]),
              ],
            ),
          ),
          const SizedBox(height: _gap),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: cells[2]),
                const SizedBox(width: _gap),
                Expanded(child: cells[3]),
              ],
            ),
          ),
        ],
      ),
    };
  }
}

class _MoreTile extends StatelessWidget {
  const _MoreTile({required this.hidden});

  final int hidden;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return ColoredBox(
      color: c.ink,
      child: Center(
        child: Text(
          '+$hidden',
          style: LbmText.display.copyWith(fontSize: 16, color: c.surface),
        ),
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
        // Fills its cell rather than letterboxing inside it, which is what
        // left pale bands down the side of a one-item collage.
        fit: BoxFit.cover,
        cacheWidth: 300,
        fallback: ColoredBox(color: c.skyWash),
      ),
    );
  }
}
