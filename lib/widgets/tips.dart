import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../state/providers.dart';
import '../state/session.dart';
import '../state/tips.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'async.dart';
import 'composers.dart';
import 'primitives.dart';
import 'sheets.dart';

const _cartTipTitle = '♡ is now 🛒';
const _cartTipBody =
    'On Little Blue Market, adding something to your cart is how you show a '
    'maker you love their work. There is no separate like. Your cart is a '
    'wishlist you can act on, and you can post it whenever you want.';

/// The tutorial card at the top of the feed, until it has been dismissed once.
class CartTipCard extends ConsumerWidget {
  const CartTipCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final seen = ref.watch(tipsProvider).contains(Tips.cartIsTheLike);
    if (seen) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      child: LbmCard(
        color: c.accentMist,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _cartTipTitle,
              style: LbmText.display.copyWith(fontSize: 18, color: c.ink),
            ),
            const SizedBox(height: 6),
            Text(
              _cartTipBody,
              style: LbmText.tiny.copyWith(color: c.ink2, height: 1.5),
            ),
            const SizedBox(height: 10),
            PillButton(
              'Got it',
              small: true,
              expand: false,
              style: PillStyle.quiet,
              onPressed: () =>
                  ref.read(tipsProvider.notifier).markSeen(Tips.cartIsTheLike),
            ),
          ],
        ),
      ),
    );
  }
}

/// The same tip as a one-time dialog, the first time a card's cart action is
/// tapped. Returns once the tip is dismissed (or immediately if seen).
Future<void> showCartTipOnce(BuildContext context, WidgetRef ref) async {
  final tips = ref.read(tipsProvider.notifier);
  if (tips.seen(Tips.cartIsTheLike)) return;
  await tips.markSeen(Tips.cartIsTheLike);
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      final c = dialogContext.c;
      return AlertDialog(
        backgroundColor: c.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(22)),
        ),
        title: Text(
          _cartTipTitle,
          style: LbmText.display.copyWith(fontSize: 21, color: c.ink),
        ),
        content: Text(
          _cartTipBody,
          style: LbmText.body.copyWith(color: c.ink2, fontSize: 14),
        ),
        actions: [
          PillButton(
            'Got it',
            small: true,
            expand: false,
            onPressed: () => Navigator.of(dialogContext).pop(),
          ),
        ],
      );
    },
  );
}

/// "How was it?" — shown while something delivered is still unreviewed.
///
/// Delivery is the moment a review is worth asking for, and the moment a
/// buyer is most likely to write one. The card opens the review composer
/// with that purchase already picked.
class ReviewPromptCard extends ConsumerWidget {
  const ReviewPromptCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    if (ref.watch(isGuestProvider)) return const SizedBox.shrink();
    final purchases = ref.watch(purchasesProvider);

    return LbmAsync<List<Purchase>>(
      purchases,
      skeleton: const SizedBox.shrink(),
      errorBuilder: (_, _) => const SizedBox.shrink(),
      isEmpty: (all) => !all.any((p) => p.delivered && p.canReview),
      empty: const SizedBox.shrink(),
      data: (all) {
        final waiting = all.where((p) => p.delivered && p.canReview).toList();
        final first = waiting.first;
        return Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          child: LbmCard(
            color: c.sageMist,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'How was it?',
                  style: LbmText.display.copyWith(fontSize: 18, color: c.ink),
                ),
                const SizedBox(height: 6),
                Text(
                  waiting.length == 1
                      ? '"${first.title}" arrived. A review helps the next '
                            'person find it.'
                      : '${waiting.length} things arrived. A review helps the '
                            'next person find them.',
                  style: LbmText.tiny.copyWith(color: c.ink2, height: 1.5),
                ),
                const SizedBox(height: 10),
                PillButton(
                  'Write a review',
                  small: true,
                  expand: false,
                  onPressed: () => showLbmSheet(
                    context,
                    (_) => ReviewComposer(initialPurchaseId: first.id),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
