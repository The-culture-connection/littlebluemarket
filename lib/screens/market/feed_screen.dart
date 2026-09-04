import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/fixtures/fixture_data.dart';
import '../../router/nav.dart';
import '../../state/session.dart';
import '../../theme/tokens.dart';
import '../../widgets/post_card.dart';
import '../../widgets/primitives.dart';
import '../../widgets/product_art.dart';
import '../../widgets/screen.dart';

/// The marketplace feed.
///
/// Rounded cards floating on soft blue rather than an edge-to-edge grid: a
/// search pill and Near me at the top, initiative hashtags below, then goods
/// and services in one stream.
class FeedScreen extends ConsumerStatefulWidget {
  const FeedScreen({super.key});

  @override
  ConsumerState<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends ConsumerState<FeedScreen> {
  bool _nearMe = false;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final isGuest = ref.watch(isGuestProvider);

    return LbmScreen(
      appBar: Container(
        color: c.paper,
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: SearchPill(
                    label: 'Search goods, services, #tags',
                    onTap: () => context.push('/market/search'),
                  ),
                ),
                const SizedBox(width: 10),
                NearMeButton(
                  active: _nearMe,
                  onTap: () => setState(() => _nearMe = !_nearMe),
                ),
              ],
            ),
            const SizedBox(height: 11),
            SizedBox(
              height: 32,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: 6,
                separatorBuilder: (_, _) => const SizedBox(width: 7),
                itemBuilder: (context, i) => LbmChip(
                  Fx.tags[i].tag,
                  style: ChipStyle.initiative,
                  onTap: () => context.goToResults(Fx.tags[i].tag),
                ),
              ),
            ),
          ],
        ),
      ),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          if (isGuest) const GuestBanner(),
          for (final id in Fx.feedOrder)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: PostCard(Fx.product(id)),
            ),
          const Puff(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 2, 20, 26),
            child: Text(
              "That's everything new.\nTry a hashtag to keep going.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, height: 1.6, color: c.ink2),
            ),
          ),
        ],
      ),
    );
  }
}
