import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/models.dart';
import '../../router/nav.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../product_art.dart';

/// Opens an address outside the app: a website, a phone number, a map.
///
/// A provider rather than a bare `launchUrl` so a test can stand in for the
/// phone and see what would have been opened. Returns whether anything did.
typedef ExternalLauncher = Future<bool> Function(Uri uri);

final externalLauncherProvider = Provider<ExternalLauncher>(
  (ref) =>
      (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
);

/// How far the card leans, at rest. Zero when the phone asks for no motion.
const kCardTilt = -1.5 * math.pi / 180;

/// Card height over width, as a real 3.5 by 2 business card.
const kCardAspect = 1.75;

/// The ink border, top and bottom, which sits outside the card's minimum.
const _kCardBorder = 2.5 * 2;

/// About how tall a card of this width comes out, for anything that has to
/// reserve room before the listing has arrived.
///
/// **Close, and it cannot be exact.** The card is a minimum height wrapped
/// round intrinsic content, so a long business name, a third tag or a large
/// text size all make it taller. Reserving roughly the right room takes the
/// error from the ~140 pixels a generic placeholder was out by down to about
/// fifteen, and it is the sum of those errors that decides whether a fling
/// lands where the phone said it would (Grace, 2026-09-29: "slowly dragging
/// does work").
double directoryCardHeightFor(double width) =>
    width / kCardAspect + _kCardBorder;

/// A littlebluecart.com business in the feed, as a cartoon business card.
///
/// Full width and landscape, laid on the grid at a slight tilt with a strip
/// of tape along the top: a printed thing somebody left on the counter, not
/// one more white tile. Only the front is drawn. Grace's call (2026-09-28)
/// was that the back of the card (address, hours, directions, message) is
/// the listing's own page, which a tap on the card opens; the card itself
/// keeps to a photo, a name, two lines, two tags, a town and one button.
class DirectoryBusinessCard extends ConsumerStatefulWidget {
  const DirectoryBusinessCard({super.key, required this.listing, this.more});

  final DirectoryListing listing;

  /// The post's "more" menu (report, block), in the top corner. Null off the
  /// feed, where the card is not somebody's post.
  final Widget? more;

  @override
  ConsumerState<DirectoryBusinessCard> createState() =>
      _DirectoryBusinessCardState();
}

class _DirectoryBusinessCardState extends ConsumerState<DirectoryBusinessCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _wiggle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  );
  bool _pressed = false;

  /// The mockup's `wiggle` keyframes: from the resting lean, over to the
  /// other side and up a touch, back past rest, and settle.
  static final _lean = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: -1.5, end: 1.0), weight: 30),
    TweenSequenceItem(tween: Tween(begin: 1.0, end: -2.5), weight: 30),
    TweenSequenceItem(tween: Tween(begin: -2.5, end: -1.5), weight: 40),
  ]);
  static final _lift = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 0.0, end: -3.0), weight: 30),
    TweenSequenceItem(tween: Tween(begin: -3.0, end: 0.0), weight: 70),
  ]);

  @override
  void dispose() {
    _wiggle.dispose();
    super.dispose();
  }

  void _press(bool down) {
    if (_pressed == down) return;
    setState(() => _pressed = down);
    if (down && !MediaQuery.disableAnimationsOf(context)) {
      _wiggle.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.listing;
    final still = MediaQuery.disableAnimationsOf(context);

    return Semantics(
      button: true,
      label: '${l.title}, open the listing',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _press(true),
        onTapUp: (_) => _press(false),
        onTapCancel: () => _press(false),
        onTap: () => context.goToDirectoryListing(l.id),
        child: Padding(
          // Room for the tape above, the hard shadow below and right, and
          // the corners the lean pushes past the column.
          padding: const EdgeInsets.fromLTRB(6, 12, 10, 12),
          child: AnimatedScale(
            scale: _pressed ? 0.97 : 1,
            duration: still ? Duration.zero : const Duration(milliseconds: 120),
            child: AnimatedBuilder(
              animation: _wiggle,
              builder: (context, child) {
                final t = _wiggle.value;
                final moving = !still && _wiggle.isAnimating;
                final angle = still
                    ? 0.0
                    : moving
                    ? _lean.transform(t) * math.pi / 180
                    : kCardTilt;
                return Transform.translate(
                  offset: Offset(0, moving ? _lift.transform(t) : 0),
                  child: Transform.rotate(angle: angle, child: child),
                );
              },
              child: _CardFace(listing: l, more: widget.more),
            ),
          ),
        ),
      ),
    );
  }
}

class _CardFace extends StatelessWidget {
  const _CardFace({required this.listing, this.more});

  final DirectoryListing listing;
  final Widget? more;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final more = this.more;

    return LayoutBuilder(
      builder: (context, box) {
        final width = box.maxWidth;
        // At double-size type there is not room for two lines of blurb and a
        // "+N" as well as everything else; the card grows rather than
        // clipping, but it grows less if it gives those two up first.
        final big = MediaQuery.textScalerOf(context).scale(10) >= 17;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              decoration: BoxDecoration(
                color: c.cardStock,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: c.ink, width: 2.5),
                boxShadow: [
                  BoxShadow(
                    color: c.ink,
                    offset: const Offset(5, 6),
                    blurRadius: 0,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(11.5),
                // A minimum rather than an AspectRatio: at 1.0 the card is
                // exactly 1.75 wide to 1 tall, and at a large text size it is
                // allowed to grow instead of overflowing.
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: width / kCardAspect),
                  child: IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          width: width * 0.34,
                          child: _PhotoSide(listing: listing),
                        ),
                        Expanded(
                          child: _TextSide(
                            listing: listing,
                            big: big,
                            clearCorner: more != null,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // Washi tape, overhanging the top edge.
            Positioned(
              top: -8,
              left: 26,
              child: Transform.rotate(
                angle: -6 * math.pi / 180,
                child: Container(
                  width: 58,
                  height: 18,
                  decoration: BoxDecoration(
                    color: c.accent.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(
                      color: c.ink.withValues(alpha: 0.35),
                      width: 1.5,
                    ),
                  ),
                ),
              ),
            ),
            if (more != null) Positioned(top: 6, right: 8, child: more),
            // The hole punch.
            Positioned(
              left: 10,
              bottom: 10,
              child: Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: c.paper,
                  shape: BoxShape.circle,
                  border: Border.all(color: c.ink, width: 1.5),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The left third: the business's photo, its first category, and a stamp
/// for who owns it.
class _PhotoSide extends StatelessWidget {
  const _PhotoSide({required this.listing});

  final DirectoryListing listing;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final category = listing.categories.firstOrNull ?? '';

    return CustomPaint(
      painter: _DashedEdge(color: c.ink),
      child: Stack(
        children: [
          Center(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(6, 14, 8, 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListingPhoto(listing: listing, size: 58),
                  if (category.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      category.toUpperCase(),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.95,
                        height: 1.2,
                        color: c.ink2,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: _IdentityStamp(tags: listing.tags),
          ),
        ],
      ),
    );
  }
}

/// The round photo, or a tinted tile with the business's initials.
///
/// Public because the listing page draws the same thing at a larger size
/// when there is no photograph to run edge to edge.
class ListingPhoto extends StatelessWidget {
  const ListingPhoto({super.key, required this.listing, required this.size});

  final DirectoryListing listing;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final initials = ListingInitials(listing: listing, fontSize: size * 0.36);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: c.surface,
        border: Border.all(color: c.ink, width: 2.5),
        boxShadow: [
          BoxShadow(color: c.ink, offset: const Offset(3, 3), blurRadius: 0),
        ],
      ),
      child: ClipOval(
        child: listing.imageUrl.isEmpty
            ? initials
            : ProductPhoto(url: listing.imageUrl, fallback: initials),
      ),
    );
  }
}

/// A listing's initials on its tint, filling whatever box it is given.
class ListingInitials extends StatelessWidget {
  const ListingInitials({
    super.key,
    required this.listing,
    required this.fontSize,
  });

  final DirectoryListing listing;
  final double fontSize;

  /// "Found House Ceramics" → "FH". Words that are only punctuation, such
  /// as the "&" in "Cedar & Salt", do not count.
  static String of(String title) {
    final words = title
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty && RegExp(r'[A-Za-z0-9]').hasMatch(w[0]))
        .toList();
    if (words.isEmpty) return '?';
    return words.take(2).map((w) => w[0].toUpperCase()).join();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: LbmConst.makerTintFor(listing.id),
      child: Center(
        child: Text(
          of(listing.title),
          style: TextStyle(
            fontFamily: kDisplayFont,
            fontWeight: FontWeight.w700,
            fontSize: fontSize,
            height: 1,
            color: LbmConst.onGradient,
          ),
        ),
      ),
    );
  }
}

/// The dashed round stamp in the corner of the photo side.
///
/// Drawn with icons rather than the mockup's ♀ ✦ ★: Fraunces and Nunito do
/// not carry those, and a missing glyph is a box on somebody's phone.
class _IdentityStamp extends StatelessWidget {
  const _IdentityStamp({required this.tags});

  final List<String> tags;

  static IconData iconFor(List<String> tags) {
    bool has(String word) =>
        tags.any((t) => t.toLowerCase().contains(word.toLowerCase()));
    if (has('Woman')) return Icons.female_rounded;
    if (has('BIPOC')) return Icons.auto_awesome_rounded;
    if (has('LGBTQ')) return Icons.looks_rounded;
    return Icons.star_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Transform.rotate(
      angle: -14 * math.pi / 180,
      child: CustomPaint(
        painter: _DashedCircle(color: c.accentDeep),
        child: Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(color: c.surface, shape: BoxShape.circle),
          child: Icon(iconFor(tags), size: 14, color: c.accentDeep),
        ),
      ),
    );
  }
}

/// The right two thirds: name, two lines of blurb, two tags, town, Visit.
class _TextSide extends ConsumerWidget {
  const _TextSide({
    required this.listing,
    required this.big,
    required this.clearCorner,
  });

  final DirectoryListing listing;
  final bool big;

  /// Keep the name out from under the "more" dots in the corner.
  final bool clearCorner;

  /// Who owns it before what it sells: the ownership tags are what the
  /// directory is for.
  static List<String> orderedTags(List<String> tags) => [
    ...tags.where(_isIdentity),
    ...tags.where((t) => !_isIdentity(t)),
  ];

  static bool _isIdentity(String tag) => tag.toLowerCase().contains('owned');

  /// Where it is, in the directory's words first.
  static String locationOf(DirectoryListing l) {
    final label = l.locationLabel.replaceFirst('*', '').trim();
    if (label.isNotEmpty) return label;
    return [l.city, l.state].where((s) => s.isNotEmpty).join(', ');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final tags = orderedTags(listing.tags);
    final shown = tags.take(2).toList();
    final more = tags.length - shown.length;
    final location = locationOf(listing);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(right: clearCorner ? 16 : 0),
            child: Text(
              listing.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: LbmText.display.copyWith(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                height: 1.05,
                color: c.ink,
              ),
            ),
          ),
          if (listing.description.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              listing.description,
              key: const ValueKey('directory-card-description'),
              maxLines: big ? 1 : 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                height: 1.3,
                color: c.ink2,
              ),
            ),
          ],
          if (shown.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                for (final tag in shown) ...[
                  Flexible(child: _OutlinedChip(tag)),
                  const SizedBox(width: 4),
                ],
                if (more > 0 && !big) _OutlinedChip('+$more', plain: true),
              ],
            ),
          ],
          const Spacer(),
          const SizedBox(height: 6),
          CustomPaint(
            painter: _DottedRule(color: c.ink3),
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  if (location.isNotEmpty) ...[
                    Icon(Icons.place_rounded, size: 13, color: c.ink2),
                    const SizedBox(width: 2),
                    Expanded(
                      child: Text(
                        location,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: c.ink2,
                        ),
                      ),
                    ),
                  ] else
                    const Spacer(),
                  _VisitButton(listing: listing),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OutlinedChip extends StatelessWidget {
  const _OutlinedChip(this.label, {this.plain = false});

  final String label;

  /// The "+N" chip: white rather than the tint, so it reads as a count.
  final bool plain;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: plain ? c.surface : c.skyMist,
        borderRadius: LbmRadius.pillR,
        border: Border.all(color: c.ink, width: 1.5),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w900,
          height: 1.2,
          color: c.ink,
        ),
      ),
    );
  }
}

/// The one button: the business's own website, or failing that its page on
/// littlebluecart.com, or nothing.
class _VisitButton extends ConsumerWidget {
  const _VisitButton({required this.listing});

  final DirectoryListing listing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final website = listing.websiteUri;
    final target = website ?? listing.linkUri;
    if (target == null) return const SizedBox.shrink();
    final label = website != null ? 'Visit' : 'Listing';

    return Semantics(
      button: true,
      label: website != null
          ? 'Visit ${listing.title} website'
          : '${listing.title} on littlebluecart.com',
      excludeSemantics: true,
      child: GestureDetector(
        // Its own tap, so pressing it never also opens the listing page.
        behavior: HitTestBehavior.opaque,
        onTap: () => _open(context, ref, target),
        child: Container(
          margin: const EdgeInsets.only(left: 6),
          padding: const EdgeInsets.fromLTRB(10, 4, 8, 4),
          decoration: BoxDecoration(
            color: c.accentDeep,
            borderRadius: LbmRadius.pillR,
            border: Border.all(color: c.ink, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: c.ink,
                offset: const Offset(2, 2),
                blurRadius: 0,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w900,
                  color: c.accentInk,
                ),
              ),
              const SizedBox(width: 3),
              Icon(
                website != null
                    ? Icons.arrow_forward_rounded
                    : Icons.north_east_rounded,
                size: 12,
                color: c.accentInk,
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Future<void> _open(
    BuildContext context,
    WidgetRef ref,
    Uri uri,
  ) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final ok = await ref.read(externalLauncherProvider)(uri);
    if (!ok) {
      messenger?.showSnackBar(SnackBar(content: Text('Could not open $uri')));
    }
  }
}

/// The dashed line down the right edge of the photo side. Flutter's borders
/// are solid only.
class _DashedEdge extends CustomPainter {
  const _DashedEdge({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.5;
    final x = size.width - 1.25;
    for (var y = 0.0; y < size.height; y += 10) {
      canvas.drawLine(
        Offset(x, y),
        Offset(x, math.min(y + 6, size.height)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DashedEdge old) => old.color != color;
}

/// The dotted rule over the card's footer.
class _DottedRule extends CustomPainter {
  const _DottedRule({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    for (var x = 0.75; x < size.width; x += 4) {
      canvas.drawCircle(Offset(x, 0.75), 0.75, paint);
    }
  }

  @override
  bool shouldRepaint(_DottedRule old) => old.color != color;
}

/// A dashed ring, for the stamp.
class _DashedCircle extends CustomPainter {
  const _DashedCircle({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final rect = Offset.zero & size;
    const dashes = 12;
    const sweep = 2 * math.pi / dashes;
    for (var i = 0; i < dashes; i++) {
      canvas.drawArc(rect.deflate(1), i * sweep, sweep * 0.6, false, paint);
    }
  }

  @override
  bool shouldRepaint(_DashedCircle old) => old.color != color;
}
