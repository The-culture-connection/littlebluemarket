import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/feed_item.dart';
import '../../models/models.dart';
import '../../models/profile_activity.dart';
import '../../router/nav.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/async.dart';
import '../../widgets/following_grid.dart';
import '../../widgets/pins/cart_pin.dart';
import '../../widgets/pins/thread_pin.dart';
import '../../widgets/masonry.dart';
import '../../widgets/primitives.dart';
import '../../widgets/skeleton.dart';

/// The four profile sections that are about what somebody does rather than
/// what they sell: the reviews they wrote, the carts they shared, the threads
/// they started and the things they said.
///
/// Public widgets rather than private ones because your own profile and
/// somebody else's have to draw them identically. A control that says "this
/// is what they see" has to be checkable by looking.
///
/// Reviews and carts are also in Posts, which is everything: Posts is the
/// board, these two are the shelves.

/// Forum threads this person started.
class ProfileThreadsList extends ConsumerWidget {
  const ProfileThreadsList({super.key, required this.uid, this.own = false});

  final String uid;
  final bool own;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final threads = ref.watch(threadsByProvider(uid));

    return LbmAsync<List<ForumThread>>(
      threads,
      skeleton: const ListRowSkeleton(rows: 2),
      onRetry: () => ref.invalidate(threadsByProvider(uid)),
      isEmpty: (threads) => threads.isEmpty,
      empty: LbmEmpty(
        title: own ? 'You have not started a thread yet' : 'No threads yet',
        body: own ? 'Ask the community something and it lands here.' : null,
        compact: true,
      ),
      data: (threads) => LbmMasonry.fixed(
        children: [
          for (final thread in threads)
            ThreadPin(key: ValueKey(thread.id), item: ThreadItem(thread)),
        ],
      ),
    );
  }
}

/// What this person has said, in threads and under posts, newest first.
class ProfileCommentsList extends ConsumerWidget {
  const ProfileCommentsList({super.key, required this.uid, this.own = false});

  final String uid;
  final bool own;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final comments = ref.watch(commentsByProvider(uid));

    return LbmAsync<List<ProfileComment>>(
      comments,
      skeleton: const ListRowSkeleton(rows: 3),
      onRetry: () => ref.invalidate(commentsByProvider(uid)),
      isEmpty: (comments) => comments.isEmpty,
      empty: LbmEmpty(
        title: own ? 'You have not commented yet' : 'Nothing said yet',
        body: own ? 'Replies in the forums and under posts land here.' : null,
        compact: true,
      ),
      data: (comments) => Column(
        children: [
          for (final comment in comments)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: LbmCard(
                padding: EdgeInsets.zero,
                onTap: () => _open(context, comment),
                child: ListRow(
                  title: Text(
                    comment.text,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text('${comment.where} · ${comment.age}'),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// A comment's home, not the comment: there is no screen for one comment,
  /// and the thread it is in is what somebody tapping it wants to read.
  void _open(BuildContext context, ProfileComment comment) {
    switch (comment.place) {
      case CommentPlace.thread:
        context.go('/community/thread/${comment.parentId}');
      case CommentPlace.post:
        context.goToPost(comment.parentId);
    }
  }
}

/// Reviews this person wrote.
class ProfileReviewsList extends ConsumerWidget {
  const ProfileReviewsList({super.key, required this.uid, this.own = false});

  final String uid;
  final bool own;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final posts = ref.watch(postsByProvider(uid));

    return LbmAsync<List<Post>>(
      posts,
      skeleton: const ListRowSkeleton(rows: 2),
      onRetry: () => ref.invalidate(postsByProvider(uid)),
      isEmpty: (all) => all.whereType<ReviewPost>().isEmpty,
      empty: LbmEmpty(
        title: own
            ? 'You have not written a review yet'
            : 'No reviews written yet',
        body: own ? 'Reviews of what you bought land here.' : null,
        compact: true,
      ),
      data: (all) => Column(
        children: [
          for (final post in all.whereType<ReviewPost>())
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: LbmCard(
                padding: EdgeInsets.zero,
                onTap: () => context.goToPost(post.id),
                child: ListRow(
                  leading: Stars(post.rating.toDouble(), size: 12),
                  title: Text(
                    post.text,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(post.age),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Carts this person shared.
class ProfileCartsList extends ConsumerWidget {
  const ProfileCartsList({super.key, required this.uid, this.own = false});

  final String uid;
  final bool own;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final posts = ref.watch(postsByProvider(uid));

    return LbmAsync<List<Post>>(
      posts,
      skeleton: const GridSkeleton(count: 2),
      onRetry: () => ref.invalidate(postsByProvider(uid)),
      isEmpty: (all) => all.whereType<CartPost>().isEmpty,
      empty: LbmEmpty(
        title: own ? 'You have not shared a cart yet' : 'No carts shared yet',
        body: own ? 'Post a cart and it lands here.' : null,
        compact: true,
      ),
      data: (all) => LbmMasonry.fixed(
        children: [
          for (final post in all.whereType<CartPost>())
            CartPin.of(post, key: ValueKey(post.id)),
        ],
      ),
    );
  }
}

/// "Comments · hidden from others", on your own profile only.
///
/// The switch lives two screens away in Edit profile, so the profile has to
/// say which of its tabs nobody else can see. Without this the control is
/// invisible the moment you leave the screen that sets it.
class HiddenFromOthersNote extends StatelessWidget {
  const HiddenFromOthersNote({super.key, required this.onEdit});

  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        children: [
          Icon(Icons.visibility_off_outlined, size: 16, color: c.ink3),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '(hidden from others)',
              style: LbmText.xtiny.copyWith(color: c.ink2),
            ),
          ),
          TextButton(onPressed: onEdit, child: const Text('Edit what shows')),
        ],
      ),
    );
  }
}

/// Everything this person posted, as the pins the feed draws.
///
/// The public view's Posts tab. Your own profile keeps its tighter grid of
/// product tiles: on your own board you are scanning for one thing you put
/// up, and a column of full pins is a slower way to find it.
class ProfilePostsGrid extends ConsumerWidget {
  const ProfilePostsGrid({super.key, required this.uid});

  final String uid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final posts = ref.watch(postsByProvider(uid));

    return LbmAsync<List<Post>>(
      posts,
      skeleton: const GridSkeleton(count: 4),
      onRetry: () => ref.invalidate(postsByProvider(uid)),
      isEmpty: (all) => all.isEmpty,
      empty: const LbmEmpty(title: 'Nothing posted yet', compact: true),
      data: (all) => LbmMasonry.fixed(
        children: [for (final post in all) ?FollowingGrid.pinFor(post)],
      ),
    );
  }
}
