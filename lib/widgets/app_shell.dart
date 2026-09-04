import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../state/session.dart';
import '../theme/tokens.dart';
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
                  else ...[
                    _TabButton(
                      icon: Icons.chat_bubble_outline_rounded,
                      activeIcon: Icons.chat_bubble_rounded,
                      label: 'Community',
                      selected: current == Tabs.community,
                      badge: true,
                      onTap: () => _goBranch(Tabs.community),
                    ),
                    _TabButton(
                      icon: Icons.person_outline_rounded,
                      activeIcon: Icons.person_rounded,
                      label: 'You',
                      selected: current == Tabs.you,
                      onTap: () => _goBranch(Tabs.you),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
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
