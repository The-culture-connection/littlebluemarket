import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../primitives.dart';

/// The two lines under a photograph: what it is, and whose it is.
///
/// Sits directly on the paper with no card behind it, which is what lets the
/// photograph read as the card. Kept in one place because the product pin,
/// the review pin and the cart pin all use it and drifting apart by a pixel
/// is what makes a grid look untidy.
class PinCaption extends StatelessWidget {
  const PinCaption({
    super.key,
    required this.title,
    this.author,
    this.byline,
    this.trailing,
    this.maxLines = 2,
  });

  final String title;

  /// The maker, drawn as a small avatar before [byline].
  final Person? author;

  /// Overrides the text beside the avatar. Defaults to the first word of the
  /// author's name: in a 180-wide column "Untamed Alchemy" and a price do not
  /// both fit, and the first word is the part people recognise.
  final String? byline;

  /// The price, usually. Pushed to the right.
  final Widget? trailing;

  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final person = author;
    final line = byline ?? person?.name.split(RegExp(r'\s+')).first;

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 7, 4, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // An empty title is the review pin, which puts the quote above the
          // byline instead. Drawing it anyway would leave a blank line.
          if (title.isNotEmpty)
            Text(
              title,
              maxLines: maxLines,
              overflow: TextOverflow.ellipsis,
              style: LbmText.pinTitle.copyWith(color: c.ink),
            ),
          if (person != null || line != null || trailing != null) ...[
            if (title.isNotEmpty) const SizedBox(height: 5),
            Row(
              children: [
                if (person != null) ...[
                  Avatar(person, size: AvatarSize.xs),
                  const SizedBox(width: 6),
                ],
                if (line != null)
                  Flexible(
                    child: Text(
                      line,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: LbmText.pinMeta.copyWith(color: c.ink2),
                    ),
                  ),
                if (trailing != null) ...[
                  const SizedBox(width: 6),
                  trailing!,
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// The price at the end of a caption row, in the display face.
class PinPrice extends StatelessWidget {
  const PinPrice(this.cents, {super.key});

  final int cents;

  @override
  Widget build(BuildContext context) {
    return Text(
      Fmt.money(cents),
      maxLines: 1,
      style: LbmText.display.copyWith(fontSize: 14, color: context.c.ink),
    );
  }
}

/// The small dark badge over the top-left of a photograph.
///
/// Used for the carted count, and for nothing that is not a fact the backend
/// actually holds.
class PinBadge extends StatelessWidget {
  const PinBadge(this.label, {super.key, this.icon});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: LbmRadius.pillR,
        boxShadow: c.shadowSoft,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 12, color: c.ink2),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: LbmText.pinMeta.copyWith(
                color: c.ink2,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
