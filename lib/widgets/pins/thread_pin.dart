import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../models/feed_item.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';

/// A forum question in the market grid.
///
/// The point of putting it here is that Community and Market stopped being
/// two apps: a thread shows up where people already are, with the best reply
/// under it so the pin says something rather than just advertising itself.
class ThreadPin extends StatelessWidget {
  const ThreadPin({super.key, required this.item, this.onTap});

  final ThreadItem item;

  /// Defaults to the thread's own screen in the Community tab.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final thread = item.thread;
    final reply = item.topReply;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap ?? () => context.go('/community/thread/${thread.id}'),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: LbmRadius.imageR,
          boxShadow: c.shadowSoft,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'FORUM · ${item.forumName ?? 'Community'}'.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: LbmText.pinMeta.copyWith(
                fontSize: 10.5,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
                color: c.sage,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              thread.title,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: LbmText.display.copyWith(
                fontSize: 17,
                height: 1.18,
                color: c.ink,
              ),
            ),
            if (reply != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.only(left: 8),
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(color: c.sageMist, width: 3),
                  ),
                ),
                child: Text(
                  reply.text,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: LbmText.pinMeta.copyWith(fontSize: 12, color: c.ink2),
                ),
              ),
            ],
            const SizedBox(height: 10),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 6,
              children: [
                if (item.repliers.isNotEmpty)
                  _Faces(item: item)
                else
                  const SizedBox.shrink(),
                Text(
                  '${thread.commentCount} '
                  '${thread.commentCount == 1 ? 'reply' : 'replies'}',
                  style: LbmText.pinMeta.copyWith(
                    fontWeight: FontWeight.w800,
                    color: c.ink2,
                  ),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: c.sageMist,
                    borderRadius: LbmRadius.pillR,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    child: Text(
                      item.joined ? 'Joined' : 'Join in',
                      style: LbmText.pinMeta.copyWith(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w900,
                        color: c.sage,
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

/// The overlapping faces of whoever is in the thread.
class _Faces extends StatelessWidget {
  const _Faces({required this.item});

  final ThreadItem item;

  @override
  Widget build(BuildContext context) {
    final people = item.repliers.take(3).toList();
    const overlap = 6.0;
    const size = 20.0;

    return SizedBox(
      width: size + (people.length - 1) * (size - overlap),
      height: size,
      child: Stack(
        children: [
          for (var i = 0; i < people.length; i++)
            Positioned(
              left: i * (size - overlap),
              child: Container(
                width: size,
                height: size,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Color(people[i].tint),
                  shape: BoxShape.circle,
                  border: Border.all(color: context.c.surface, width: 2),
                ),
                child: Text(
                  people[i].initials.characters.first,
                  style: LbmText.pinMeta.copyWith(
                    fontSize: 9,
                    height: 1,
                    fontWeight: FontWeight.w900,
                    color: LbmConst.onGradient,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
