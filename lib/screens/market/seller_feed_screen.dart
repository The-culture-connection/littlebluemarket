import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/models.dart';
import '../../router/nav.dart';
import '../../state/providers.dart';
import '../../state/session.dart';
import '../../widgets/async.dart';
import '../../widgets/directory_storefront.dart';
import '../../widgets/primitives.dart';
import '../../widgets/report_sheet.dart';
import '../../widgets/profile_identity.dart';
import '../../widgets/screen.dart';
import '../../widgets/seller_products_grid.dart';
import '../../widgets/sheets.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/unclaimed_shop.dart';

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
    // A directory business shows a storefront the way a Market seller does:
    // the listing's photos, then what it sells on its own website.
    final hasDirectory = ref.watch(
      hasDirectoryStorefrontProvider(widget.personId),
    );

    return LbmScreen(
      appBar: LbmAppBar(
        title: switch (person.value?.handle) {
          null || '' => 'Profile',
          final handle => handle,
        },
        actions: [
          CircleIconButton(
            icon: Icons.more_horiz_rounded,
            tooltip: 'More',
            onPressed: () {
              final p = person.value;
              if (p == null) return;
              showMoreSheet(
                context,
                ref,
                subjectUid: p.id,
                subjectName: p.name,
                subjectHandle: p.handle,
              );
            },
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
                if (!person.unclaimed &&
                    ref.watch(currentUidProvider) != person.id)
                  _NotifyMeButton(personId: person.id),
              ],
            ),
            // A shop that is on the market but has nobody behind it yet.
            UnclaimedShopCard(person: person),
            // A buyer has no shop, so they get one tab rather than an empty
            // one. The first tab is the shop's **products**, and used to be
            // labelled "Posted", which put a grid of products under a word
            // that means something else and directly under a "Posts" count
            // that disagreed with it: a shop showing "1 Posts" above twelve
            // product tiles looked plainly broken (Grace, 2026-09-24).
            if (person.isSeller || hasDirectory)
              SegmentedTabs(
                labels: const ['Products', 'Reviews written'],
                selected: _tab,
                onChanged: (i) => setState(() => _tab = i),
              ),
            if ((person.isSeller || hasDirectory) && _tab == 0) ...[
              if (hasDirectory) DirectoryPhotoStrip(ownerUid: person.id),
              if (person.isSeller) SellerProductsGrid(sellerId: person.id),
              if (hasDirectory)
                DirectoryProductsGrid(
                  ownerUid: person.id,
                  heading: person.isSeller ? 'Sold on their website' : null,
                ),
              // Everything this shop has is on this one tab, so the
              // littlebluecart.com listings belong here too rather than in a
              // band of their own above the tabs, where they read as part of
              // the profile header (Grace, 2026-09-24: a products tab
              // "which will also list directory listings").
              DirectoryListings(ownerUid: person.id),
            ] else
              _ReviewsWritten(personId: person.id),
            const SizedBox(height: 26),
          ],
        ),
      ),
    );
  }
}

/// Follow someone for a push when they post. One tap on, one tap off; the
/// label says which state you are in so the button never needs a tooltip.
class _NotifyMeButton extends ConsumerStatefulWidget {
  const _NotifyMeButton({required this.personId});

  final String personId;

  @override
  ConsumerState<_NotifyMeButton> createState() => _NotifyMeButtonState();
}

class _NotifyMeButtonState extends ConsumerState<_NotifyMeButton> {
  var _busy = false;

  Future<void> _toggle(bool on) async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(socialRepositoryProvider)
          .setFollowing(widget.personId, on);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            on
                ? 'You will hear when they post.'
                : 'No more posts from them.',
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(describeError(e).body)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final following =
        ref.watch(followingProvider(widget.personId)).value ?? false;
    return PillButton(
      following ? 'Notifying you' : 'Notify me',
      icon: following
          ? Icons.notifications_active_rounded
          : Icons.notifications_none_rounded,
      style: following ? PillStyle.quiet : PillStyle.ghost,
      onPressed: _busy
          ? null
          : () => requireProfile(context, ref, () => _toggle(!following)),
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
