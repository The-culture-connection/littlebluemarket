import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/repositories.dart';
import '../models/models.dart';
import '../router/nav.dart';
import '../state/providers.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'async.dart' show describeError;
import 'lbm_toast.dart';
import 'post_card.dart' show addToCart;
import 'sheets.dart' show requireProfile;
import 'tips.dart' show showCartTipOnce;

/// How big the pill is drawn. [large] is for a detail page's image, where the
/// photograph is the full width of the phone and a 34px pill disappears.
enum CartPillSize { small, large }

/// The one orchid thing on a photograph: add this to your cart.
///
/// The accent is reserved for this action across the whole app. Chips, tabs
/// and secondary buttons are sky or ink precisely so that when something is
/// pink it means "this puts it in your cart" and nothing else.
///
/// Adding to the cart **is** the like here. There is no heart in this app:
/// carting is the affinity signal, which is why the pill is on every photo
/// rather than tucked into a row of actions under it, and why tapping it a
/// second time takes the line back out.
class CartPill extends ConsumerStatefulWidget {
  const CartPill({
    super.key,
    required this.productId,
    this.variantId,
    this.size = CartPillSize.small,
  });

  final String productId;
  final String? variantId;
  final CartPillSize size;

  @override
  ConsumerState<CartPill> createState() => _CartPillState();
}

class _CartPillState extends ConsumerState<CartPill>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 450),
  );

  /// Out quickly, back with a wobble. The pop is what the eye catches at the
  /// edge of vision while the thumb is still on the glass.
  late final Animation<double> _bounce = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(
        begin: 1.0,
        end: 1.25,
      ).chain(CurveTween(curve: Curves.easeOut)),
      weight: 35,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: 1.25,
        end: 1.0,
      ).chain(CurveTween(curve: Curves.elasticOut)),
      weight: 65,
    ),
  ]).animate(_controller);

  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// One tap at a time: the repository call is a round trip, and a second tap
  /// mid-flight would add the line twice or remove one that is already gone.
  Future<void> _guard(Future<void> Function() body) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await body();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(CartLine line) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(commerceRepositoryProvider).removeLine(line.id);
    } on RepositoryException catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text(describeError(error).body)),
      );
    }
  }

  Future<void> _add() async {
    // The first time, say what the cart means here, before anything moves.
    await showCartTipOnce(context, ref);
    if (!mounted) return;
    await addToCart(
      context,
      ref,
      widget.productId,
      variantId: widget.variantId,
      announce: false, // the toast below says it, with the photograph
    );
    if (!mounted) return;

    _controller.forward(from: 0);
    final product = ref.read(productProvider(widget.productId)).value;
    LbmToast.show(
      context,
      title: 'In your little blue cart',
      subtitle: product?.title,
      thumbnailUrl: product?.imageUrls.firstOrNull,
      action: ('View', context.goToCart),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final cart = ref.watch(cartProvider).value;
    final line = cart?.lines.cast<CartLine?>().firstWhere(
      (l) => l?.productId == widget.productId,
      orElse: () => null,
    );
    final inCart = line != null;
    final big = widget.size == CartPillSize.large;

    final height = big ? 44.0 : 34.0;
    final iconSize = big ? 20.0 : 16.0;
    final label = inCart ? 'Carted' : 'Cart';

    // In the cart it goes ink: the job is done, so it stops asking. Orchid is
    // for the thing still to be tapped.
    final bg = inCart ? c.ink : c.accentDeep;
    final fg = inCart ? c.surface : c.accentInk;

    // The gesture sits *above* the bounce on purpose. A Transform moves what
    // is painted and what is hit, so a tap target inside the scale would
    // shrink and grow under the thumb mid-animation, and a second tap during
    // the bounce could miss the pill entirely.
    return Semantics(
      button: true,
      label: inCart ? 'In your cart. Tap to take it out.' : 'Add to your cart',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _busy
            ? null
            : () => requireProfile(context, ref, () {
                _guard(() => inCart ? _remove(line) : _add());
              }),
        child: ScaleTransition(
          scale: _bounce,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: bg,
              borderRadius: LbmRadius.pillR,
              // It sits on a photograph, so it has to lift off it.
              boxShadow: c.shadowSoft,
            ),
            child: SizedBox(
              height: height,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: big ? 16 : 11),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      inCart
                          ? Icons.check_rounded
                          : Icons.shopping_cart_outlined,
                      size: iconSize,
                      color: fg,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      label,
                      style: LbmText.pinTitle.copyWith(
                        fontSize: big ? 14 : 12.5,
                        color: fg,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
