import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/models.dart';
import '../../router/nav.dart';
import '../../state/providers.dart';
import '../../state/session.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/async.dart';
import '../../widgets/detail_sheet.dart';
import '../../widgets/masonry.dart';
import '../../widgets/pins/directory_card.dart';
import '../../widgets/primitives.dart';
import '../../widgets/product_art.dart';
import '../../widgets/sheets.dart';
import '../../widgets/skeleton.dart';

/// One littlebluecart.com business, in the app.
///
/// What the business card in the feed leaves out: the full description,
/// where to find them, how to reach them, every tag, and more like them.
/// Laid out like a product page (the picture edge to edge, the sheet pulled
/// up over it) so opening a business feels like opening anything else here.
///
/// There is no opening-hours row. The directory does not carry hours, and
/// the mockup's "Tue–Sat 10–6" was a placeholder, not data.
class DirectoryListingScreen extends ConsumerWidget {
  const DirectoryListingScreen({super.key, required this.listingId});

  final String listingId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listing = ref.watch(directoryListingProvider(listingId));

    return ColoredBox(
      color: context.c.paper,
      child: LbmAsync<DirectoryListing?>(
        listing,
        skeleton: const SafeArea(child: ProductDetailSkeleton()),
        onRetry: () => ref.invalidate(directoryListingProvider(listingId)),
        data: (listing) =>
            listing == null ? const _Gone() : _Body(listing: listing),
      ),
    );
  }
}

/// A listing that was taken down, or went back to pending, since the link
/// to it was drawn.
class _Gone extends StatelessWidget {
  const _Gone();

  @override
  Widget build(BuildContext context) {
    // Just the floating Back over empty paper, so there is still a way out.
    return const Column(
      children: [
        DetailGallery(child: SizedBox(height: 100, width: double.infinity)),
        Expanded(
          child: LbmEmpty(
            title: 'This business is not listed right now',
            body: 'It may be being updated on littlebluecart.com.',
          ),
        ),
      ],
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.listing});

  final DirectoryListing listing;

  /// An owner the app can message: somebody has claimed the listing, and it
  /// is not the person looking at it.
  static bool canMessage(DirectoryListing l, String? me) =>
      l.ownerUid.isNotEmpty && l.ownerUid != 'unclaimed' && l.ownerUid != me;

  Future<void> _open(BuildContext context, WidgetRef ref, Uri? uri) async {
    if (uri == null) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final ok = await ref.read(externalLauncherProvider)(uri);
    if (!ok) {
      messenger?.showSnackBar(SnackBar(content: Text('Could not open $uri')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final l = listing;
    final me = ref.watch(currentUidProvider);
    // The owner sells on the Market: send people to their shop here rather
    // than out to littlebluecart.com (Grace, 2026-09-30).
    final shop = ref.watch(marketShopForListingProvider(l.ownerUid));
    final category = l.categories.firstOrNull ?? '';
    final place = [l.city, l.state].where((s) => s.isNotEmpty).join(', ');
    final location = place.isNotEmpty
        ? place
        : l.locationLabel.replaceFirst('*', '').trim();
    final meta = [category, location].where((s) => s.isNotEmpty).join(' · ');
    final identity = l.tags
        .where((t) => t.toLowerCase().contains('owned'))
        .toList();
    // The zip code, never the street or the full address (Grace,
    // 2026-10-05). The town and state are already in [meta] above.
    final zipLine = l.zip.trim().isEmpty ? '' : 'Zip code ${l.zip.trim()}';

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        DetailGallery(
          child: AspectRatio(
            aspectRatio: 4 / 3,
            child: l.imageUrl.isEmpty
                ? ListingInitials(listing: l, fontSize: 72)
                : ProductPhoto(
                    url: l.imageUrl,
                    fallback: ListingInitials(listing: l, fontSize: 72),
                  ),
          ),
        ),
        DetailBody(
          children: [
            DetailSheet(
              children: [
                Text(
                  l.title,
                  style: LbmText.display.copyWith(fontSize: 24, color: c.ink),
                ),
                if (meta.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    meta,
                    style: LbmText.tiny.copyWith(
                      color: c.ink2,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                if (identity.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  TagChips(identity, onTap: (tag) => context.goToTag(tag)),
                ],
                const SizedBox(height: 16),
                if (shop != null) ...[
                  PillButton(
                    'Shop on the Market',
                    icon: Icons.storefront_rounded,
                    onPressed: () => context.goToSeller(shop),
                  ),
                  if (l.websiteUri != null) ...[
                    const SizedBox(height: 10),
                    PillButton(
                      'Visit website',
                      icon: Icons.language_rounded,
                      style: PillStyle.ghost,
                      onPressed: () => _open(context, ref, l.websiteUri),
                    ),
                  ],
                ] else if (l.websiteUri != null)
                  PillButton(
                    'Visit website',
                    icon: Icons.language_rounded,
                    onPressed: () => _open(context, ref, l.websiteUri),
                  )
                else if (l.linkUri != null)
                  PillButton(
                    'See it on littlebluecart.com',
                    icon: Icons.north_east_rounded,
                    onPressed: () => _open(context, ref, l.linkUri),
                  ),
                if (canMessage(l, me)) ...[
                  const SizedBox(height: 10),
                  PillButton(
                    'Message',
                    icon: Icons.chat_bubble_outline_rounded,
                    style: PillStyle.ghost,
                    onPressed: () => requireProfile(
                      context,
                      ref,
                      () => context.goToDm(l.ownerUid),
                    ),
                  ),
                ],
                if (l.description.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    l.description,
                    style: TextStyle(fontSize: 14, height: 1.55, color: c.ink2),
                  ),
                ],
              ],
            ),
            if (zipLine.isNotEmpty || l.callUri != null || l.emailUri != null)
              DetailSection(
                title: 'Find us',
                child: LbmCard(
                  margin: const EdgeInsets.symmetric(horizontal: 14),
                  child: RowStack(
                    children: [
                      if (zipLine.isNotEmpty)
                        _ReachRow(icon: Icons.place_rounded, text: zipLine),
                      if (l.callUri != null)
                        _ReachRow(
                          icon: Icons.call_rounded,
                          text: l.phone,
                          onTap: () => _open(context, ref, l.callUri),
                        ),
                      if (l.emailUri != null)
                        _ReachRow(
                          icon: Icons.mail_outline_rounded,
                          text: l.email,
                          onTap: () => _open(context, ref, l.emailUri),
                        ),
                    ],
                  ),
                ),
              ),
            if (l.tags.isNotEmpty || l.categories.isNotEmpty)
              DetailSection(
                title: 'Tags',
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TagChips(
                    <String>{...l.categories, ...l.tags}.toList(),
                    onTap: (tag) => context.goToTag(tag),
                  ),
                ),
              ),
            if (category.isNotEmpty)
              _AlsoIn(category: category, exceptId: l.id),
            const SizedBox(height: 40),
          ],
        ),
      ],
    );
  }
}

/// A zip code, a phone number or an email, and what tapping it does.
class _ReachRow extends StatelessWidget {
  const _ReachRow({required this.icon, required this.text, this.onTap});

  final IconData icon;
  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return ListRow(
      onTap: onTap,
      crossAxisAlignment: CrossAxisAlignment.start,
      leading: Icon(icon, size: 20, color: c.skyDeep),
      title: Text(
        text,
        style: TextStyle(
          fontSize: 14,
          height: 1.4,
          fontWeight: FontWeight.w700,
          color: c.ink,
        ),
      ),
      trailing: onTap == null
          ? null
          : Icon(Icons.chevron_right_rounded, size: 20, color: c.ink3),
    );
  }
}

/// Other businesses filed under the same category.
///
/// Reads the category's first page, which the browse screen caches anyway,
/// rather than asking for something new. The listing names its categories
/// by name and the pages are addressed by slug, so the rail's list of
/// categories is what joins the two.
class _AlsoIn extends ConsumerWidget {
  const _AlsoIn({required this.category, required this.exceptId});

  final String category;
  final String exceptId;

  static const _max = 6;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(directoryCategoriesProvider).value ?? const [];
    final slug = categories
        .where((cat) => cat.name == category)
        .firstOrNull
        ?.slug;
    if (slug == null) return const SizedBox.shrink();

    final page = ref.watch(directoryCategoryPageProvider(slug)).value;
    final others = [
      for (final l in page?.items ?? const <DirectoryListing>[])
        if (l.id != exceptId) l,
    ].take(_max).toList();
    if (others.isEmpty) return const SizedBox.shrink();

    return DetailSection(
      title: 'Also in $category',
      child: LbmMasonry.fixed(
        horizontal: 14,
        children: [for (final l in others) _MiniListing(listing: l)],
      ),
    );
  }
}

/// A business as a small tile: photo, name, town.
class _MiniListing extends StatelessWidget {
  const _MiniListing({required this.listing});

  final DirectoryListing listing;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final l = listing;
    final town = [l.city, l.state].where((s) => s.isNotEmpty).join(', ');

    return LbmCard(
      onTap: () => context.goToDirectoryListing(l.id),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ListingPhoto(listing: l, size: 44),
          const SizedBox(height: 10),
          Text(
            l.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: LbmText.pinTitle.copyWith(color: c.ink),
          ),
          if (town.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              town,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: LbmText.pinMeta.copyWith(color: c.ink2),
            ),
          ],
        ],
      ),
    );
  }
}
