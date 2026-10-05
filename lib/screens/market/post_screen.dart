import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/repositories.dart';
import '../../models/models.dart';
import '../../router/nav.dart';
import '../../state/providers.dart';
import '../../state/session.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/async.dart';
import '../../widgets/cart_pill.dart';
import '../../widgets/detail_sheet.dart';
import '../../widgets/masonry.dart';
import '../../widgets/pins/pin_caption.dart';
import '../../widgets/post_card.dart';
import '../../widgets/primitives.dart';
import '../../widgets/product_art.dart';
import '../../widgets/report_sheet.dart';
import '../../widgets/screen.dart';
import '../../widgets/sheets.dart';
import '../../widgets/skeleton.dart';

/// A post on its own, with its comments.
///
/// Keyed by the post rather than by a product, because a review and a shoutout
/// are posts too and neither is a product. The listing a post is about, when
/// there is one, is one tap away.
class PostScreen extends ConsumerWidget {
  const PostScreen({super.key, required this.postId});

  final String postId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final post = ref.watch(postProvider(postId));
    // A review opens on a full-bleed photograph with its own floating Back
    // and "…", the way a product does. An app bar over it would be a band of
    // colour across the top of the picture, and a second Back button.
    final fullBleed = post.value is ReviewPost;

    return LbmScreen(
      appBar: fullBleed
          ? null
          : LbmAppBar(
              title: 'Post',
              actions: [
                CircleIconButton(
                  icon: Icons.more_horiz_rounded,
                  tooltip: 'More',
                  onPressed: () {
                    final p = post.value;
                    if (p == null) return;
                    final author = ref.read(personProvider(p.authorId)).value;
                    showMoreSheet(
                      context,
                      ref,
                      subjectUid: p.authorId,
                      subjectName: author?.name ?? '',
                      subjectHandle: author?.handle ?? '@${p.authorId}',
                      postId: p.id,
                    );
                  },
                ),
              ],
            ),
      bottom: LbmAsync<Post>(
        post,
        skeleton: const SizedBox.shrink(),
        errorBuilder: (_, _) => const SizedBox.shrink(),
        data: (post) => _CommentComposer(postId: post.id),
      ),
      child: LbmAsync<Post>(
        post,
        skeleton: const PostCardSkeleton(count: 1),
        onRetry: () => ref.invalidate(postProvider(postId)),
        data: (post) => switch (post) {
          // A listing's detail *is* the product page; there is no second
          // page about the same thing.
          final ListingPost listing => _RedirectToProduct(
            productId: listing.product.id,
          ),
          final ReviewPost review => _ReviewDetail(post: review),
          final CartPost cart => _CartPostDetail(post: cart),
          _ => ListView(
            padding: EdgeInsets.zero,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                child: PostCard(post),
              ),
              _Comments(postId: post.id),
              const SizedBox(height: 20),
            ],
          ),
        },
      ),
    );
  }
}

/// A listing post has no detail of its own: it is about a product, and the
/// product has a page. Rather than show a second, thinner version of it, the
/// screen replaces itself with the real one.
class _RedirectToProduct extends StatefulWidget {
  const _RedirectToProduct({required this.productId});

  final String productId;

  @override
  State<_RedirectToProduct> createState() => _RedirectToProductState();
}

class _RedirectToProductState extends State<_RedirectToProduct> {
  @override
  void initState() {
    super.initState();
    // After this frame: navigating during a build is an error, and the post
    // may still have been loading when the screen was first laid out.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.replaceWithProduct(widget.productId);
    });
  }

  @override
  Widget build(BuildContext context) => const ProductDetailSkeleton();
}

/// Somebody's review, on its own page.
///
/// The photograph first, then what they said, then the thing they are
/// talking about with a way to cart it: a review that cannot be acted on is
/// a paragraph, and the point of putting reviews in the feed is that they
/// sell things.
class _ReviewDetail extends ConsumerWidget {
  const _ReviewDetail({required this.post});

  final ReviewPost post;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final reviewer = ref.watch(personProvider(post.authorId)).value;
    final product = ref.watch(productProvider(post.productId)).value;
    final photo = post.imageUrls.firstOrNull ?? product?.imageUrls.firstOrNull;

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        DetailGallery(
          actions: [_MoreButton(post: post)],
          child: SizedBox(
            height: 300,
            child: ColoredBox(
              color: c.skyWash,
              child: photo == null || photo.isEmpty
                  ? (product == null
                        ? const SizedBox.expand()
                        : ProductArt(product))
                  : ProductPhoto(
                      url: photo,
                      fallback: ColoredBox(color: c.skyMist),
                    ),
            ),
          ),
        ),
        DetailBody(
          children: [
            DetailSheet(
              children: [
                if (reviewer != null)
                  Row(
                    children: [
                      Avatar(
                        reviewer,
                        onTap: () => context.goToSeller(reviewer.id),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              reviewer.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: LbmText.pinTitle.copyWith(
                                fontSize: 14,
                                color: c.ink,
                              ),
                            ),
                            Row(
                              children: [
                                if (post.purchaseId != null) ...[
                                  Icon(
                                    Icons.verified_rounded,
                                    size: 13,
                                    color: c.sage,
                                  ),
                                  const SizedBox(width: 4),
                                ],
                                Flexible(
                                  child: Text(
                                    // A review only exists for a line the
                                    // order pipeline recorded, so "bought it"
                                    // is a fact rather than a claim.
                                    post.purchaseId != null
                                        ? 'Bought it · ${post.age}'
                                        : post.age,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: LbmText.pinMeta.copyWith(
                                      color: c.ink2,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 12),
                Stars(post.rating.toDouble(), size: 18),
                const SizedBox(height: 10),
                Text(
                  '“${post.text}”',
                  style: LbmText.display.copyWith(
                    fontSize: 21,
                    height: 1.25,
                    color: c.ink,
                  ),
                ),
                if (post.tags.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  TagChips(post.tags, onTap: (tag) => context.goToTag(tag)),
                ],
                if (product != null) ...[
                  const SizedBox(height: 16),
                  _ReviewedProductRow(product: product),
                ],
              ],
            ),
            _MoreReviews(productId: post.productId, exceptId: post.id),
            _Comments(postId: post.id),
            const SizedBox(height: 24),
          ],
        ),
      ],
    );
  }
}

/// Report or block, floating on a full-bleed picture.
class _MoreButton extends ConsumerWidget {
  const _MoreButton({required this.post});

  final Post post;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final author = ref.watch(personProvider(post.authorId)).value;
    return FloatingCircleButton(
      icon: Icons.more_horiz_rounded,
      label: 'More',
      onTap: () => showMoreSheet(
        context,
        ref,
        subjectUid: post.authorId,
        subjectName: author?.name ?? '',
        subjectHandle: author?.handle ?? '@${post.authorId}',
        postId: post.id,
      ),
    );
  }
}

/// The thing being reviewed, with the way to cart it.
class _ReviewedProductRow extends StatelessWidget {
  const _ReviewedProductRow({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final c = context.c;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: c.skyWash,
        borderRadius: const BorderRadius.all(Radius.circular(16)),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.all(Radius.circular(12)),
            child: SizedBox(
              width: 52,
              height: 52,
              child: ProductArt(product, square: true),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => context.goToProduct(product.id),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    product.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: LbmText.pinTitle.copyWith(
                      fontSize: 13.5,
                      color: c.ink,
                    ),
                  ),
                  Text(
                    product.price,
                    style: LbmText.pinMeta.copyWith(color: c.ink2),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          CartPill(productId: product.id),
        ],
      ),
    );
  }
}

/// What else people said about the same thing.
class _MoreReviews extends ConsumerWidget {
  const _MoreReviews({required this.productId, required this.exceptId});

  final String productId;
  final String exceptId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reviews = ref.watch(reviewsProvider(productId)).value;
    if (reviews == null || reviews.length < 2) return const SizedBox.shrink();

    return DetailSection(
      title: 'More reviews of this',
      action: InlineLink(
        'See all',
        fontSize: 12.5,
        onTap: () => context.goToReviews(productId),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: LbmCard(
          child: RowStack(
            children: [
              for (final review in reviews.take(4))
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  child: ReviewRow(review),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Somebody's cart, posted, on its own page.
///
/// The items are the snapshot the post was made from, never the live
/// products: a post that quietly restocked itself would be a bug people
/// notice at once.
class _CartPostDetail extends ConsumerWidget {
  const _CartPostDetail({required this.post});

  final CartPost post;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final author = ref.watch(personProvider(post.authorId)).value;
    final total = post.items.fold<int>(0, (sum, i) => sum + i.priceCents);

    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 24),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              if (author != null) ...[
                Avatar(author, onTap: () => context.goToSeller(author.id)),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${author?.name ?? 'Someone'} posted their cart',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: LbmText.pinTitle.copyWith(
                        fontSize: 14,
                        color: c.ink,
                      ),
                    ),
                    Text(
                      // Said out loud, because a cart post looks live and is
                      // not: what is drawn is what was in it that day.
                      '${post.age} · a snapshot, it will not change',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: LbmText.pinMeta.copyWith(color: c.ink2),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (post.caption?.isNotEmpty ?? false) ...[
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: LbmRadius.cardR,
                boxShadow: c.shadowSoft,
              ),
              child: Text(
                post.caption!,
                style: LbmText.display.copyWith(
                  fontSize: 17,
                  height: 1.3,
                  color: c.ink,
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: PillButton(
            'Add all ${post.itemCount} · ${Fmt.money(total)}',
            icon: Icons.add_shopping_cart_rounded,
            onPressed: () => requireProfile(
              context,
              ref,
              () => addManyToCart(
                context,
                ref,
                [for (final line in post.items) line.productId],
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        LbmMasonry.fixed(
          children: [
            for (final line in post.items)
              _SnapshotPin(key: ValueKey('snap_${line.productId}'), line: line),
          ],
        ),
        const SizedBox(height: 8),
        _Comments(postId: post.id),
      ],
    );
  }
}

/// One frozen line of a posted cart.
///
/// Built from the snapshot rather than from the product, so it shows what
/// was in the cart at the time even if the listing has changed since.
class _SnapshotPin extends StatelessWidget {
  const _SnapshotPin({super.key, required this.line});

  final CartPostItem line;

  @override
  Widget build(BuildContext context) {
    final c = context.c;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => context.goToProduct(line.productId),
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
                    child: line.imageUrl == null || line.imageUrl!.isEmpty
                        ? Center(
                            child: Icon(Icons.image_outlined, color: c.ink3),
                          )
                        : ProductPhoto(
                            url: line.imageUrl!,
                            fallback: ColoredBox(color: c.skyMist),
                          ),
                  ),
                ),
              ),
              Positioned(
                right: 8,
                bottom: 8,
                child: CartPill(productId: line.productId),
              ),
            ],
          ),
          PinCaption(title: line.title, byline: line.price),
        ],
      ),
    );
  }
}

class _Comments extends ConsumerWidget {
  const _Comments({required this.postId});

  final String postId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final comments = ref.watch(commentsProvider(postId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHead('Comments'),
        LbmAsync<List<Comment>>(
          comments,
          skeleton: const ListRowSkeleton(rows: 2),
          isEmpty: (comments) => comments.isEmpty,
          empty: const LbmEmpty(
            title: 'No comments yet',
            body: 'Say something about this one.',
            compact: true,
          ),
          data: (comments) => LbmCard(
            margin: const EdgeInsets.symmetric(horizontal: 14),
            child: RowStack(
              children: [
                for (final comment in comments) _CommentRow(comment: comment),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// One comment, with the way to change your own.
///
/// The edit is inline rather than a sheet: the words being rewritten stay
/// where they are, under the name and the time, so it is never in doubt which
/// comment is being changed.
class _CommentRow extends ConsumerStatefulWidget {
  const _CommentRow({required this.comment});

  final Comment comment;

  @override
  ConsumerState<_CommentRow> createState() => _CommentRowState();
}

class _CommentRowState extends ConsumerState<_CommentRow> {
  /// Non-null only while this row is being rewritten.
  TextEditingController? _draft;
  bool _busy = false;

  bool get _editing => _draft != null;

  @override
  void dispose() {
    _draft?.dispose();
    super.dispose();
  }

  void _startEditing() {
    setState(() => _draft = TextEditingController(text: widget.comment.text));
  }

  void _cancel() {
    setState(() {
      _draft?.dispose();
      _draft = null;
    });
  }

  Future<void> _save() async {
    final draft = _draft;
    if (draft == null || _busy) return;
    final text = draft.text.trim();
    if (text.isEmpty || text == widget.comment.text) {
      _cancel();
      return;
    }

    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(socialRepositoryProvider)
          .editComment(
            postId: widget.comment.postId,
            commentId: widget.comment.id,
            text: text,
          );
      if (!mounted) return;
      _cancel();
    } on RepositoryException catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(describeError(error).body)),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final messenger = ScaffoldMessenger.of(context);
    final yes = await showLbmSheet<bool>(
      context,
      (sheetContext) => LbmSheet(
        children: [
          Text(
            'Delete this comment?',
            style: LbmText.display.copyWith(
              fontSize: 20,
              color: sheetContext.c.ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'It goes for everyone, and it cannot be brought back.',
            style: LbmText.tiny.copyWith(
              color: sheetContext.c.ink2,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          PillButton(
            'Delete it',
            onPressed: () => Navigator.of(sheetContext).pop(true),
          ),
          const SizedBox(height: 8),
          PillButton(
            'Keep it',
            style: PillStyle.ghost,
            onPressed: () => Navigator.of(sheetContext).pop(false),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    try {
      await ref
          .read(socialRepositoryProvider)
          .deleteComment(
            postId: widget.comment.postId,
            commentId: widget.comment.id,
          );
    } on RepositoryException catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text(describeError(error).body)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final comment = widget.comment;
    final author = ref.watch(personProvider(comment.authorId));
    final isMine = ref.watch(currentUidProvider) == comment.authorId;

    return Padding(
      // One level of nesting only; a reply to a reply flattens onto this level.
      padding: EdgeInsets.fromLTRB(16 + comment.depth * 26.0, 12, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LbmAsync<Person>(
            author,
            skeleton: const LbmSkeleton(width: 30, height: 30, radius: 15),
            errorBuilder: (_, _) =>
                const LbmSkeleton(width: 30, height: 30, radius: 15),
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
                LbmAsync<Person>(
                  author,
                  skeleton: const LbmSkeleton(width: 90, height: 12),
                  errorBuilder: (_, _) => const SizedBox.shrink(),
                  data: (person) => Row(
                    children: [
                      Flexible(
                        child: Text(
                          person.name,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: c.ink,
                          ),
                        ),
                      ),
                      const SizedBox(width: 7),
                      Flexible(
                        child: Text(
                          comment.isEdited
                              ? '${comment.age} · edited'
                              : comment.age,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: LbmText.xtiny.copyWith(color: c.ink2),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                if (_editing) ...[
                  LbmField(
                    controller: _draft,
                    maxLines: 4,
                    autofocus: true,
                    hintText: 'Your comment',
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      PillButton(
                        _busy ? 'Saving' : 'Save',
                        expand: false,
                        onPressed: _busy ? null : _save,
                      ),
                      const SizedBox(width: 8),
                      PillButton(
                        'Cancel',
                        style: PillStyle.ghost,
                        expand: false,
                        onPressed: _busy ? null : _cancel,
                      ),
                    ],
                  ),
                ] else ...[
                  Text(
                    comment.text,
                    style: TextStyle(
                      fontSize: 13.5,
                      height: 1.5,
                      color: c.ink2,
                    ),
                  ),
                  // Your own words are yours to change. On the row itself
                  // rather than behind a long press, which nobody finds
                  // (Grace's testers, 2026-09-23).
                  if (isMine)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Row(
                        children: [
                          InlineLink(
                            'Edit',
                            fontSize: 11.5,
                            onTap: _startEditing,
                          ),
                          const SizedBox(width: 14),
                          InlineLink('Delete', fontSize: 11.5, onTap: _delete),
                        ],
                      ),
                    ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          _CommentLike(comment: comment),
        ],
      ),
    );
  }
}

class _CommentLike extends ConsumerWidget {
  const _CommentLike({required this.comment});

  final Comment comment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkResponse(
          radius: 20,
          onTap: () => requireProfile(context, ref, () async {
            final messenger = ScaffoldMessenger.of(context);
            try {
              await ref
                  .read(socialRepositoryProvider)
                  .setCommentLike(
                    comment.postId,
                    comment.id,
                    !comment.likedByMe,
                  );
            } catch (error) {
              messenger.showSnackBar(
                SnackBar(content: Text(describeError(error).body)),
              );
            }
          }),
          child: Semantics(
            button: true,
            label: comment.likedByMe ? 'Unlike comment' : 'Like comment',
            child: Icon(
              comment.likedByMe
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
              size: 16,
              color: comment.likedByMe ? c.accentDeep : c.ink3,
            ),
          ),
        ),
        if (comment.likeCount > 0)
          Text(
            '${comment.likeCount}',
            style: LbmText.xtiny.copyWith(
              color: c.ink3,
              fontFeatures: kTabularFigures,
            ),
          ),
      ],
    );
  }
}

class _CommentComposer extends ConsumerWidget {
  const _CommentComposer({required this.postId});

  final String postId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isGuest = ref.watch(isGuestProvider);
    if (isGuest) return const SizedBox.shrink();

    return Composer(
      hintText: 'Add a comment',
      onSend: (text) => ref
          .read(socialRepositoryProvider)
          .addComment(postId: postId, text: text),
    );
  }
}
