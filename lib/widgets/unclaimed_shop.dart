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
/// It used to say so in a card with four lines of explanation and a button,
/// which on a shell profile was the largest thing on the screen and pushed
/// the products below the fold. Grace, the same day: "I want it to not be
/// so large and I want it to only let others know that this seller is not
/// active on the app... maybe make it a small badge of some kind that is
/// clickable."
///
/// So the fact is a badge and the explanation is a tap. Nothing was cut:
/// every word of the old card is in [showUnclaimedShopSheet], including the
/// two things that matter to a buyer, that the products are real and that a
/// message is kept.
class UnclaimedShopBadge extends ConsumerWidget {
  const UnclaimedShopBadge({
    super.key,
    required this.person,
    this.offerClaim = true,
  });

  final Person person;

  /// Whether the sheet offers the way in for the person who owns the shop.
  /// True on the shop's own profile, false on a listing, where the shop is
  /// not the subject of the screen.
  final bool offerClaim;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!person.unclaimed) return const SizedBox.shrink();
    return LbmChip(
      'Not active on the app yet',
      fontSize: 11.5,
      // A question mark rather than an exclamation: this is something to
      // know about the shop, not a warning about it.
      trailingIcon: Icons.help_outline_rounded,
      onTap: () => showUnclaimedShopSheet(
        context,
        ref,
        person: person,
        offerClaim: offerClaim,
      ),
    );
  }
}

/// What the badge says when it is tapped: the whole explanation, once.
Future<void> showUnclaimedShopSheet(
  BuildContext context,
  WidgetRef ref, {
  required Person person,
  bool offerClaim = true,
}) {
  return showLbmSheet(context, (sheetContext) {
    final c = sheetContext.c;
    return LbmSheet(
      children: [
        Row(
          children: [
            Icon(Icons.storefront_outlined, size: 20, color: c.ink3),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                'Not active on the app yet',
                style: LbmText.display.copyWith(fontSize: 19, color: c.ink),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          '${person.name} sells on Little Blue Market, but nobody has signed '
          'up for the shop on the app yet.',
          style: LbmText.tiny.copyWith(color: c.ink2, height: 1.55),
        ),
        const SizedBox(height: 10),
        // The two facts a buyer actually needs, and the reason this is worth
        // a sheet rather than a tooltip.
        Text(
          'Everything here is real and you can buy it as normal. A message '
          'will wait for them until they sign up.',
          style: LbmText.tiny.copyWith(color: c.ink2, height: 1.55),
        ),
        if (offerClaim) ...[
          const SizedBox(height: 16),
          // The way in, for the person who owns it. The claim itself is the
          // shop's own verified email; this is only the door.
          PillButton(
            'Is this your shop?',
            style: PillStyle.ghost,
            onPressed: () {
              Navigator.of(sheetContext).pop();
              // The shop travels with them, so a refusal can name it.
              // Nothing is granted on the strength of it; the Shipturtle
              // roster match is still the only thing that connects a shop.
              final shop = Uri.encodeQueryComponent(person.name);
              requireProfile(
                context,
                ref,
                () => context.push('/you/claim-shop?shop=$shop'),
              );
            },
          ),
        ],
      ],
    );
  });
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
