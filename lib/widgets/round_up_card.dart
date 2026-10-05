import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/formatting.dart';
import '../state/providers.dart';
import '../state/round_up.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/primitives.dart';

/// "Round up for Little Blue Market", above the totals.
///
/// Off unless somebody turns it on, and shown as its own line in the totals
/// every time: an opt-in that defaults to on is not an opt-in, and change
/// taken quietly is the thing people are right to resent about this pattern.
///
/// Hides itself entirely when the round-up product is not configured for
/// this environment, which is how the whole feature ships dark.
class RoundUpCard extends ConsumerWidget {
  const RoundUpCard({super.key, required this.subtotalCents});

  final int subtotalCents;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final canRoundUp = ref.watch(appConfigProvider).value?.canRoundUp ?? false;
    if (!canRoundUp || subtotalCents <= 0) return const SizedBox.shrink();

    final on = ref.watch(roundUpProvider);
    final cents = roundUpCentsFor(subtotalCents);

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
      child: LbmCard(
        padding: const EdgeInsets.fromLTRB(16, 6, 10, 6),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Round up for Little Blue Market',
                    style: LbmText.pinTitle.copyWith(
                      fontSize: 14,
                      color: c.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    on
                        ? '${Fmt.money(cents)} keeps the app member-run.'
                        : 'Round up to the nearest dollar. The change keeps '
                              'the app running.',
                    style: LbmText.pinMeta.copyWith(color: c.ink2),
                  ),
                ],
              ),
            ),
            Switch(
              value: on,
              activeThumbColor: c.sage,
              onChanged: (next) => ref.read(roundUpProvider.notifier).set(next),
            ),
          ],
        ),
      ),
    );
  }
}

/// The round-up's own line in the totals, when it is on.
class RoundUpLine extends ConsumerWidget {
  const RoundUpLine({super.key, required this.subtotalCents});

  final int subtotalCents;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final canRoundUp = ref.watch(appConfigProvider).value?.canRoundUp ?? false;
    if (!canRoundUp || !ref.watch(roundUpProvider) || subtotalCents <= 0) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Round-up',
              style: TextStyle(fontSize: 14, color: c.ink2),
            ),
          ),
          Text(
            Fmt.money(roundUpCentsFor(subtotalCents)),
            style: TextStyle(
              fontSize: 14,
              color: c.sage,
              fontWeight: FontWeight.w800,
              fontFeatures: kTabularFigures,
            ),
          ),
        ],
      ),
    );
  }
}
