import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../router/nav.dart';
import '../state/providers.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'cart_pill.dart';
import 'product_art.dart';

/// The listing a message is about, inside the bubble.
///
/// This is the bridge the redesign is for: a maker drops a product into a
/// conversation and it can be carted from there, so talking to people and
/// buying from them stop being two separate apps that share a tab bar.
class MessageProductCard extends ConsumerWidget {
  const MessageProductCard({
    super.key,
    required this.productId,
    this.onDark = false,
  });

  final String productId;

  /// Inside somebody's own orchid bubble, where the card needs its own pale
  /// surface to be legible.
  final bool onDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final product = ref.watch(productProvider(productId)).value;
    if (product == null) return const SizedBox.shrink();

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => context.goToProduct(product.id),
      child: Container(
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          color: onDark ? c.surface : c.skyWash,
          borderRadius: const BorderRadius.all(Radius.circular(14)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.all(Radius.circular(9)),
              child: SizedBox(
                width: 40,
                height: 40,
                child: ProductArt(product, square: true),
              ),
            ),
            const SizedBox(width: 9),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    product.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: LbmText.pinTitle.copyWith(
                      fontSize: 12.5,
                      color: c.ink,
                    ),
                  ),
                  Text(
                    product.price,
                    style: LbmText.pinMeta.copyWith(color: c.ink2),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            CartPill(productId: product.id),
          ],
        ),
      ),
    );
  }
}
