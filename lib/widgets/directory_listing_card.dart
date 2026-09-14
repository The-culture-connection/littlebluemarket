import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/models.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
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
    final actions = <({String label, IconData icon, Uri? uri})>[
      (label: 'Website', icon: Icons.language_rounded, uri: l.websiteUri),
      (label: 'Call', icon: Icons.call_rounded, uri: l.callUri),
      (label: 'Email', icon: Icons.mail_outline_rounded, uri: l.emailUri),
      (label: 'Directions', icon: Icons.near_me_rounded, uri: l.directionsUri),
    ].where((a) => a.uri != null).toList();

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
                    children: [for (final chip in chips) LbmChip(chip)],
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
                          onPressed: () => _open(context, action.uri),
                        ),
                    ],
                  ),
                ],
                if (showClaim && l.ownerUid.isEmpty) ...[
                  const SizedBox(height: 10),
                  const _ClaimRow(),
                ],
                if (l.linkUri != null) ...[
                  const SizedBox(height: 10),
                  InkWell(
                    onTap: () => _open(context, l.linkUri),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        'View on littlebluecart.com',
                        style: LbmText.xtiny.copyWith(
                          color: c.ink3,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      );

    return bare ? content : LbmCard(child: content);
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
