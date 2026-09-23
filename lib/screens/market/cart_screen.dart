import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/repositories.dart';
import '../../models/models.dart';
import '../../router/nav.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/async.dart';
import '../../widgets/cart_composer.dart';
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
///
/// Two shelves: what is being bought, and what has been set aside. A saved
/// line is in no total and is not handed to checkout, and it gives up the
/// public "in this many carts right now" count while it sits there.
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
        // Only truly bare counts as empty: a cart with nothing to buy but
        // three things saved for later is not an empty screen.
        isEmpty: (cart) => cart.isBare,
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
            if (cart.lines.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(14, 8, 14, 0),
                child: LbmCard(
                  child: LbmEmpty(
                    title: 'Nothing in the cart',
                    body: 'What you saved for later is below.',
                    compact: true,
                  ),
                ),
              )
            else ...[
              LbmCard(
                margin: const EdgeInsets.symmetric(horizontal: 14),
                child: RowStack(
                  children: [
                    for (final line in cart.lines) _CartLineRow(line: line),
                  ],
                ),
              ),
              _Summary(cart: cart),
            ],
            _SavedShelf(saved: cart.saved),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

/// Set aside for later: a thinner row, and the two things you can do with it.
class _SavedShelf extends ConsumerWidget {
  const _SavedShelf({required this.saved});

  final List<CartLine> saved;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    if (saved.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHead(
          saved.length == 1
              ? '1 saved for later'
              : '${saved.length} saved for later',
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
          child: Text(
            'Not in your cart and not in the total. Move one back whenever '
            'you like; the price is taken fresh from the shop.',
            style: LbmText.xtiny.copyWith(color: c.ink2, height: 1.5),
          ),
        ),
        LbmCard(
          margin: const EdgeInsets.symmetric(horizontal: 14),
          child: RowStack(
            children: [
              for (final line in saved) _SavedLineRow(line: line),
            ],
          ),
        ),
      ],
    );
  }
}

class _SavedLineRow extends ConsumerStatefulWidget {
  const _SavedLineRow({required this.line});

  final CartLine line;

  @override
  ConsumerState<_SavedLineRow> createState() => _SavedLineRowState();
}

class _SavedLineRowState extends ConsumerState<_SavedLineRow> {
  bool _busy = false;

  Future<void> _run(Future<Cart> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
    } on RepositoryException catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text(describeError(error).body)),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final line = widget.line;
    final commerce = ref.read(commerceRepositoryProvider);

    return ListRow(
      crossAxisAlignment: CrossAxisAlignment.start,
      leading: SizedBox(
        width: 44,
        child: line.imageUrl == null
            ? const LbmSkeleton(height: 44, radius: 12)
            : ClipRRect(
                borderRadius: const BorderRadius.all(Radius.circular(12)),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: ProductPhoto(
                    url: line.imageUrl!,
                    fallback: const LbmSkeleton(height: 44, radius: 12),
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
            Text(
              [
                if (!isPlaceholderVariantName(line.variantTitle))
                  line.variantTitle,
                '${line.unitPrice} when you saved it',
              ].join(' · '),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                PillButton(
                  _busy ? 'Moving' : 'Move to cart',
                  small: true,
                  expand: false,
                  style: PillStyle.quiet,
                  onPressed: _busy
                      ? null
                      : () => _run(() => commerce.moveToCart(line.id)),
                ),
                _RowAction(
                  'Remove',
                  tint: c.ink3,
                  onPressed: _busy
                      ? () {}
                      : () => _run(() => commerce.removeSaved(line.id)),
                ),
              ],
            ),
          ],
        ),
      ),
      onTap: () => context.goToProduct(line.productId),
    );
  }
}

class _CartLineRow extends ConsumerStatefulWidget {
  const _CartLineRow({required this.line});

  final CartLine line;

  @override
  ConsumerState<_CartLineRow> createState() => _CartLineRowState();
}

class _CartLineRowState extends ConsumerState<_CartLineRow> {
  /// True from the tap until the cart stream catches up. Every control on
  /// the row goes quiet while it is set.
  ///
  /// Without it the row was silent for as long as the round trip took, so a
  /// tester tapped Remove twice and then said the cart was broken (Grace,
  /// 2026-09-23). The work is the same; a tap that visibly registers is the
  /// difference between slow and dead.
  bool _busy = false;

  Future<void> _run(Future<Cart> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
    } on RepositoryException catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text(describeError(error).body)),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final line = widget.line;
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
            Text(
              [
                if (!isPlaceholderVariantName(line.variantTitle))
                  line.variantTitle,
                '${line.unitPrice} each',
              ].join(' · '),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _StepButton(
                  icon: Icons.remove_rounded,
                  enabled: !_busy,
                  onTap: () => _run(
                    () => commerce.updateLine(
                      lineId: line.id,
                      quantity: line.quantity - 1,
                    ),
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
                  enabled: !_busy,
                  onTap: () => _run(
                    () => commerce.updateLine(
                      lineId: line.id,
                      quantity: line.quantity + 1,
                    ),
                  ),
                ),
              ],
            ),
            // Under the stepper rather than beside it, and wrapped rather
            // than in a Row: two words do not fit a 227pt column at large
            // text sizes, and this design throws on overflow.
            Wrap(
              spacing: 6,
              children: [
                // Not quite ready to buy it, not ready to lose it either
                // (Grace's testers, 2026-09-23).
                _RowAction(
                  _busy ? 'Working' : 'Save for later',
                  tint: c.skyDeep,
                  onPressed: _busy
                      ? null
                      : () => _run(() => commerce.saveForLater(line.id)),
                ),
                _RowAction(
                  'Remove',
                  tint: c.ink3,
                  onPressed: _busy
                      ? null
                      : () => _run(() => commerce.removeLine(line.id)),
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

/// A quiet word under a cart row. Small enough that two fit side by side in
/// the column a list row leaves, which is what the design throws for.
class _RowAction extends StatelessWidget {
  const _RowAction(this.label, {required this.tint, required this.onPressed});

  final String label;
  final Color tint;

  /// Null while the row is waiting on the backend.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: kBodyFont,
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: tint,
        ),
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final VoidCallback onTap;

  /// False while the row is waiting on the backend, so a second tap cannot
  /// queue a second change against a quantity that is about to move.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Semantics(
      button: true,
      enabled: enabled,
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        child: InkResponse(
          radius: 20,
          onTap: enabled ? onTap : null,
          child: Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: c.skyMist, shape: BoxShape.circle),
            child: Icon(icon, size: 16, color: c.ink),
          ),
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
            const SizedBox(height: 8),
            // The cart is a wishlist you can act on, and you can post it.
            PillButton(
              'Post my cart',
              style: PillStyle.ghost,
              onPressed: () => showPostCartSheet(context, ref, cart),
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
