import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/donation_nudge.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';

/// The chip-in nudge, in the grid.
///
/// Its own pin rather than a case in [NudgePin] because it is the only one
/// that carries a figure, and that figure has to be read rather than
/// written: the line says "212 people chipped in this month" only when
/// `funding/{month}` says 212, and says something true without a number when
/// there is no document.
///
/// Sage, not orchid. Orchid is the cart in this design, and being asked for
/// money is not shopping.
class DonationNudgePin extends ConsumerWidget {
  const DonationNudgePin({super.key, this.onTap, this.onDismiss});

  final VoidCallback? onTap;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    // `.value` and not a gate: a nudge that shows a skeleton while it waits
    // for a funding document would be a loading state in the middle of
    // somebody's feed. No number is a fine answer.
    final donors = ref.watch(fundingThisMonthProvider).value?.donors;
    final line = donationNudgeLine(DateTime.now(), donors);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 14),
        decoration: BoxDecoration(
          color: c.sageMist,
          borderRadius: LbmRadius.cardR,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Drawn, never typeset: the bundled faces carry no emoji and
                // the mockup's 🌱 came out as an empty box the first time.
                Icon(Icons.eco_rounded, size: 20, color: c.sage),
                const Spacer(),
                if (onDismiss != null)
                  Semantics(
                    button: true,
                    label: 'Hide this',
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: onDismiss,
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(Icons.close_rounded, size: 16, color: c.ink3),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Member-run',
              style: LbmText.display.copyWith(fontSize: 17, color: c.ink),
            ),
            const SizedBox(height: 5),
            Text(
              line,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: LbmText.pinMeta.copyWith(
                fontSize: 12.5,
                color: c.ink2,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 11),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: LbmRadius.pillR,
                border: Border.all(color: c.sage, width: 1.2),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Chip in',
                    style: LbmText.pinMeta.copyWith(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w900,
                      color: c.ink,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.arrow_forward_rounded, size: 13, color: c.ink),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
