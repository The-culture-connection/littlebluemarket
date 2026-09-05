import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/repositories.dart';
import '../models/models.dart';
import '../router/nav.dart';
import '../state/providers.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'async.dart';
import 'primitives.dart';
import 'product_art.dart';
import 'sheets.dart';
import 'skeleton.dart';
import 'tips.dart';

/// An entry in the feed.
///
/// Switches over the sealed [Post], so the three kinds share the header, the
/// action bar and the tag row and differ only in their body. Adding a fourth
/// kind is a compile error here rather than a silently blank card.
class PostCard extends ConsumerWidget {
  const PostCard(this.post, {super.key});

  final Post post;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final author = ref.watch(personProvider(post.authorId));

    return LbmCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LbmAsync<Person>(
            author,
            skeleton: const _HeadSkeleton(),
            errorBuilder: (_, _) => const _HeadSkeleton(),
            data: (person) => _PostHead(post: post, author: person),
          ),
          switch (post) {
            final ListingPost listing => _ListingBody(post: listing),
            final ReviewPost review => _ReviewBody(post: review),
            final ShoutoutPost shoutout => _ShoutoutBody(post: shoutout),
            final CartPost cart => _CartBody(post: cart),
          },
        ],
      ),
    );
  }
}

/// Add to cart and comment, shared by the feed card and the post screen.
///
/// There is no like. On Little Blue Market adding something to your cart is
/// how you show a maker you love their work, and the count line says how
/// many people have. One widget rather than two look-alikes: the row
/// appeared verbatim in both places and the copies had drifted apart.
class PostActionBar extends StatelessWidget {
  const PostActionBar({
    super.key,
    this.onComment,
    this.onAddToCart,
    this.inCart = false,
  });

  final VoidCallback? onComment;
  final VoidCallback? onAddToCart;

  /// Whether the viewer's cart already holds this listing. A filled, accent
  /// cart says so; tapping it again takes the listing back out.
  final bool inCart;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 11, 16, 4),
      child: Row(
        children: [
          if (onAddToCart != null) ...[
            _ActionIcon(
              icon: inCart
                  ? Icons.shopping_cart_rounded
                  : Icons.add_shopping_cart_rounded,
              label: inCart ? 'Remove from cart' : 'Add to cart',
              tint: inCart ? context.c.accentDeep : null,
              onTap: onAddToCart,
            ),
            const SizedBox(width: 16),
          ],
          _ActionIcon(
            icon: Icons.chat_bubble_outline_rounded,
            label: 'Comments',
            onTap: onComment,
          ),
        ],
      ),
    );
  }
}

/// Adds a listing to the cart and says so, or says why it could not.
Future<void> addToCart(
  BuildContext context,
  WidgetRef ref,
  String productId, {
  String? variantId,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await ref
        .read(commerceRepositoryProvider)
        .addLine(productId: productId, variantId: variantId);
    messenger.showSnackBar(const SnackBar(content: Text('Added to your cart')));
  } on RepositoryException catch (error) {
    messenger.showSnackBar(SnackBar(content: Text(describeError(error).body)));
  }
}

class _ListingBody extends ConsumerWidget {
  const _ListingBody({required this.post});

  final ListingPost post;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final product = post.product;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: GestureDetector(
            onTap: () => context.goToProduct(product.id),
            child: ProductArt(product, borderRadius: LbmRadius.imageR),
          ),
        ),
        _Actions(post: post, productId: product.id),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CountLine(post: post),
              const SizedBox(height: 8),
              Text(
                post.body,
                style: TextStyle(fontSize: 14, height: 1.5, color: c.ink),
              ),
              const SizedBox(height: 8),
              TagChips(post.tags, onTap: (tag) => context.goToResults(tag)),
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
                      child: _RatingLine(
                        product:
                            ref.watch(liveProductProvider(product.id)).value ??
                            product,
                      ),
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
    );
  }
}

/// A buyer's review, in the feed.
class _ReviewBody extends ConsumerWidget {
  const _ReviewBody({required this.post});

  final ReviewPost post;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final product = ref.watch(productProvider(post.productId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stars(post.rating.toDouble(), size: 13),
              const SizedBox(height: 8),
              Text(
                post.text,
                style: TextStyle(fontSize: 14, height: 1.55, color: c.ink),
              ),
            ],
          ),
        ),
        // The listing being reviewed, so a review is a way into the product
        // rather than a dead end.
        LbmAsync<Product>(
          product,
          skeleton: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14),
            child: LbmSkeleton(height: 62, radius: LbmRadius.image),
          ),
          errorBuilder: (_, _) => const SizedBox.shrink(),
          data: (product) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: LbmCard(
              color: c.skyWash,
              padding: EdgeInsets.zero,
              onTap: () => context.goToProduct(product.id),
              child: ListRow(
                leading: SizedBox(
                  width: 44,
                  child: ProductArt(
                    product,
                    square: true,
                    borderRadius: const BorderRadius.all(Radius.circular(10)),
                  ),
                ),
                title: Text(product.title),
                subtitle: Text(product.price),
                trailing: Icon(
                  Icons.chevron_right_rounded,
                  size: 22,
                  color: c.ink3,
                ),
              ),
            ),
          ),
        ),
        _Actions(post: post, productId: post.productId),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CountLine(post: post),
              if (post.tags.isNotEmpty) ...[
                const SizedBox(height: 8),
                TagChips(post.tags, onTap: (tag) => context.goToResults(tag)),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// A shoutout: someone naming a seller they want other people to find.
class _ShoutoutBody extends ConsumerWidget {
  const _ShoutoutBody({required this.post});

  final ShoutoutPost post;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
          child: HashtagText(
            post.text,
            style: TextStyle(fontSize: 14.5, height: 1.55, color: c.ink),
            onTagTap: (tag) => context.goToResults(tag),
          ),
        ),
        if (post.aboutSellerId != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: PillButton(
                'Visit the storefront',
                style: PillStyle.quiet,
                small: true,
                expand: false,
                onPressed: () => context.goToSeller(post.aboutSellerId!),
              ),
            ),
          ),
        _Actions(post: post),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CountLine(post: post),
              if (post.tags.isNotEmpty) ...[
                const SizedBox(height: 8),
                TagChips(post.tags, onTap: (tag) => context.goToResults(tag)),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// The action bar, wired to the repository.
class _Actions extends ConsumerWidget {
  const _Actions({required this.post, this.productId});

  final Post post;
  final String? productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = productId;
    // The viewer's own cart, live: the icon fills the moment the line lands.
    final cart = ref.watch(cartProvider).value;
    final line = id == null
        ? null
        : cart?.lines.cast<CartLine?>().firstWhere(
            (l) => l?.productId == id,
            orElse: () => null,
          );
    return PostActionBar(
      inCart: line != null,
      onComment: () => context.goToPost(post.id),
      onAddToCart: id == null
          ? null
          : () => requireProfile(context, ref, () async {
              if (line != null) {
                // Tapping the filled cart takes it back out, the way a
                // second tap on a heart used to.
                final messenger = ScaffoldMessenger.of(context);
                try {
                  await ref
                      .read(commerceRepositoryProvider)
                      .removeLine(line.id);
                  messenger.showSnackBar(
                    const SnackBar(content: Text('Removed from your cart')),
                  );
                } on RepositoryException catch (error) {
                  messenger.showSnackBar(
                    SnackBar(content: Text(describeError(error).body)),
                  );
                }
                return;
              }
              // The first time, say what the cart means here.
              await showCartTipOnce(context, ref);
              if (!context.mounted) return;
              await addToCart(context, ref, id);
            }),
    );
  }
}

class _PostHead extends StatelessWidget {
  const _PostHead({required this.post, required this.author});

  final Post post;
  final Person author;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final isListing = post is ListingPost;
    final where = post is ListingPost
        ? (post as ListingPost).product.locationLabel()
        : post.age;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      child: Row(
        children: [
          Avatar(author, onTap: () => context.goToSeller(author.id)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  author.name,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                    color: c.ink,
                  ),
                ),
                Row(
                  children: [
                    Icon(
                      isListing ? Icons.place_outlined : Icons.schedule_rounded,
                      size: 13,
                      color: c.ink3,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        where,
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

class _HeadSkeleton extends StatelessWidget {
  const _HeadSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(14, 12, 14, 10),
      child: Row(
        children: [
          LbmSkeleton(width: 38, height: 38, radius: 19),
          SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LbmSkeleton(width: 120, height: 12),
              SizedBox(height: 6),
              LbmSkeleton(width: 80, height: 10),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActionIcon extends StatelessWidget {
  const _ActionIcon({
    required this.icon,
    required this.label,
    this.onTap,
    this.tint,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: InkResponse(
        onTap: onTap ?? () {},
        radius: 22,
        child: Icon(icon, size: 23, color: tint ?? context.c.ink),
      ),
    );
  }
}

/// "N added · M comments" for a listing; "M comments" for everything else.
/// "Added" is the product's own save count, so the number is the same on
/// every post about that product.
class _CountLine extends ConsumerWidget {
  const _CountLine({required this.post});

  final Post post;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final snapshot = post is ListingPost ? (post as ListingPost).product : null;
    // Live where possible: the feed's copy of the product was taken when the
    // feed loaded, and the count has usually moved since.
    final product = snapshot == null
        ? null
        : ref.watch(liveProductProvider(snapshot.id)).value ?? snapshot;
    return Text.rich(
      TextSpan(
        style: LbmText.tiny.copyWith(color: c.ink2),
        children: [
          if (product != null) ...[
            TextSpan(
              text: '${Fmt.count(product.saveCount)} added',
              style: TextStyle(fontWeight: FontWeight.w700, color: c.ink),
            ),
            const TextSpan(text: ' · '),
          ],
          TextSpan(text: '${Fmt.count(post.commentCount)} comments'),
        ],
      ),
    );
  }
}

/// Someone's cart, posted: a row of what is in it and one tap to add it all.
class _CartBody extends ConsumerStatefulWidget {
  const _CartBody({required this.post});

  final CartPost post;

  @override
  ConsumerState<_CartBody> createState() => _CartBodyState();
}

class _CartBodyState extends ConsumerState<_CartBody> {
  bool _adding = false;

  Future<void> _addAll() async {
    if (_adding) return;
    setState(() => _adding = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await ref.read(commerceRepositoryProvider).addManyLines([
        for (final i in widget.post.items) i.productId,
      ]);
      final skipped = result.skipped.length;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            skipped == 0
                ? 'Added ${result.added.length} to your cart'
                : 'Added ${result.added.length}; $skipped could not be '
                      'added (${result.skipped.values.toSet().join(', ')})',
          ),
        ),
      );
    } on RepositoryException catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text(describeError(error).body)),
      );
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final post = widget.post;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (post.caption != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
            child: HashtagText(
              post.caption!,
              style: TextStyle(fontSize: 14.5, height: 1.55, color: c.ink),
              onTagTap: (tag) => context.goToResults(tag),
            ),
          ),
        SizedBox(
          // Two text lines under the image; the row grows with the text
          // scale rather than overflowing at 2.0.
          height: 84 + 36 * MediaQuery.textScalerOf(context).scale(1),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            itemCount: post.items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) => _CartItemTile(item: post.items[i]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          // A Wrap, not a Row: at 2.0 text the button drops below the count
          // instead of running off the right edge.
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              Text(
                '${post.itemCount} ${post.itemCount == 1 ? 'thing' : 'things'}',
                style: LbmText.tiny.copyWith(color: c.ink2),
              ),
              PillButton(
                _adding ? 'Adding…' : 'Add all to my cart',
                small: true,
                expand: false,
                onPressed: _adding
                    ? null
                    : () => requireProfile(context, ref, _addAll),
              ),
            ],
          ),
        ),
        _Actions(post: post),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CountLine(post: post),
              if (post.tags.isNotEmpty) ...[
                const SizedBox(height: 8),
                TagChips(post.tags, onTap: (tag) => context.goToResults(tag)),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _CartItemTile extends StatelessWidget {
  const _CartItemTile({required this.item});

  final CartPostItem item;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final url = item.imageUrl;
    return GestureDetector(
      onTap: () => context.goToProduct(item.productId),
      child: SizedBox(
        width: 92,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 92,
              height: 78,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: c.skyWash,
                borderRadius: BorderRadius.circular(12),
              ),
              child: url == null
                  ? const SizedBox.shrink()
                  : url.startsWith('asset://')
                  ? Image.asset(url.substring(8), fit: BoxFit.cover)
                  : Image.network(
                      url,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    ),
            ),
            const SizedBox(height: 4),
            Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: LbmText.xtiny.copyWith(color: c.ink),
            ),
            Text(
              item.price,
              style: LbmText.xtiny.copyWith(
                fontWeight: FontWeight.w800,
                color: c.ink,
              ),
            ),
          ],
        ),
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
class ReviewRow extends ConsumerWidget {
  const ReviewRow(this.review, {super.key});

  final Review review;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final author = ref.watch(personProvider(review.authorId));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LbmAsync<Person>(
            author,
            skeleton: const LbmSkeleton(width: 34, height: 34, radius: 17),
            errorBuilder: (_, _) =>
                const LbmSkeleton(width: 34, height: 34, radius: 17),
            data: (person) => Avatar(
              person,
              size: AvatarSize.sm,
              onTap: () => context.goToSeller(person.id),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
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
