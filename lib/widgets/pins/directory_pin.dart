import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/feed_item.dart';
import '../../models/models.dart';
import '../../router/nav.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../async.dart';
import '../skeleton.dart';
import 'directory_card.dart';
import 'pin_caption.dart';

/// A littlebluecart.com business, in the grid: the business card.
///
/// Fed live from the mirror, so an edit made on the website reaches the
/// feed. It used to be the whole listing (logo, every chip, the street
/// address) squeezed into a pin; that is the listing page now, and the card
/// is the invitation to it.
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
    final fallback = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => context.goToPost(post.id),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: LbmRadius.imageR,
          boxShadow: c.shadowSoft,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                post.title,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: LbmText.display.copyWith(fontSize: 17, color: c.ink),
              ),
            ),
            PinMore(post: post, onSurface: true),
          ],
        ),
      ),
    );

    return LbmAsync<DirectoryListing?>(
      listing,
      // The shape the card will be, not a generic two-row placeholder.
      //
      // Each of these resolves on its own, and a placeholder of the wrong
      // height means every one of them shoves the column below it down as its
      // listing arrives. On a feed that is mostly business cards that is
      // several hundred pixels of the page moving while somebody is reading
      // it (Grace, 2026-09-29). The card is a real 3.5-by-2 business card, so
      // its height is known before its contents are.
      skeleton: LayoutBuilder(
        builder: (_, constraints) => LbmSkeleton.block(
          height: directoryCardHeightFor(constraints.maxWidth),
        ),
      ),
      errorBuilder: (_, _) => fallback,
      data: (current) => current == null
          ? fallback
          : DirectoryBusinessCard(
              listing: current,
              more: PinMore(post: post, onSurface: true),
            ),
    );
  }
}
