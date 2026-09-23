import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/models.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'primitives.dart';
import 'sheets.dart';

/// The note on a shop that is on the market but has not been signed up for.
///
/// Every vendor the catalogue carries has a profile, so its listings have a
/// shop behind them and it can be found, opened and messaged (Grace,
/// 2026-09-24). What it does not have is anybody reading. Saying so is the
/// whole point: a message into silence is worse than a message you were
/// told might wait.
///
/// Two shapes, because two places need it and they need different lengths:
/// [UnclaimedShopCard] on the profile and the listing, [UnclaimedShopStrip]
/// above a message thread.
class UnclaimedShopCard extends ConsumerWidget {
  const UnclaimedShopCard({super.key, required this.person, this.compact = false});

  final Person person;

  /// The shorter wording, for the "Sold by" strip on a listing where the
  /// shop is not the subject of the screen.
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    if (!person.unclaimed) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      child: Container(
        padding: const EdgeInsets.fromLTRB(15, 13, 15, 13),
        decoration: BoxDecoration(
          color: c.skyMist,
          borderRadius: LbmRadius.cardR,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.storefront_outlined, size: 18, color: c.ink3),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Not on the app yet',
                    style: LbmText.tiny.copyWith(
                      fontWeight: FontWeight.w800,
                      color: c.ink,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              compact
                  ? 'You can buy from them as normal. A message will wait '
                        'until they sign up.'
                  : '${person.name} sells on Little Blue Market, but nobody '
                        'has signed up for the shop yet. Everything here is '
                        'real and you can buy it as normal. A message will '
                        'wait for them until they do.',
              style: LbmText.xtiny.copyWith(color: c.ink2, height: 1.55),
            ),
            // The way in, for the person who owns it. The claim itself is
            // the shop's own verified email; this is only the door.
            if (!compact) ...[
              const SizedBox(height: 12),
              PillButton(
                'Is this your shop?',
                style: PillStyle.ghost,
                small: true,
                onPressed: () => requireProfile(
                  context,
                  ref,
                  () => context.push('/you/claim-shop'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The same fact, one line, above a message thread.
class UnclaimedShopStrip extends StatelessWidget {
  const UnclaimedShopStrip({super.key, required this.person});

  final Person person;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    if (!person.unclaimed) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      color: c.skyMist,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.schedule_rounded, size: 16, color: c.ink3),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${person.name} has not claimed their shop on the app yet, so '
              'nobody is reading this thread. What you write is kept, and '
              'reaches them when they sign up.',
              style: LbmText.xtiny.copyWith(color: c.ink2, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}
