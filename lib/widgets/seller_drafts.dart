import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/repositories/repositories.dart';
import '../models/models.dart';
import '../state/providers.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'async.dart';
import 'primitives.dart';

/// The top of a seller's own Products tab: the Add button, and every draft
/// that is not live yet with an honest chip on it.
///
/// A submitted product is on the store as a DRAFT awaiting the merchant; it
/// is not in the shop, and the grid below will not show it. Listing it here
/// with "Under review" is what stops that from becoming a support ticket.
class SellerDraftsPanel extends ConsumerWidget {
  const SellerDraftsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final listings = ref.watch(listingsProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PillButton(
            'Add a product',
            icon: Icons.add_rounded,
            onPressed: () => context.push('/you/add-product'),
          ),
          LbmAsync<List<Listing>>(
            listings,
            skeleton: const SizedBox.shrink(),
            errorBuilder: (_, _) => const SizedBox.shrink(),
            isEmpty: (items) =>
                items.where((l) => l.status != ListingStatus.live).isEmpty,
            empty: const SizedBox.shrink(),
            data: (items) {
              final pending = items
                  .where((l) => l.status != ListingStatus.live)
                  .toList();
              return Padding(
                padding: const EdgeInsets.only(top: 12),
                child: LbmCard(
                  child: RowStack(
                    children: [
                      for (final listing in pending)
                        _DraftRow(listing: listing),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 4),
          Text(
            'Approved products appear in the grid below.',
            style: LbmText.xtiny.copyWith(color: c.ink3),
          ),
        ],
      ),
    );
  }
}

class _DraftRow extends ConsumerStatefulWidget {
  const _DraftRow({required this.listing});

  final Listing listing;

  @override
  ConsumerState<_DraftRow> createState() => _DraftRowState();
}

class _DraftRowState extends ConsumerState<_DraftRow> {
  bool _busy = false;

  Future<void> _retry() async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(sellerRepositoryProvider)
          .publishListing(widget.listing.id);
      messenger.showSnackBar(const SnackBar(content: Text('Sent for review.')));
    } on RepositoryException catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text(describeError(error).body)),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final listing = widget.listing;
    final (Color chipBg, Color chipFg) = switch (listing.status) {
      ListingStatus.submitted => (c.accentMist, c.accentText),
      ListingStatus.failed || ListingStatus.rejected => (c.skyWash, c.clay),
      _ => (c.skyWash, c.ink2),
    };

    return ListRow(
      crossAxisAlignment: CrossAxisAlignment.start,
      leading: SizedBox(
        width: 44,
        height: 44,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: listing.imageUrls.isEmpty
              ? ColoredBox(color: c.skyWash)
              : Image.network(
                  listing.imageUrls.first,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => ColoredBox(color: c.skyWash),
                ),
        ),
      ),
      title: Text(listing.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        listing.error ?? Fmt.money(listing.priceCents),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: chipBg,
              borderRadius: LbmRadius.pillR,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              child: Text(
                _busy ? 'Sending…' : listing.status.label,
                style: LbmText.xtiny.copyWith(
                  fontWeight: FontWeight.w800,
                  color: chipFg,
                ),
              ),
            ),
          ),
          if (listing.status.editable && !_busy) ...[
            const SizedBox(height: 6),
            PillButton(
              'Retry',
              small: true,
              expand: false,
              style: PillStyle.quiet,
              onPressed: _retry,
            ),
          ],
        ],
      ),
      onTap: listing.status == ListingStatus.submitted
          ? () => showDialog<void>(
              context: context,
              builder: (dialogContext) => AlertDialog(
                backgroundColor: dialogContext.c.surface,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(Radius.circular(22)),
                ),
                title: const Text('Under review'),
                content: Text(
                  '"${listing.title}" is with Little Blue Market for approval. '
                  'It appears in your shop as soon as it is approved.',
                ),
                actions: [
                  PillButton(
                    'Got it',
                    small: true,
                    expand: false,
                    onPressed: () => Navigator.of(dialogContext).pop(),
                  ),
                ],
              ),
            )
          : null,
    );
  }
}
