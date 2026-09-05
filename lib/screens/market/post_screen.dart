import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/models.dart';
import '../../router/nav.dart';
import '../../state/providers.dart';
import '../../state/session.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/async.dart';
import '../../widgets/post_card.dart';
import '../../widgets/primitives.dart';
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
        data: (post) => ListView(
          padding: EdgeInsets.zero,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: PostCard(post),
            ),
            if (post.subjectProductId case final productId?) ...[
              _ProductLink(productId: productId),
              _ReviewsSection(productId: productId),
            ],
            _Comments(postId: post.id),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

/// The way from a post into the full listing.
class _ProductLink extends ConsumerWidget {
  const _ProductLink({required this.productId});

  final String productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    return LbmCard(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      padding: EdgeInsets.zero,
      child: ListRow(
        title: const Text('Product details'),
        subtitle: const Text('Options, materials, shipping, returns'),
        trailing: Icon(Icons.chevron_right_rounded, color: c.ink3, size: 22),
        onTap: () => context.goToProduct(productId),
      ),
    );
  }
}

class _ReviewsSection extends ConsumerWidget {
  const _ReviewsSection({required this.productId});

  final String productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final reviews = ref.watch(reviewsProvider(productId));
    final rating = ref.watch(ratingProvider(productId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHead(
          'Reviews of this product',
          trailing: InlineLink(
            'See all',
            onTap: () => context.goToReviews(productId),
          ),
        ),
        LbmAsync<RatingSummary>(
          rating,
          skeleton: const Padding(
            padding: EdgeInsets.fromLTRB(18, 0, 18, 8),
            child: LbmSkeleton(width: 200, height: 14),
          ),
          errorBuilder: (_, _) => const SizedBox.shrink(),
          data: (rating) => Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
            child: rating.isEmpty
                ? Text(
                    'No ratings yet',
                    style: LbmText.tiny.copyWith(color: c.ink2),
                  )
                : Row(
                    children: [
                      Stars(rating.average, size: 14),
                      const SizedBox(width: 10),
                      Text(
                        rating.average.toStringAsFixed(1),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: c.ink,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'from ${Fmt.count(rating.total)} verified buyers',
                          style: LbmText.tiny.copyWith(color: c.ink2),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
        LbmAsync<List<Review>>(
          reviews,
          skeleton: const ListRowSkeleton(rows: 2),
          isEmpty: (reviews) => reviews.isEmpty,
          empty: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14),
            child: LbmCard(
              child: LbmEmpty(
                title: 'No reviews yet',
                body: 'Be the first after you buy.',
                compact: true,
              ),
            ),
          ),
          data: (reviews) => Column(
            children: [
              LbmCard(
                margin: const EdgeInsets.symmetric(horizontal: 14),
                child: RowStack(
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
        ),
      ],
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

class _CommentRow extends ConsumerWidget {
  const _CommentRow({required this.comment});

  final Comment comment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final author = ref.watch(personProvider(comment.authorId));

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
                      Text(
                        comment.age,
                        style: LbmText.xtiny.copyWith(color: c.ink2),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  comment.text,
                  style: TextStyle(fontSize: 13.5, height: 1.5, color: c.ink2),
                ),
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
          onTap: () => requireProfile(context, ref, () {
            ref
                .read(socialRepositoryProvider)
                .setCommentLike(comment.id, !comment.likedByMe);
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
