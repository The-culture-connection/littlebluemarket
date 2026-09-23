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
import '../../widgets/post_card.dart';
import '../../widgets/primitives.dart';
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

    return LbmScreen(
      appBar: LbmAppBar(
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
