import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/models.dart';
import '../../router/nav.dart';
import '../../state/providers.dart';
import '../../state/session.dart';
import '../../widgets/async.dart';
import '../../widgets/directory_listing_card.dart';
import '../../widgets/directory_storefront.dart';
import '../../widgets/primitives.dart';
import '../../widgets/report_sheet.dart';
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
    // A directory business shows a storefront the way a Market seller does:
    // the listing's photos, then what it sells on its own website.
    final hasDirectory = ref.watch(
      hasDirectoryStorefrontProvider(widget.personId),
    );

    return LbmScreen(
      appBar: LbmAppBar(
        title: person.value?.handle ?? '',
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
                if (ref.watch(currentUidProvider) != person.id)
                  _NotifyMeButton(personId: person.id),
              ],
            ),
            // A business listed on littlebluecart.com shows its listing the
            // way a seller shows a storefront. Nothing when there is none.
            _DirectorySection(personId: person.id),
            // A buyer has no storefront, so they get one tab rather than an
            // empty "Posted" one.
            if (person.isSeller || hasDirectory)
              SegmentedTabs(
                labels: const ['Posted', 'Reviews written'],
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
            ] else
              _ReviewsWritten(personId: person.id),
            const SizedBox(height: 26),
          ],
        ),
      ),
    );
  }
}

/// This person's published littlebluecart.com listings, from the public
/// mirror. Decided by the query, not by a field on the profile.
class _DirectorySection extends ConsumerWidget {
  const _DirectorySection({required this.personId});

  final String personId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listings = ref.watch(directoryListingsOfProvider(personId));
    return LbmAsync<List<DirectoryListing>>(
      listings,
      skeleton: const SizedBox.shrink(),
      errorBuilder: (_, _) => const SizedBox.shrink(),
      data: (list) => list.isEmpty
          ? const SizedBox.shrink()
          : Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionHead('Little Blue Cart directory'),
                  const SizedBox(height: 8),
                  for (final listing in list)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: DirectoryListingCard(listing: listing),
                    ),
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
