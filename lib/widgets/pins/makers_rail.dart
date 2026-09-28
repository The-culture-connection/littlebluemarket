import 'package:flutter/material.dart';

import '../../models/feed_item.dart';
import '../../models/models.dart';
import '../../router/nav.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../primitives.dart';

/// A sideways rail of makers, full width across the grid.
///
/// Full width because a column of faces at 180 wide is a list, and a list of
/// people is what the directory already is. Sideways, it is a glance.
class MakersRail extends StatelessWidget {
  const MakersRail({super.key, required this.item, this.title = 'Makers near you'});

  final MakersRailItem item;

  final String title;

  /// Tall enough for the ring, the name and the place line.
  static const _height = 124.0;

  /// The same, with room for the two text lines to grow.
  ///
  /// The ring is a fixed 64 whatever the text does; only the name and the
  /// place scale, so the rail grows by what those two lines gain rather than
  /// by the whole card. Clamped, because past 1.6 the cards are taller than
  /// anything they sit next to and the rail stops being a glance.
  ///
  /// It was a flat 124, which fitted a maker with no place line and nothing
  /// else: every maker on the live market has a city, and at 2.0 the card
  /// overflowed by 5 pixels, which throws.
  static double heightFor(BuildContext context) {
    final scale = MediaQuery.textScalerOf(
      context,
    ).scale(1.0).clamp(1.0, 1.6);
    const textLines = 22.0;
    return _height + textLines * (scale - 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 0, 2, 10),
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: LbmText.display.copyWith(fontSize: 18, color: c.ink),
          ),
        ),
        SizedBox(
          height: heightFor(context),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 2),
            itemCount: item.sellers.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, i) => _Maker(person: item.sellers[i]),
          ),
        ),
      ],
    );
  }
}

class _Maker extends StatelessWidget {
  const _Maker({required this.person});

  final Person person;

  @override
  Widget build(BuildContext context) {
    final c = context.c;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => context.goToSeller(person.id),
      child: SizedBox(
        width: 96,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // The ring is the one place a gradient is purely decorative. It
            // makes a row of avatars read as people worth tapping rather than
            // as a row of coloured circles.
            Container(
              width: 64,
              height: 64,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [c.accent, c.sky],
                ),
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: c.paper, width: 3),
                ),
                child: Avatar(person, size: AvatarSize.sm),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              person.name,
              maxLines: 1,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: LbmText.pinMeta.copyWith(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: c.ink,
              ),
            ),
            if (person.cityState.isNotEmpty)
              Text(
                person.cityState,
                maxLines: 1,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: LbmText.pinMeta.copyWith(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: c.ink2,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
