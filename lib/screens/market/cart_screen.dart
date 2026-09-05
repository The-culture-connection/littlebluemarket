import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/repositories.dart';
import '../../models/models.dart';
import '../../router/nav.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/async.dart';
import '../../widgets/checkout_launcher.dart';
import '../../widgets/primitives.dart';
import '../../widgets/product_art.dart';
import '../../widgets/screen.dart';
import '../../widgets/sheets.dart';
import '../../widgets/skeleton.dart';

/// The cart.
///
/// Ours, not the storefront's — which is the point. The lines live here, and
/// only the final handoff goes to whoever takes the money.
class CartScreen extends ConsumerWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);
    final pending = ref.watch(checkoutPendingProvider);

    // Something new in the cart means the last checkout is history.
    ref.listen(cartProvider, (_, next) {
      if (next.value?.isEmpty == false) {
        ref.read(checkoutPendingProvider.notifier).set(false);
      }
    });

    return LbmScreen(
      appBar: const LbmAppBar(title: 'Your cart'),
      child: LbmAsync<Cart>(
        cart,
        skeleton: const ListRowSkeleton(rows: 2),
        isEmpty: (cart) => cart.isEmpty,
        // After a checkout the cart empties when the paid-order webhook lands,
        // and that is the moment this copy has to be true. It never claims the
        // payment went through: the app cannot see that.
        empty: pending
            ? const LbmEmpty(
                title: "Thanks! We'll confirm shortly",
                body:
                    'Your order shows under Bought & received on your profile '
                    'as soon as the store confirms it, usually within a minute.',
              )
            : const LbmEmpty(
                title: 'Your cart is empty',
                body: 'Add something from the market and it waits here.',
              ),
        data: (cart) => ListView(
          padding: EdgeInsets.zero,
          children: [
            LbmCard(
              margin: const EdgeInsets.symmetric(horizontal: 14),
              child: RowStack(
                children: [
                  for (final line in cart.lines) _CartLineRow(line: line),
                ],
              ),
            ),
            _Summary(cart: cart),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

class _CartLineRow extends ConsumerWidget {
  const _CartLineRow({required this.line});

  final CartLine line;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final commerce = ref.read(commerceRepositoryProvider);

    return ListRow(
      crossAxisAlignment: CrossAxisAlignment.start,
      leading: SizedBox(
        width: 52,
        child: line.imageUrl == null
            ? const LbmSkeleton(height: 52, radius: 13)
            : ClipRRect(
                borderRadius: const BorderRadius.all(Radius.circular(13)),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: ProductPhoto(
                    url: line.imageUrl!,
                    fallback: const LbmSkeleton(height: 52, radius: 13),
                  ),
                ),
              ),
      ),
      title: Text(line.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${line.variantTitle} · ${line.unitPrice} each'),
            const SizedBox(height: 8),
            Row(
              children: [
                _StepButton(
                  icon: Icons.remove_rounded,
                  onTap: () => commerce.updateLine(
                    lineId: line.id,
                    quantity: line.quantity - 1,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    '${line.quantity}',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: c.ink,
                      fontFeatures: kTabularFigures,
                    ),
                  ),
                ),
                _StepButton(
                  icon: Icons.add_rounded,
                  onTap: () => commerce.updateLine(
                    lineId: line.id,
                    quantity: line.quantity + 1,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => commerce.removeLine(line.id),
                  child: Text(
                    'Remove',
                    style: TextStyle(
                      fontFamily: kBodyFont,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: c.ink3,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      trailing: Text(
        line.subtotal,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w800,
          color: c.ink,
          fontFeatures: kTabularFigures,
        ),
      ),
      onTap: () => context.goToProduct(line.productId),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Semantics(
      button: true,
      child: InkResponse(
        radius: 20,
        onTap: onTap,
        child: Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: c.skyMist, shape: BoxShape.circle),
          child: Icon(icon, size: 16, color: c.ink),
        ),
      ),
    );
  }
}

class _Summary extends ConsumerStatefulWidget {
  const _Summary({required this.cart});

  final Cart cart;

  @override
  ConsumerState<_Summary> createState() => _SummaryState();
}

class _SummaryState extends ConsumerState<_Summary> {
  bool _working = false;

  Future<void> _checkout() async {
    if (_working) return;
    setState(() => _working = true);

    final messenger = ScaffoldMessenger.of(context);
    try {
      final handoff = await ref
          .read(commerceRepositoryProvider)
          .beginCheckout();
      if (!mounted) return;
      setState(() => _working = false);
      // Nothing here claims the purchase succeeded. The app cannot observe a
      // hosted checkout completing; only the paid webhook is proof.
      showCheckoutSheet(context, ref, handoff);
    } on RepositoryException catch (error) {
      if (!mounted) return;
      setState(() => _working = false);
      messenger.showSnackBar(
        SnackBar(content: Text(describeError(error).body)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final cart = widget.cart;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
      child: LbmCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Line(label: 'Subtotal', value: cart.subtotal),
            const SizedBox(height: 10),
            _Line(
              label: 'Shipping & tax',
              // Honest about what is not known yet, rather than inventing a
              // number that checkout will contradict.
              value: cart.totalCents == null
                  ? 'Calculated at checkout'
                  : Fmt.money(cart.shippingCents! + cart.taxCents!),
              muted: cart.totalCents == null,
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Divider(height: 1),
            ),
            _Line(
              label: cart.totalCents == null ? 'Total so far' : 'Total',
              value: cart.totalCents == null
                  ? cart.subtotal
                  : Fmt.money(cart.totalCents!),
              strong: true,
            ),
            if (cart.sellerIds.length > 1) ...[
              const SizedBox(height: 10),
              Text(
                'From ${cart.sellerIds.length} sellers — each ships separately.',
                style: LbmText.xtiny.copyWith(color: c.ink2, height: 1.5),
              ),
            ],
            const SizedBox(height: 16),
            PillButton(
              _working ? 'Opening checkout…' : 'Checkout',
              onPressed: _working ? null : _checkout,
            ),
          ],
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({
    required this.label,
    required this.value,
    this.strong = false,
    this.muted = false,
  });

  final String label;
  final String value;
  final bool strong;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: strong ? 15 : 13.5,
              fontWeight: strong ? FontWeight.w800 : FontWeight.w600,
              color: strong ? c.ink : c.ink2,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: strong ? 18 : 13.5,
            fontWeight: FontWeight.w800,
            color: muted ? c.ink3 : c.ink,
            fontFeatures: kTabularFigures,
          ),
        ),
      ],
    );
  }
}
