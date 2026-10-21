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
/// Shown on every cart, empty ones included (Grace, 2026-10-21): with
/// nothing to round, the switch waits and says what it will do. Hides
/// itself only when the store has said it has no round-up product, which is
/// how the whole feature ships dark.
class RoundUpCard extends ConsumerStatefulWidget {
  const RoundUpCard({super.key, required this.subtotalCents});

  final int subtotalCents;

  @override
  ConsumerState<RoundUpCard> createState() => _RoundUpCardState();
}

class _RoundUpCardState extends ConsumerState<RoundUpCard> {
  @override
  void initState() {
    super.initState();
    // The config is asked for once per app session and kept. If that one
    // answer was a failure, or a "no" given while the store was not
    // answering, the card stayed hidden until the app was closed, which is
    // why the round-up was only sometimes there. Opening the cart asks again.
    final config = ref.read(appConfigProvider);
    if (config.hasError || config.value?.canRoundUp == false) {
      Future.microtask(() {
        if (mounted) ref.invalidate(appConfigProvider);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final subtotalCents = widget.subtotalCents;
    final config = ref.watch(appConfigProvider);
    // Drawn while the answer is on its way, so it does not pop in late. Only
    // a settled "no product in this store" hides it.
    final canRoundUp = config.value?.canRoundUp ?? config.isLoading;
    if (!canRoundUp) return const SizedBox.shrink();

    final ready = subtotalCents > 0 && config.value?.canRoundUp == true;
    final on = ready && ref.watch(roundUpProvider);
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
                    subtotalCents <= 0
                        ? 'Add something to your cart, then round up to the '
                              'nearest dollar. The change keeps the app running.'
                        : on
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
              onChanged: ready
                  ? (next) => ref.read(roundUpProvider.notifier).set(next)
                  : null,
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
