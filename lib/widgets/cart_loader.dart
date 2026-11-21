import 'package:flutter/material.dart';

import '../app_assets.dart';
import '../theme/tokens.dart';

/// The app's loading mark: the cart, pulsing.
///
/// Grace, 2026-11-21: "If it has to be slow that's fine, but provide a
/// loading icon that is the cart pulsing." It replaces the grey Material
/// spinner wherever a whole section or screen is waiting, so a slow answer
/// looks like the brand thinking rather than a generic app stalling.
///
/// The cart is the bundled logo used as a mask and painted in `accentDeep`
/// (navy in light mode, sky in dark), so it reads on either page. It grows
/// a little and brightens, then settles, about once a second. When the
/// phone asks for reduced motion it holds still at full strength.
class CartLoader extends StatefulWidget {
  const CartLoader({super.key, this.size = 44, this.label = 'Loading'});

  /// Width of the cart. 44 suits a section; pass more for a full screen.
  final double size;

  /// What a screen reader says.
  final String label;

  @override
  State<CartLoader> createState() => _CartLoaderState();
}

class _CartLoaderState extends State<CartLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (still) {
      _pulse
        ..stop()
        ..value = 1;
    } else if (!_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final curve = CurvedAnimation(parent: _pulse, curve: Curves.easeInOut);
    final cart = Image.asset(
      LbmAssets.cartMark,
      width: widget.size,
      height: widget.size,
      fit: BoxFit.contain,
      color: c.accentDeep,
      colorBlendMode: BlendMode.srcIn,
      excludeFromSemantics: true,
    );
    return Semantics(
      label: widget.label,
      liveRegion: true,
      child: SizedBox(
        // Room for the grown cart, so the pulse never nudges its neighbours.
        width: widget.size * 1.2,
        height: widget.size * 1.2,
        child: Center(
          child: FadeTransition(
            opacity: Tween(begin: 0.45, end: 1.0).animate(curve),
            child: ScaleTransition(
              scale: Tween(begin: 0.88, end: 1.08).animate(curve),
              child: cart,
            ),
          ),
        ),
      ),
    );
  }
}
