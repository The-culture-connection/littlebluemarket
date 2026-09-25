import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/feed_item.dart';
import '../../models/models.dart';
import '../../router/nav.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../primitives.dart';

/// Somebody naming a maker they want other people to find.
///
/// Type on a blue gradient rather than a photograph, because a shoutout has
/// no picture of its own and a white card full of words is the flatness this
/// grid exists to break up.
class ShoutoutPin extends ConsumerWidget {
  const ShoutoutPin({super.key, required this.item});

  ShoutoutPin.of(ShoutoutPost post, {Key? key})
    : this(key: key, item: ShoutoutItem(post));

  final ShoutoutItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final post = item.post;
    final author = ref.watch(personProvider(post.authorId)).value;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => post.aboutSellerId != null
          ? context.goToSeller(post.aboutSellerId!)
          : context.goToPost(post.id),
      child: Container(
        constraints: const BoxConstraints(minHeight: 170),
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
        decoration: BoxDecoration(
          borderRadius: LbmRadius.imageR,
          gradient: LinearGradient(
            begin: const Alignment(-0.6, -0.8),
            end: const Alignment(0.6, 0.8),
            colors: c.shoutoutGradient,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            const _Kicker('Shoutout'),
            const SizedBox(height: 6),
            Text(
              post.text,
              maxLines: 5,
              overflow: TextOverflow.ellipsis,
              style: LbmText.display.copyWith(
                fontSize: 17,
                height: 1.2,
                color: LbmConst.onGradient,
              ),
            ),
            const SizedBox(height: 10),
            if (author != null)
              Row(
                children: [
                  Avatar(author, size: AvatarSize.xs),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'by ${author.name}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: LbmText.pinMeta.copyWith(
                        color: LbmConst.onGradient,
                        fontWeight: FontWeight.w800,
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

/// The small uppercase label at the top of a gradient pin.
class _Kicker extends StatelessWidget {
  const _Kicker(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: LbmText.pinMeta.copyWith(
        fontSize: 10.5,
        fontWeight: FontWeight.w900,
        letterSpacing: 1.3,
        color: LbmConst.onGradient.withValues(alpha: 0.85),
      ),
    );
  }
}
