import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../router/nav.dart';
import '../state/providers.dart';
import '../state/session.dart';
import '../state/tips.dart';
import '../state/tour.dart';
import '../theme/tokens.dart';
import 'composers.dart';
import 'first_tour.dart';
import 'keep_it_here_dialog.dart';
import 'sheets.dart';

/// Branch order inside the shell. Guests never reach 1 or 2.
abstract final class Tabs {
  static const market = 0;
  static const community = 1;
  static const you = 2;
}

/// The three-tab shell. Each branch keeps its own back stack, which is what
/// gives Market, Community and You independent history.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // The tab bar gets out of the way when the keyboard is up, so a composer
    // sits directly above the keys.
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;

    // The first-time tour: requested when a profile has just been created,
    // shown once the shell is on screen, remembered on the phone so it never
    // comes back.
    if (ref.watch(tourPendingProvider)) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!context.mounted) return;
        if (!ref.read(tourPendingProvider.notifier).consume()) return;
        await showFirstTour(context);
        // The tour ends, by Done or by Skip, and the platform's one ask
        // follows it. Both are remembered by the same write below.
        if (!context.mounted) return;
        await showKeepItHereDialog(context);
        await ref.read(tipsProvider.notifier).markSeen(Tips.firstTour);
      });
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: c.paper,
        systemNavigationBarIconBrightness: isDark
            ? Brightness.light
            : Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: c.paper,
        body: navigationShell,
        bottomNavigationBar: keyboardOpen
            ? null
            : LbmTabBar(navigationShell: navigationShell),
      ),
    );
  }
}

/// The floating pill tab bar.
///
/// In guest mode Community and You are not in the bar at all; the second slot
/// reads "Sign up to unlock" and opens the gate.
class LbmTabBar extends ConsumerWidget {
  const LbmTabBar({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  void _goBranch(int index) {
    navigationShell.goBranch(
      index,
      // Tapping the tab you are already on returns to the root of that flow.
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final isGuest = ref.watch(isGuestProvider);
    final current = navigationShell.currentIndex;

    return Container(
      color: c.paper,
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: LbmRadius.pillR,
              boxShadow: c.shadowLift,
            ),
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Row(
                children: [
                  _TabButton(
                    icon: Icons.home_outlined,
                    activeIcon: Icons.home_rounded,
                    label: 'Market',
                    selected: current == Tabs.market,
                    onTap: () => _goBranch(Tabs.market),
                  ),
                  if (isGuest)
                    _TabButton(
                      icon: Icons.chat_bubble_outline_rounded,
                      activeIcon: Icons.chat_bubble_rounded,
                      label: 'Sign up to unlock',
                      selected: false,
                      dimmed: true,
                      onTap: () => showGateSheet(context),
                    )
                  else
                    _TabButton(
                      icon: Icons.chat_bubble_outline_rounded,
                      activeIcon: Icons.chat_bubble_rounded,
                      label: 'Community',
                      selected: current == Tabs.community,
                      badge: true,
                      onTap: () => _goBranch(Tabs.community),
                    ),
                  // Posting is the middle of the bar rather than a button
                  // floating over the grid, where it covered a pin and moved
                  // as you scrolled. It is the one orchid thing here, for the
                  // same reason the cart pill is the one orchid thing on a
                  // photograph: there is exactly one of each.
                  const _ComposeButton(),
                  const _CartTab(),
                  if (!isGuest)
                    _TabButton(
                      icon: Icons.person_outline_rounded,
                      activeIcon: Icons.person_rounded,
                      label: 'You',
                      selected: current == Tabs.you,
                      onTap: () => _goBranch(Tabs.you),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The orchid circle in the middle of the bar: post something.
///
/// Guests get the gate instead, the same as every other thing that writes.
class _ComposeButton extends ConsumerWidget {
  const _ComposeButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Semantics(
        button: true,
        label: 'Post something',
        child: Material(
          color: c.accentDeep,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () => requireProfile(
              context,
              ref,
              () => showNewPostSheet(context, ref),
            ),
            child: SizedBox(
              width: 54,
              height: 54,
              child: Icon(Icons.add_rounded, size: 28, color: c.accentInk),
            ),
          ),
        ),
      ),
    );
  }
}

/// The cart, in the bar.
///
/// Pushed rather than switched to: the cart is a shared route registered
/// under every branch, so opening it from the Market and from Community
/// keeps each tab's own back stack.
class _CartTab extends ConsumerWidget {
  const _CartTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(cartCountProvider);
    return _TabButton(
      icon: Icons.shopping_bag_outlined,
      activeIcon: Icons.shopping_bag_rounded,
      label: 'Cart',
      selected: false,
      count: count,
      onTap: context.goToCart,
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.badge = false,
    this.dimmed = false,
    this.count = 0,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// The unread dot on Community.
  final bool badge;

  /// The locked slot a guest sees.
  final bool dimmed;

  /// How many things are in the cart. Zero draws nothing: an empty cart does
  /// not need a badge saying it is empty.
  final int count;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final fg = selected ? c.accentText : c.ink3;

    return Expanded(
      child: Semantics(
        selected: selected,
        button: true,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: selected ? c.accentMist : null,
            borderRadius: LbmRadius.pillR,
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: onTap,
              borderRadius: LbmRadius.pillR,
              child: Opacity(
                opacity: dimmed ? 0.45 : 1,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.topCenter,
                    children: [
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            selected ? activeIcon : icon,
                            size: 22,
                            color: fg,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              height: 1.2,
                              color: fg,
                            ),
                          ),
                        ],
                      ),
                      if (badge)
                        Positioned(
                          top: 1,
                          right: 12,
                          child: Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: c.accentDeep,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      if (count > 0)
                        Positioned(
                          top: -1,
                          right: 6,
                          child: Container(
                            constraints: const BoxConstraints(minWidth: 16),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: c.accentDeep,
                              borderRadius: LbmRadius.pillR,
                            ),
                            child: Text(
                              '$count',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                height: 1.3,
                                color: c.accentInk,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
