import 'package:flutter/material.dart';

import '../../data/fixtures.dart';
import '../../models/models.dart';
import '../../router/nav.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/primitives.dart';
import '../../widgets/screen.dart';

/// The original post, then its comments with one level of nesting.
///
/// Every avatar taps through to that person's feed.
class ThreadScreen extends StatelessWidget {
  const ThreadScreen({super.key, required this.threadId});

  final String threadId;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final thread = Fx.thread(threadId);
    final forum = Fx.forum(thread.forumId);
    final author = Fx.person(thread.authorId);

    return LbmScreen(
      appBar: LbmAppBar(title: forum.title),
      bottom: const Composer(hintText: 'Add a comment…'),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          LbmCard(
            margin: const EdgeInsets.symmetric(horizontal: 14),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
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
                ),
                const SizedBox(height: 13),
                // A wrap rather than a row: at a large text size these four
                // actions do not fit on one line, and reflowing beats clipping.
                Wrap(
                  spacing: 16,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.keyboard_arrow_up_rounded,
                          size: 17,
                          color: c.ink3,
                        ),
                        Text(' ${thread.upvotes} ', style: _metaStyle(c)),
                        Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 17,
                          color: c.ink3,
                        ),
                      ],
                    ),
                    Text(
                      '${thread.commentCount} comments',
                      style: _metaStyle(c),
                    ),
                    Text('Share', style: _metaStyle(c)),
                    Text('Save', style: _metaStyle(c)),
                  ],
                ),
              ],
            ),
          ),
          const SectionHead("Comments — tap any avatar for that person's feed"),
          LbmCard(
            margin: const EdgeInsets.symmetric(horizontal: 14),
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                for (final comment in Fx.comments)
                  _Comment(comment: comment),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  static TextStyle _metaStyle(LbmColors c) => TextStyle(
    fontSize: 12.5,
    fontWeight: FontWeight.w800,
    color: c.ink3,
    fontFeatures: kTabularFigures,
  );
}

class _Comment extends StatelessWidget {
  const _Comment({required this.comment});

  final ThreadComment comment;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final author = Fx.person(comment.authorId);
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
          Avatar(
            author,
            size: AvatarSize.xs,
            onTap: () => context.goToSeller(author.id),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
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
                        style: const TextStyle(
                          fontFeatures: kTabularFigures,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  comment.text,
                  style: TextStyle(fontSize: 13.5, height: 1.5, color: c.ink),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      Icons.keyboard_arrow_up_rounded,
                      size: 15,
                      color: c.ink3,
                    ),
                    Text(
                      ' ${comment.upvotes}',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: c.ink3,
                        fontFeatures: kTabularFigures,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Text(
                      'Reply',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: c.ink3,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
