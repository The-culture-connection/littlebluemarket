import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/models.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'primitives.dart';

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
  });

  final DirectoryListing listing;

  /// Published / Under review, for the owner only. A stranger never sees a
  /// pending listing, so the chip would only ever say Published.
  final bool showStatus;

  /// No card chrome of its own: inside a feed post, which is already a card.
  final bool bare;

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

    final image = l.imageUrl.isEmpty
        ? null
        : AspectRatio(
            aspectRatio: 16 / 9,
            child: Image.network(
              l.imageUrl,
              fit: BoxFit.cover,
              // A dead image link is not worth a broken-picture glyph.
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          );

    final content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (image != null)
            bare
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                    child: ClipRRect(
                      borderRadius: LbmRadius.imageR,
                      child: image,
                    ),
                  )
                : ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(16),
                    ),
                    child: image,
                  ),
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
