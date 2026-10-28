import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../router/nav.dart';
import '../../widgets/primitives.dart';
import '../../widgets/screen.dart';
import 'collection_screen.dart' show CollectionTiles;

/// The Market button: the store's categories, and only those.
///
/// Grace, 2026-10-28: "Change Market button at the bottom to go to shopping
/// products on Little Blue Market", and asked for the category tiles on
/// their own. The feed that used to live behind this button (posts,
/// products, the banner) is Home now, one tap away at the top of the screen.
/// A tile opens that category's products; the pill searches everything.
class MarketScreen extends StatelessWidget {
  const MarketScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return LbmScreen(
      appBar: LbmAppBar(
        title: 'Market',
        showBack: context.canPop(),
        actions: const [HomeButton()],
      ),
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
            child: SearchPill(
              label: 'Search goods, sellers, #tags',
              onTap: context.goToSearch,
            ),
          ),
          const CollectionTiles(),
        ],
      ),
    );
  }
}
