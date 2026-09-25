import 'package:flutter/material.dart';

import '../../models/feed_item.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../product_art.dart';

/// News from Little Blue Market.
///
/// Two shapes from one widget. The newest unread one is the [ThreadItem]-free
/// top of the feed: full width, a real headline, and the promo's photograph
/// bleeding in from the right if there is one. Every other announcement is
/// the same thing in a column, with a cart glyph ghosted behind the type
/// instead of a photograph.
class AnnouncementPin extends StatelessWidget {
  const AnnouncementPin({super.key, required this.item, this.onTap});

  final AnnouncementItem item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final a = item.announcement;
    final hero = item.hero;
    final photo = item.promo?.imageUrls.firstOrNull;
    final white = LbmConst.onGradient;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.all(Radius.circular(20)),
          gradient: LinearGradient(
            begin: const Alignment(-0.7, -0.9),
            end: const Alignment(0.7, 0.9),
            colors: c.heroGradient,
            stops: LbmColors.heroStops,
          ),
          boxShadow: c.shadowLift,
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.all(Radius.circular(20)),
          child: Stack(
            children: [
              if (hero && photo != null && photo.isNotEmpty)
                // Filled and then aligned, rather than a Positioned with no
                // left edge: that leaves the width unbounded, and a
                // FractionallySizedBox inside it asks for a fraction of
                // infinity.
                Positioned.fill(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: FractionallySizedBox(
                      widthFactor: 0.52,
                      heightFactor: 1,
                      child: ShaderMask(
                        // Fades the photograph into the gradient rather than
                        // butting it against the type. Under `dstIn` these
                        // two are an alpha ramp, not colours: nothing here is
                        // ever painted black, so no token applies.
                        shaderCallback: (rect) => const LinearGradient(
                          colors: [Colors.transparent, Colors.black],
                          stops: [0, 0.4],
                        ).createShader(rect),
                        blendMode: BlendMode.dstIn,
                        child: ProductPhoto(
                          url: photo,
                          fallback: const SizedBox.shrink(),
                        ),
                      ),
                    ),
                  ),
                )
              else if (!hero)
                Positioned(
                  right: -18,
                  top: -14,
                  child: Opacity(
                    opacity: 0.14,
                    child: Icon(
                      Icons.shopping_cart_outlined,
                      size: 120,
                      color: white,
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(18),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: hero ? 170 : 130),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'LITTLE BLUE MARKET',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: LbmText.pinMeta.copyWith(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.4,
                          color: white.withValues(alpha: 0.85),
                        ),
                      ),
                      const SizedBox(height: 6),
                      ConstrainedBox(
                        // Kept clear of the photograph fading in from the
                        // right. Without this the headline runs across it and
                        // the last word of it is unreadable.
                        constraints: BoxConstraints(
                          maxWidth: hero && photo != null && photo.isNotEmpty
                              ? 250
                              : double.infinity,
                        ),
                        child: Text(
                          a.title,
                          maxLines: hero ? 3 : 4,
                          overflow: TextOverflow.ellipsis,
                          style: hero
                              ? LbmText.headline.copyWith(color: white)
                              : LbmText.display.copyWith(
                                  fontSize: 18,
                                  height: 1.1,
                                  color: white,
                                ),
                        ),
                      ),
                      if (a.body.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: hero ? 250 : double.infinity,
                          ),
                          child: Text(
                            a.body,
                            maxLines: hero ? 3 : 4,
                            overflow: TextOverflow.ellipsis,
                            style: LbmText.pinMeta.copyWith(
                              fontSize: 13,
                              height: 1.4,
                              fontWeight: FontWeight.w600,
                              color: white.withValues(alpha: 0.92),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: white,
                          borderRadius: LbmRadius.pillR,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 9,
                          ),
                          child: Text(
                            'Take a look',
                            style: LbmText.pinTitle.copyWith(
                              color: c.accentText,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
