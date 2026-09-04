import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/fixtures.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/primitives.dart';
import '../../widgets/screen.dart';

/// Threads inside one forum: a vote column, the title, the author and a
/// comment count.
class ForumScreen extends StatelessWidget {
  const ForumScreen({super.key, required this.forumId});

  final String forumId;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final forum = Fx.forum(forumId);
    final threads = Fx.threadsIn(forum.id);

    return LbmScreen(
      appBar: LbmAppBar(
        title: forum.title,
        actions: [
          PillButton(
            'Join',
            small: true,
            expand: false,
            style: PillStyle.quiet,
            onPressed: () {},
          ),
        ],
      ),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  forum.description,
                  style: TextStyle(fontSize: 13, height: 1.5, color: c.ink2),
                ),
                const SizedBox(height: 6),
                Text(
                  '${forum.members} · ${forum.threadCount} threads',
                  style: LbmText.xtiny.copyWith(
                    color: c.ink2,
                    fontFeatures: kTabularFigures,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          for (final thread in threads)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: _ThreadCard(thread: thread),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 26),
            child: PillButton(
              'New thread',
              icon: Icons.add_rounded,
              style: PillStyle.ghost,
              onPressed: () {},
            ),
          ),
        ],
      ),
    );
  }
}

class _ThreadCard extends StatelessWidget {
  const _ThreadCard({required this.thread});

  final ForumThread thread;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final author = Fx.person(thread.authorId);

    return LbmCard(
      onTap: () => context.push('/community/thread/${thread.id}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _VoteColumn(upvotes: thread.upvotes),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    thread.title,
                    style: LbmText.display.copyWith(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w600,
                      height: 1.32,
                      color: c.ink,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '${author.handle} · ${thread.age} · '
                    '${thread.commentCount} comments',
                    style: LbmText.xtiny.copyWith(color: c.ink2),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VoteColumn extends StatelessWidget {
  const _VoteColumn({required this.upvotes});

  final int upvotes;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.keyboard_arrow_up_rounded, size: 18, color: c.ink3),
          Text(
            '$upvotes',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: c.ink,
              fontFeatures: kTabularFigures,
            ),
          ),
          Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: c.ink3),
        ],
      ),
    );
  }
}
