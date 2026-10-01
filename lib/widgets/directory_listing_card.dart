import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/models.dart';
import '../router/nav.dart';
import '../state/providers.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'copy_address.dart';
import 'primitives.dart';
import 'remote_image.dart';
import 'sheets.dart';

/// One littlebluecart.com listing: the business, where it is, what it is,
/// who owns it, and the four ways to reach it. Used on the owner's Directory
/// screen (with the status chip) and, from CP-D4, on their public profile
/// and in the feed.
class DirectoryListingCard extends StatelessWidget {
  const DirectoryListingCard({
    super.key,
    required this.listing,
    this.showStatus = false,
    this.bare = false,
    this.showClaim = false,
  });

  final DirectoryListing listing;

  /// Published / Under review, for the owner only. A stranger never sees a
  /// pending listing, so the chip would only ever say Published.
  final bool showStatus;

  /// No card chrome of its own: inside a feed post, which is already a card.
  final bool bare;

  /// "Is this your business?" under a listing with no owner. On the browse
  /// and search screens, where a stranger might be its owner; never on the
  /// owner's own Directory screen, where every listing is already theirs.
  final bool showClaim;

  Future<void> _open(BuildContext context, Uri? uri) async {
    final messenger = ScaffoldMessenger.of(context);
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) {
      messenger.showSnackBar(SnackBar(content: Text('Could not open $uri')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final l = listing;
    final meta = [
      if (l.planLabel.isNotEmpty) l.planLabel,
      if (l.stateLabel.isNotEmpty) l.stateLabel,
    ].join(' · ');
    final chips = <String>{
      ...l.categories,
      if (l.stateLabel.isNotEmpty) l.stateLabel,
      ...l.tags,
    }.toList();
    final actions = <({String label, IconData icon, VoidCallback onTap})>[
      for (final (label, icon, uri) in [
        ('Website', Icons.language_rounded, l.websiteUri),
        ('Call', Icons.call_rounded, l.callUri),
        ('Email', Icons.mail_outline_rounded, l.emailUri),
      ])
        if (uri != null)
          (label: label, icon: icon, onTap: () => _open(context, uri)),
      if (l.address.isNotEmpty)
        (
          label: 'Copy address',
          icon: Icons.content_copy_rounded,
          onTap: () => copyAddress(context, l.address),
        ),
    ];

    // RemoteImage rather than a bare Image.network: it routes the picture
    // through this origin on the web (littlebluecart.com sends no CORS
    // header, so a browser refuses to draw it) and, when it still cannot be
    // shown, takes up no room instead of leaving a 16:9 hole above the name.
    final image = l.imageUrl.isEmpty
        ? null
        : RemoteImage(
            url: l.imageUrl,
            borderRadius: bare
                ? LbmRadius.imageR
                : const BorderRadius.vertical(top: Radius.circular(16)),
          );

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (image != null)
          bare
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                  child: image,
                )
              : image,
        Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      l.title,
                      style: LbmText.display.copyWith(
                        fontSize: 17,
                        color: c.ink,
                      ),
                    ),
                  ),
                  if (showStatus) ...[
                    const SizedBox(width: 8),
                    LbmChip(l.statusLabel),
                  ],
                ],
              ),
              if (meta.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(meta, style: LbmText.xtiny.copyWith(color: c.ink3)),
              ],
              if (l.description.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  l.description,
                  style: LbmText.tiny.copyWith(color: c.ink2, height: 1.45),
                ),
              ],
              if (chips.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  // Tappable: a chip that says "Woman Owned" and does
                  // nothing reads as a broken button, and the word is the
                  // most obvious thing on the card to want more of
                  // (Grace, 2026-09-28). A search rather than a category
                  // page, because these are three different kinds of word
                  // — a category, a state, a directory tag — and search is
                  // the one place that takes all three.
                  children: [
                    for (final chip in chips)
                      LbmChip(chip, onTap: () => context.goToResults(chip)),
                  ],
                ),
              ],
              if (l.address.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  l.address,
                  style: LbmText.tiny.copyWith(color: c.ink2, height: 1.4),
                ),
              ],
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final action in actions)
                      PillButton(
                        action.label,
                        small: true,
                        expand: false,
                        icon: action.icon,
                        style: PillStyle.quiet,
                        onPressed: action.onTap,
                      ),
                  ],
                ),
              ],
              if (showClaim && l.ownerUid.isEmpty) ...[
                const SizedBox(height: 10),
                const _ClaimRow(),
              ],
              _SiteLink(
                listing: l,
                onOpenSite: () => _open(context, l.linkUri),
              ),
            ],
          ),
        ),
      ],
    );

    // The card opens the listing's own page, from every list it sits in.
    // Not when bare: that is inside a post, which has a tap of its own.
    return bare
        ? content
        : LbmCard(
            onTap: () => context.goToDirectoryListing(l.id),
            child: content,
          );
  }
}

/// "Is this your business?" on a listing nobody has claimed yet.
///
/// The claim itself is the flow Grace has already tapped through: the
/// directory screen matches the account's verified email against
/// littlebluecart.com and hands over every listing that member owns at once.
/// So this is a signpost, not a second mechanism. A guest is asked to make a
/// profile first, because the match needs an email to match.
class _ClaimRow extends ConsumerWidget {
  const _ClaimRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: c.skyWash,
        borderRadius: LbmRadius.imageR,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Is this your business?',
            style: LbmText.tiny.copyWith(
              fontWeight: FontWeight.w800,
              color: c.ink,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            'Claim it and every other listing of yours at once, then sell '
            'here too.',
            style: LbmText.xtiny.copyWith(color: c.ink2, height: 1.45),
          ),
          const SizedBox(height: 10),
          PillButton(
            'Claim this listing',
            small: true,
            expand: false,
            style: PillStyle.ghost,
            onPressed: () => requireProfile(
              context,
              ref,
              () => context.push('/you/directory'),
            ),
          ),
        ],
      ),
    );
  }
}

/// The line under a card: the owner's Market shop when they sell here,
/// otherwise the listing's page on littlebluecart.com (Grace, 2026-09-30).
class _SiteLink extends ConsumerWidget {
  const _SiteLink({required this.listing, required this.onOpenSite});

  final DirectoryListing listing;
  final VoidCallback onOpenSite;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final shop = ref.watch(marketShopForListingProvider(listing.ownerUid));
    if (shop == null && listing.linkUri == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: InkWell(
        onTap: shop != null ? () => context.goToSeller(shop) : onOpenSite,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(
            shop != null ? 'Shop on the Market' : 'View on littlebluecart.com',
            style: LbmText.xtiny.copyWith(
              color: shop != null ? c.skyDeep : c.ink3,
              fontWeight: shop != null ? FontWeight.w800 : null,
              decoration: TextDecoration.underline,
            ),
          ),
        ),
      ),
    );
  }
}
