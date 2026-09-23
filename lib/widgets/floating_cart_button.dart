import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../router/nav.dart';
import '../state/providers.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// The floating cart, bottom right on every screen.
///
/// It replaced the beta bug button, which stood in the same place and went
/// out with the beta (Grace, 2026-09-23). The cart earned the spot: on
/// Little Blue Market adding something to your cart is the affinity signal
/// as well as the way to buy, and testers kept losing what they had added
/// because the only way back to it was the icon on the feed's own app bar.
///
/// Mounted in the MaterialApp builder, above everything, so it is there on a
/// product, inside a seller's shop, halfway down a forum thread.
class CartLayer extends ConsumerWidget {
  const CartLayer({super.key, required this.router, required this.child});

  final GoRouter router;
  final Widget child;

  /// Screens with nothing to put in a cart, or nowhere to put the button:
  /// the welcome artwork, the onboarding steps, and the cart itself.
  static const hiddenOn = {
    '/',
    '/welcome',
    '/welcome-intro',
    '/orient',
    '/signin',
    '/verify',
    '/setup',
    '/terms',
    '/delete-account',
  };

  static bool isHidden(String path) =>
      hiddenOn.contains(path) || path.endsWith('/cart');

  /// Screens with a composer pinned along the bottom, where the button
  /// otherwise sits on top of Send (Grace, 2026-09-14). Raised by a
  /// composer's height on these, rather than moved for everyone.
  static const raisedOn = {'/community'};

  /// True for any screen whose bottom belongs to a composer, including the
  /// ones whose address carries an id.
  static bool isRaised(String path) =>
      // The Open chat IS the community root, which the first attempt at this
      // missed: it guessed '/community/chatroom', a route that does not
      // exist, so the button stayed on the Send button (Grace, twice).
      raisedOn.contains(path) ||
      path.startsWith('/community/thread/') ||
      path.startsWith('/community/forums/') ||
      path.startsWith('/market/post/') ||
      path.startsWith('/you/dm/');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final count = ref.watch(cartCountProvider);

    return Stack(
      children: [
        child,
        ListenableBuilder(
          // The route information provider, not the delegate: a push onto a
          // shell branch's own navigator (a product, the cart) leaves the
          // root delegate's `currentConfiguration` on the branch root, so a
          // layer watching that never learned it was on the cart screen.
          listenable: router.routeInformationProvider,
          builder: (context, _) {
            final path = router.routeInformationProvider.value.uri.path;
            if (keyboardOpen || isHidden(path)) return const SizedBox.shrink();
            return Positioned(
              right: 14,
              // Above the floating pill tab bar, which is 18 from the bottom
              // and about 64 tall, plus the phone's own gesture inset.
              bottom:
                  MediaQuery.viewPaddingOf(context).bottom +
                  (isRaised(path) ? 164 : 96),
              child: _CartButton(
                count: count,
                // Pushed onto the branch the person is already in, so Back
                // returns them to where they were rather than to the feed.
                // The router is asked directly: this widget is mounted above
                // it, so `context.goToCart()` has no GoRouterState to read.
                onPressed: () => router.push('${branchPrefixOf(path)}/cart'),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _CartButton extends StatelessWidget {
  const _CartButton({required this.count, required this.onPressed});

  /// How many things are in it. Zero draws no badge.
  final int count;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Semantics(
      button: true,
      label: count == 0
          ? 'Your cart'
          : 'Your cart, $count ${count == 1 ? 'item' : 'items'}',
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Material(
            color: c.accentDeep,
            shape: const CircleBorder(),
            elevation: 3,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onPressed,
              child: SizedBox(
                width: 52,
                height: 52,
                child: Icon(
                  Icons.shopping_bag_rounded,
                  color: c.accentInk,
                  size: 24,
                ),
              ),
            ),
          ),
          if (count > 0)
            Positioned(
              right: -2,
              top: -2,
              child: Container(
                constraints: const BoxConstraints(minWidth: 20),
                height: 20,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 5),
                decoration: BoxDecoration(
                  color: c.paper,
                  borderRadius: LbmRadius.pillR,
                  boxShadow: c.shadowSoft,
                ),
                child: Text(
                  count > 99 ? '99+' : '$count',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: c.ink,
                    fontFeatures: kTabularFigures,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
