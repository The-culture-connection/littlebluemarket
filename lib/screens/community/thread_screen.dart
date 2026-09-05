import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/models.dart';
import '../../router/nav.dart';
import '../../state/providers.dart';
import '../../state/session.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/async.dart';
import '../../widgets/primitives.dart';
import '../../widgets/screen.dart';
import '../../widgets/skeleton.dart';

/// The original post, then its comments with one level of nesting.
///
/// Every avatar taps through to that person's feed.
class ThreadScreen extends ConsumerWidget {
  const ThreadScreen({super.key, required this.threadId});

  final String threadId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final thread = ref.watch(threadProvider(threadId));
    final isGuest = ref.watch(isGuestProvider);

    return LbmScreen(
      appBar: LbmAppBar(title: thread.value?.title ?? 'Thread'),
      bottom: isGuest
          ? null
          : Composer(
              hintText: 'Add a comment…',
              onSend: (text) => ref
                  .read(socialRepositoryProvider)
                  .addThreadComment(threadId: threadId, text: text),
            ),
      child: LbmAsync<ForumThread>(
        thread,
        skeleton: const ListRowSkeleton(rows: 2),
        onRetry: () => ref.invalidate(threadProvider(threadId)),
        data: (thread) => ListView(
          padding: EdgeInsets.zero,
          children: [
            _ThreadHead(thread: thread),
            const SectionHead(
              "Comments — tap any avatar for that person's feed",
            ),
            _Comments(threadId: threadId),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

class _ThreadHead extends ConsumerWidget {
  const _ThreadHead({required this.thread});

  final ForumThread thread;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final author = ref.watch(personProvider(thread.authorId));

    return LbmCard(
      margin: const EdgeInsets.symmetric(horizontal: 14),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LbmAsync<Person>(
            author,
            skeleton: const ListRowSkeleton(rows: 1),
            errorBuilder: (_, _) => const SizedBox.shrink(),
            data: (author) => Row(
              children: [
                Avatar(
                  author,
                  size: AvatarSize.sm,
                  onTap: () => context.goToSeller(author.id),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text.rich(
                        TextSpan(
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: c.ink,
                          ),
                          children: [
                            TextSpan(text: '${author.name} '),
                            TextSpan(
                              text: author.handle,
                              style: TextStyle(
                                fontWeight: FontWeight.w500,
                                color: c.ink2,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '${thread.age} ago',
                        style: LbmText.xtiny.copyWith(
                          color: c.ink2,
                          fontFeatures: kTabularFigures,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            thread.title,
            style: LbmText.display.copyWith(
              fontSize: 20,
              height: 1.24,
              color: c.ink,
            ),
          ),
          const SizedBox(height: 9),
          HashtagText(
            thread.body,
            tagColor: c.skyDeep,
            style: TextStyle(fontSize: 14, height: 1.6, color: c.ink2),
            onTagTap: (tag) => context.goToResults(tag),
          ),
          const SizedBox(height: 13),
          Text(
            '${Fmt.count(thread.commentCount)} comments',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: c.ink3,
              fontFeatures: kTabularFigures,
            ),
          ),
        ],
      ),
    );
  }
}

class _Comments extends ConsumerWidget {
  const _Comments({required this.threadId});

  final String threadId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final comments = ref.watch(threadCommentsProvider(threadId));

    return LbmAsync<List<ThreadComment>>(
      comments,
      skeleton: const ListRowSkeleton(rows: 3),
      // Comments belong to their thread now. The prototype rendered one global
      // list under every thread in the app.
      isEmpty: (comments) => comments.isEmpty,
      empty: const LbmEmpty(
        title: 'No comments yet',
        body: 'Be the first to answer.',
        compact: true,
      ),
      data: (comments) => LbmCard(
        margin: const EdgeInsets.symmetric(horizontal: 14),
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          children: [
            for (final comment in comments) _Comment(comment: comment),
          ],
        ),
      ),
    );
  }
}

class _Comment extends ConsumerWidget {
  const _Comment({required this.comment});

  final ThreadComment comment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final author = ref.watch(personProvider(comment.authorId));
    final nested = comment.depth > 0;

    return Container(
      margin: nested
          ? const EdgeInsets.fromLTRB(30, 4, 12, 8)
          : EdgeInsets.zero,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        color: nested ? c.skyWash : null,
        borderRadius: nested
            ? const BorderRadius.all(Radius.circular(16))
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LbmAsync<Person>(
            author,
            skeleton: const LbmSkeleton(width: 28, height: 28, radius: 14),
            errorBuilder: (_, _) =>
                const LbmSkeleton(width: 28, height: 28, radius: 14),
            data: (author) => Avatar(
              author,
              size: AvatarSize.xs,
              onTap: () => context.goToSeller(author.id),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LbmAsync<Person>(
                  author,
                  skeleton: const LbmSkeleton(width: 120, height: 11),
                  errorBuilder: (_, _) => const SizedBox.shrink(),
                  data: (author) => Text.rich(
                    TextSpan(
                      style: LbmText.xtiny.copyWith(color: c.ink2),
                      children: [
                        TextSpan(
                          text: author.handle,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: c.ink,
                          ),
                        ),
                        TextSpan(
                          text: ' · ${comment.age}',
                          style: const TextStyle(fontFeatures: kTabularFigures),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  comment.text,
                  style: TextStyle(fontSize: 13.5, height: 1.5, color: c.ink),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
