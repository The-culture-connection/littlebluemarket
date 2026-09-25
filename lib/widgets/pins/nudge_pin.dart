import 'package:flutter/material.dart';

import '../../models/feed_item.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';

/// A small prompt to do the one thing that would help this person now.
///
/// Every nudge is dismissible and every nudge stays gone for a week. The rule
/// that keeps it from being nagging lives in the feed's assembly, not here:
/// at most one per eight items, never two in a row.
class NudgePin extends StatelessWidget {
  const NudgePin({super.key, required this.item, this.onTap, this.onDismiss});

  final NudgeItem item;
  final VoidCallback? onTap;
  final VoidCallback? onDismiss;

  /// What each nudge says. Copy lives here so the feed can stay about
  /// assembly and the wording is in one place to change.
  ///
  /// The mark is an [IconData], never an emoji. The mockup draws these as
  /// emoji, but the app's own rule is that a glyph the bundled faces do not
  /// carry gets drawn rather than typeset, and emoji fall under it: they came
  /// out as empty boxes the first time these pins were rendered.
  static ({IconData icon, String title, String body, String cta}) copyFor(
    NudgeKind kind,
  ) => switch (kind) {
    NudgeKind.reviewDelivered => (
      icon: Icons.star_rounded,
      title: 'How was it?',
      body: 'Something you bought arrived. A star on its own counts.',
      cta: 'Rate it',
    ),
    NudgeKind.sayHi => (
      icon: Icons.waving_hand_rounded,
      title: 'Say hello',
      body: 'The open chat is where people find each other. New faces welcome.',
      cta: 'Jump in',
    ),
    NudgeKind.forumActivity => (
      icon: Icons.forum_rounded,
      title: 'People are talking',
      body: 'A forum you joined has moved on without you.',
      cta: 'Catch up',
    ),
  };

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final copy = copyFor(item.nudge);

    // Tinted by kind so two nudges never look like the same card twice.
    final (Color fill, Color ctaFill, Color ctaInk) = switch (item.nudge) {
      NudgeKind.reviewDelivered => (c.surface, c.accentMist, c.accentText),
      NudgeKind.sayHi => (c.sageMist, c.sage, c.surface),
      NudgeKind.forumActivity => (c.skyMist, c.skyWash, c.skyDeep),
    };

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 140),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: LbmRadius.imageR,
          boxShadow: c.shadowSoft,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: c.skyWash,
                    borderRadius: const BorderRadius.all(Radius.circular(14)),
                  ),
                  child: Icon(copy.icon, size: 22, color: c.ink2),
                ),
                const Spacer(),
                if (onDismiss != null)
                  GestureDetector(
                    onTap: onDismiss,
                    behavior: HitTestBehavior.opaque,
                    child: Semantics(
                      button: true,
                      label: 'Dismiss',
                      child: Icon(Icons.close_rounded, size: 18, color: c.ink3),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              copy.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: LbmText.display.copyWith(
                fontSize: 16,
                height: 1.15,
                color: c.ink,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              copy.body,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: LbmText.pinMeta.copyWith(fontSize: 12, color: c.ink2),
            ),
            const SizedBox(height: 10),
            DecoratedBox(
              decoration: BoxDecoration(
                color: ctaFill,
                borderRadius: LbmRadius.pillR,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 6,
                ),
                child: Text(
                  copy.cta,
                  style: LbmText.pinMeta.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: ctaInk,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
