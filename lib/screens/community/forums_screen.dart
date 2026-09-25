import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/models.dart';
import '../../state/providers.dart';
import '../../widgets/async.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/masonry.dart';
import '../../widgets/primitives.dart';
import '../../widgets/screen.dart';
import '../../widgets/skeleton.dart';

/// The list of user-created forums, revealed by pulling the chatroom down.
/// Anyone can start one.
class ForumsScreen extends ConsumerWidget {
  const ForumsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final forums = ref.watch(forumsProvider);

    return LbmScreen(
      appBar: LbmAppBar(
        title: 'Forums',
        leading: CircleIconButton(
          icon: Icons.keyboard_arrow_up_rounded,
          iconSize: 22,
          tooltip: 'Back to chat',
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/community'),
        ),
        actions: [
          CircleIconButton(
            icon: Icons.add_rounded,
            tooltip: 'New forum',
            onPressed: () => context.push('/community/new-forum'),
          ),
        ],
      ),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
            child: Text(
              'Pulled down from the open chat. Swipe back up to return.',
              style: LbmText.xtiny.copyWith(color: c.ink2),
            ),
          ),
          LbmAsync<List<Forum>>(
            forums,
            skeleton: const ListRowSkeleton(rows: 3),
            onRetry: () => ref.invalidate(forumsProvider),
            isEmpty: (forums) => forums.isEmpty,
            empty: const LbmEmpty(
              title: 'No forums yet',
              body: 'Start the first one.',
            ),
            data: (forums) => LbmMasonry.fixed(
              children: [
                for (final forum in forums)
                  _ForumCard(key: ValueKey(forum.id), forum: forum),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 26),
            child: PillButton(
              'Start a forum',
              icon: Icons.add_rounded,
              style: PillStyle.ghost,
              onPressed: () => context.push('/community/new-forum'),
            ),
          ),
        ],
      ),
    );
  }
}

/// One forum, as a tile in the same grid the Market uses.
///
/// A gradient rather than a photograph, because a forum has no picture: its
/// own tint at two depths, so the wall of tiles is varied without anybody
/// having to choose a colour when they start one.
class _ForumCard extends ConsumerWidget {
  const _ForumCard({super.key, required this.forum});

  final Forum forum;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    const white = LbmConst.onGradient;
    final joined = ref.watch(forumMembershipProvider(forum.id)).value ?? false;
    final tint = Color(forum.tint);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => context.push('/community/forums/${forum.id}'),
      child: Container(
        constraints: const BoxConstraints(minHeight: 160),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: LbmRadius.imageR,
          gradient: LinearGradient(
            begin: const Alignment(-0.6, -0.8),
            end: const Alignment(0.6, 0.8),
            colors: [tint, Color.lerp(tint, c.ink, 0.45)!],
          ),
          boxShadow: c.shadowSoft,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'FORUM',
              style: LbmText.pinMeta.copyWith(
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.3,
                color: white.withValues(alpha: 0.8),
              ),
            ),
            const SizedBox(height: 5),
            Text(
              forum.title,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: LbmText.display.copyWith(
                fontSize: 17,
                height: 1.15,
                color: white,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              forum.description,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: LbmText.pinMeta.copyWith(
                color: white.withValues(alpha: 0.9),
              ),
            ),
            const SizedBox(height: 9),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 6,
              children: [
                Text(
                  '${forum.membersLabel} · ${forum.threadCount} threads',
                  style: LbmText.pinMeta.copyWith(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: white.withValues(alpha: 0.85),
                  ),
                ),
                if (joined)
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: white.withValues(alpha: 0.22),
                      borderRadius: LbmRadius.pillR,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      child: Text(
                        'Joined',
                        style: LbmText.pinMeta.copyWith(
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          color: white,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
