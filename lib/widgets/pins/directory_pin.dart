import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/feed_item.dart';
import '../../models/models.dart';
import '../../router/nav.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../async.dart';
import '../directory_listing_card.dart';
import '../skeleton.dart';
import 'pin_caption.dart';

/// A littlebluecart.com business, in the grid.
///
/// Reuses [DirectoryListingCard] rather than restating it: the card is fed
/// live from the mirror, so an edit made on the website reaches the feed, and
/// there is exactly one place that decides what a listing looks like.
class DirectoryPin extends ConsumerWidget {
  const DirectoryPin({super.key, required this.item});

  final DirectoryItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final post = item.post;
    final listing = ref.watch(directoryListingProvider(post.listingId));

    // A listing that went back to pending is unreadable to a stranger; the
    // pin keeps the name until the sync takes the post down.
    final fallback = Text(
      post.title,
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      style: LbmText.display.copyWith(fontSize: 17, color: c.ink),
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => context.goToPost(post.id),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: LbmRadius.imageR,
          boxShadow: c.shadowSoft,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            PinMore(post: post, onSurface: true),
            LbmAsync<DirectoryListing?>(
              listing,
              skeleton: const ListRowSkeleton(rows: 2),
              errorBuilder: (_, _) => fallback,
              data: (current) => current == null
                  ? fallback
                  : DirectoryListingCard(listing: current, bare: true),
            ),
          ],
        ),
      ),
    );
  }
}
