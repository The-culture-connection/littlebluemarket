import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/fixtures.dart';
import '../../router/nav.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/primitives.dart';
import '../../widgets/profile_identity.dart';
import '../../widgets/screen.dart';
import '../../widgets/sheets.dart';
import 'results_screen.dart';

/// The public view of a profile.
///
/// Same layout as your own, minus the add-post button and shipping. One
/// Message button, and no Follow — there is no follow relationship in the
/// product at all.
class SellerFeedScreen extends ConsumerStatefulWidget {
  const SellerFeedScreen({super.key, required this.personId});

  final String personId;

  @override
  ConsumerState<SellerFeedScreen> createState() => _SellerFeedScreenState();
}

class _SellerFeedScreenState extends ConsumerState<SellerFeedScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final person = Fx.person(widget.personId);

    final own = Fx.products.values
        .where((p) => p.sellerId == widget.personId)
        .map((p) => p.id)
        .toList();
    final source = own.isEmpty ? const ['p1', 'p4', 'p5'] : own;
    // Pad out to a full grid the way the prototype does, so the layout reads
    // as a real storefront rather than a stub.
    final grid = [...source, ...source].take(9).toList();

    return LbmScreen(
      appBar: LbmAppBar(
        title: person.handle,
        actions: [
          CircleIconButton(
            icon: Icons.more_horiz_rounded,
            tooltip: 'More',
            onPressed: () {},
          ),
        ],
      ),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          ProfileIdentity(
            person: person,
            actions: [
              PillButton(
                'Message',
                onPressed: () => requireProfile(
                  context,
                  ref,
                  () => context.goToDm(person.id),
                ),
              ),
            ],
          ),
          SegmentedTabs(
            labels: const ['Posted', 'Bought & reviewed'],
            selected: _tab,
            onChanged: (i) => setState(() => _tab = i),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 7,
                crossAxisSpacing: 7,
              ),
              itemCount: grid.length,
              itemBuilder: (context, i) {
                final product = Fx.product(grid[i]);
                return GridCell(
                  product: product,
                  badge: i % 3 == 1 ? 'Review' : null,
                  onTap: () => context.goToPost(product.id),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Public view — no add-post button, no shipping',
              textAlign: TextAlign.center,
              style: LbmText.xtiny.copyWith(color: c.ink2),
            ),
          ),
        ],
      ),
    );
  }
}
