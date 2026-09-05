import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/models.dart';
import '../../router/nav.dart';
import '../../state/providers.dart';
import '../../widgets/async.dart';
import '../../widgets/primitives.dart';
import '../../widgets/profile_identity.dart';
import '../../widgets/screen.dart';
import '../../widgets/seller_products_grid.dart';
import '../../widgets/sheets.dart';
import '../../widgets/skeleton.dart';

/// The public view of a profile.
///
/// Same layout as your own, minus the add-post button and shipping. One Message
/// button, and no Follow — there is no follow relationship in the product at
/// all.
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
    final person = ref.watch(personProvider(widget.personId));

    return LbmScreen(
      appBar: LbmAppBar(
        title: person.value?.handle ?? '',
        actions: [
          CircleIconButton(
            icon: Icons.more_horiz_rounded,
            tooltip: 'More',
            onPressed: () {},
          ),
        ],
      ),
      child: LbmAsync<Person>(
        person,
        skeleton: const IdentitySkeleton(),
        onRetry: () => ref.invalidate(personProvider(widget.personId)),
        data: (person) => ListView(
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
            // A buyer has no storefront, so they get one tab rather than an
            // empty "Posted" one.
            if (person.isSeller)
              SegmentedTabs(
                labels: const ['Posted', 'Reviews written'],
                selected: _tab,
                onChanged: (i) => setState(() => _tab = i),
              ),
            if (person.isSeller && _tab == 0)
              SellerProductsGrid(sellerId: person.id)
            else
              _ReviewsWritten(personId: person.id),
            const SizedBox(height: 26),
          ],
        ),
      ),
    );
  }
}

class _ReviewsWritten extends ConsumerWidget {
  const _ReviewsWritten({required this.personId});

  final String personId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final posts = ref.watch(postsByProvider(personId));

    return LbmAsync<List<Post>>(
      posts,
      skeleton: const ListRowSkeleton(rows: 2),
      data: (all) {
        final reviews = all.whereType<ReviewPost>().toList();
        if (reviews.isEmpty) {
          return const LbmEmpty(title: 'No reviews written yet', compact: true);
        }
        return Column(
          children: [
            for (final post in reviews)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                child: LbmCard(
                  padding: EdgeInsets.zero,
                  onTap: () => context.goToPost(post.id),
                  child: ListRow(
                    leading: Stars(post.rating.toDouble(), size: 12),
                    title: Text(
                      post.text,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(post.age),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
