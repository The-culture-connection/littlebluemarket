import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/fixtures.dart';
import '../../router/nav.dart';
import '../../widgets/primitives.dart';
import '../../widgets/product_art.dart';
import '../../widgets/profile_identity.dart';
import '../../widgets/screen.dart';
import '../../widgets/sheets.dart';
import '../market/results_screen.dart';

/// Your own profile: the Instagram layout, remapped.
///
/// The envelope opens messages and the overflow button opens shipping.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final me = Fx.me;
    final grid = _tab == 0 ? Fx.myPosts : Fx.myPurchases;

    return LbmScreen(
      appBar: LbmAppBar(
        showBack: false,
        centerTitle: true,
        titleSize: 17,
        title: me.handle,
        actions: [
          CircleIconButton(
            icon: Icons.mail_outline_rounded,
            tooltip: 'Messages',
            badge: true,
            onPressed: () => context.push('/you/messages'),
          ),
          CircleIconButton(
            icon: Icons.more_horiz_rounded,
            tooltip: 'Shipping details',
            onPressed: () => context.push('/you/shipping'),
          ),
        ],
      ),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          ProfileIdentity(
            person: me,
            actions: [
              Row(
                children: [
                  Expanded(
                    child: PillButton(
                      'Edit profile',
                      style: PillStyle.ghost,
                      onPressed: () => context.push('/you/edit'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  PillButton(
                    'Post',
                    icon: Icons.add_rounded,
                    expand: false,
                    onPressed: () => showNewPostSheet(context),
                  ),
                ],
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
                  badge: _tab == 1 && i < 2 ? 'Reviewed' : null,
                  onTap: () => context.goToPost(product.id),
                );
              },
            ),
          ),
          const Puff(),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
