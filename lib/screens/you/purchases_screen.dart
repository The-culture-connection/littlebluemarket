import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/models.dart';
import '../../router/nav.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/async.dart';
import '../../widgets/composers.dart';
import '../../widgets/primitives.dart';
import '../../widgets/product_art.dart';
import '../../widgets/screen.dart';
import '../../widgets/sheets.dart';
import '../../widgets/skeleton.dart';

/// Everything this person has bought, with the ones still waiting for a
/// review at the top.
///
/// This is where "How was it?" in the feed goes. It used to open the product
/// itself, which is the wrong thing twice over: somebody prompted to review
/// usually has more than one thing waiting, and the product page is about
/// buying it again rather than about saying how it was.
class PurchasesScreen extends ConsumerWidget {
  const PurchasesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final purchases = ref.watch(purchasesProvider);

    return LbmScreen(
      appBar: const LbmAppBar(title: 'Things you bought'),
      child: LbmAsync<List<Purchase>>(
        purchases,
        skeleton: const ListRowSkeleton(rows: 4),
        onRetry: () => ref.invalidate(purchasesProvider),
        isEmpty: (all) => all.isEmpty,
        empty: const LbmEmpty(
          title: 'Nothing yet',
          body: 'What you buy shows up here, ready to be reviewed.',
        ),
        data: (all) {
          // Waiting ones first: the whole point of the screen is the ones
          // that still have something to say.
          final waiting = [for (final p in all) if (p.canReview) p];
          final done = [for (final p in all) if (!p.canReview) p];

          return ListView(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
            children: [
              if (waiting.isNotEmpty) ...[
                SectionHead('Waiting for a review (${waiting.length})'),
                for (final purchase in waiting)
                  _PurchaseRow(purchase: purchase, canReview: true),
                const SizedBox(height: 8),
              ],
              if (done.isNotEmpty) ...[
                const SectionHead('Reviewed'),
                for (final purchase in done)
                  _PurchaseRow(purchase: purchase, canReview: false),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _PurchaseRow extends ConsumerWidget {
  const _PurchaseRow({required this.purchase, required this.canReview});

  final Purchase purchase;
  final bool canReview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;

    return LbmCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      onTap: () => context.goToProduct(purchase.productId),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.all(Radius.circular(12)),
            child: SizedBox(
              width: 56,
              height: 56,
              child: ColoredBox(
                color: c.skyWash,
                child: purchase.imageUrl == null || purchase.imageUrl!.isEmpty
                    ? Icon(Icons.image_outlined, color: c.ink3)
                    : ProductPhoto(
                        url: purchase.imageUrl!,
                        cacheWidth: 160,
                        fallback: ColoredBox(color: c.skyMist),
                      ),
              ),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  purchase.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: LbmText.pinTitle.copyWith(fontSize: 14, color: c.ink),
                ),
                const SizedBox(height: 3),
                Text(
                  canReview
                      ? 'Bought ${purchase.age}'
                      : 'Bought ${purchase.age} · reviewed',
                  style: LbmText.pinMeta.copyWith(color: c.ink2),
                ),
              ],
            ),
          ),
          if (canReview) ...[
            const SizedBox(width: 8),
            LbmChip(
              'Rate it',
              accent: true,
              fontSize: 12.5,
              onTap: () => requireProfile(
                context,
                ref,
                () => showLbmSheet(
                  context,
                  (_) => ReviewComposer(initialPurchaseId: purchase.id),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
