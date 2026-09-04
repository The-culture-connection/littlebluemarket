import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/fixtures/fixture_data.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/primitives.dart';
import '../../widgets/screen.dart';

/// The list of user-created forums, revealed by pulling the chatroom down.
/// Anyone can start one.
class ForumsScreen extends StatelessWidget {
  const ForumsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.c;

    return LbmScreen(
      appBar: LbmAppBar(
        title: 'Forums',
        leading: CircleIconButton(
          icon: Icons.keyboard_arrow_up_rounded,
          iconSize: 22,
          tooltip: 'Back to chat',
          onPressed: () => context.canPop()
              ? context.pop()
              : context.go('/community'),
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
          for (final forum in Fx.forums)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: _ForumCard(forum: forum),
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

class _ForumCard extends StatelessWidget {
  const _ForumCard({required this.forum});

  final Forum forum;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return LbmCard(
      onTap: () => context.push('/community/forums/${forum.id}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Color(forum.tint),
                borderRadius: const BorderRadius.all(Radius.circular(16)),
              ),
              child: Text(
                forum.title.characters.first,
                style: const TextStyle(
                  fontFamily: kDisplayFont,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    forum.title,
                    style: LbmText.display.copyWith(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w600,
                      color: c.ink,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    forum.description,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.5,
                      color: c.ink2,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '${forum.membersLabel} · ${forum.threadCount} threads',
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
    );
  }
}
