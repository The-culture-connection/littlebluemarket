import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/repositories/dev_error_sink.dart' show kUnderFlutterTest;
import '../models/models.dart';
import '../state/promos.dart';
import '../state/providers.dart';
import '../state/session.dart';
import '../state/tips.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'product_art.dart';
import 'tips.dart' show showCartTipOnce;

/// What one card in the banner says and where tapping it goes.
@immutable
class HeroCard {
  const HeroCard({
    required this.id,
    required this.kicker,
    required this.title,
    required this.body,
    required this.cta,
    required this.onTap,
    this.imageUrl,
  });

  final String id;
  final String kicker;
  final String title;
  final String body;
  final String cta;
  final String? imageUrl;
  final void Function(BuildContext context, WidgetRef ref) onTap;
}

/// The day's news, across the top of the feed.
///
/// One fixed-height banner that rotates rather than a pin in the grid. As a
/// pin it took a column's width and came out square, and it changed size
/// depending on whether it had been read (Grace, with a screenshot). It is
/// the same shape every time now, and it scrolls with the grid rather than
/// pinning itself above it, because it is news rather than a toolbar.
///
/// It carries every announcement aimed at this person and every live promo,
/// in that order: the market's own words first, then what is being sold.
class HeroBanner extends ConsumerStatefulWidget {
  const HeroBanner({super.key});

  /// Fixed, so the grid underneath starts in the same place whatever the
  /// banner happens to be saying today.
  static const height = 196.0;

  /// The same height for everyone reading at a normal size, and taller for
  /// anyone who has turned their text up.
  ///
  /// "The same size every time" is about the banner not changing shape from
  /// one announcement to the next; it was never meant to mean a box that
  /// three lines of large type overflow out of.
  static double heightFor(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.8);
    return height * scale;
  }

  /// Long enough to read a headline and look at the picture.
  static const rotation = Duration(seconds: 7);

  /// The in-app path a CTA means, or null when there is nothing to open.
  ///
  /// An admin types these by hand on the website, so they arrive as anything:
  /// an in-app path, a full URL to the app's own site, somebody else's
  /// website, or nothing at all. Only the first two open, and the rest do
  /// nothing rather than landing on a blank screen.
  static String? normaliseRoute(String target) {
    final trimmed = target.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.startsWith('/')) return trimmed;

    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;
    // A link to the app's own site is a route in disguise; anything else is
    // somebody else's website, which a banner does not open.
    if (!uri.host.contains('littleblue')) return null;
    final path = uri.path;
    return path.isEmpty || path == '/' ? '/market' : path;
  }

  @override
  ConsumerState<HeroBanner> createState() => _HeroBannerState();
}

class _HeroBannerState extends ConsumerState<HeroBanner> {
  final _controller = PageController();
  Timer? _timer;
  int _page = 0;
  int _count = 0;

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  /// Restarted whenever the number of cards changes, and never armed under
  /// test: a repeating timer stops `pumpAndSettle` ever returning.
  void _arm(int count) {
    if (count == _count) return;
    _count = count;
    _timer?.cancel();
    if (count < 2 || kUnderFlutterTest) return;
    _timer = Timer.periodic(HeroBanner.rotation, (_) {
      if (!mounted || !_controller.hasClients) return;
      final next = (_page + 1) % _count;
      _controller.animateToPage(
        next,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final cards = _cards(ref);
    _arm(cards.length);
    if (cards.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: HeroBanner.heightFor(context),
      child: Stack(
        children: [
          PageView.builder(
            controller: _controller,
            itemCount: cards.length,
            onPageChanged: (i) => setState(() => _page = i),
            itemBuilder: (context, i) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: _HeroCardView(card: cards[i]),
            ),
          ),
          if (cards.length > 1)
            Positioned(
              bottom: 10,
              left: 0,
              right: 0,
              child: _Dots(count: cards.length, active: _page),
            ),
        ],
      ),
    );
  }

  /// Everything worth putting in the banner today, newest first.
  List<HeroCard> _cards(WidgetRef ref) {
    final isGuest = ref.watch(isGuestProvider);

    if (isGuest) {
      // A guest has no announcements and no bell. What they need explaining
      // is why there is nowhere to press "like".
      if (ref.watch(tipsProvider).contains(Tips.cartIsTheLike)) return const [];
      return [
        HeroCard(
          id: 'tip:cartIsTheLike',
          kicker: 'From Little Blue Market',
          title: 'No likes here. Just carts.',
          body: 'Tap the cart on anything you love. Makers see it, and your '
              'cart keeps it.',
          cta: 'Show me',
          onTap: showCartTipOnce,
        ),
      ];
    }

    final announcements = ref.watch(announcementsProvider).value ?? const [];
    final promos = ref.watch(allPromosProvider).value ?? const [];
    final isSeller = ref.watch(isSellerProvider);
    final linked = ref.watch(directoryLinkProvider).value?.linked ?? false;

    return [
      for (final a in announcements)
        HeroCard(
          id: 'a:${a.id}',
          kicker: 'From Little Blue Market',
          title: a.title,
          body: a.body,
          cta: 'Take a look',
          onTap: (context, ref) => _goTo(context, a.route),
        ),
      for (final promo in promos)
        if (promo.showsTo(isSeller: isSeller, directoryLinked: linked))
          HeroCard(
            id: 'p:${promo.id}',
            kicker: promo.kind == PromoKind.announcement
                ? 'From Little Blue Market'
                : 'Today in the market',
            title: promo.title,
            body: promo.caption,
            cta: promo.ctaLabel.isEmpty ? 'Take a look' : promo.ctaLabel,
            imageUrl: promo.imageUrls.firstOrNull,
            onTap: (context, ref) => _goTo(context, promo.ctaUrl),
          ),
    ];
  }

  /// Sends a tap where the card says it goes.
  ///
  /// An admin types these by hand on the website, so they arrive as anything:
  /// an in-app path, a full URL to the app's own domain, or nothing at all.
  /// Anything that is not a route this app has lands on the Market rather
  /// than on a blank screen.
  static void _goTo(BuildContext context, String target) {
    final route = HeroBanner.normaliseRoute(target);
    if (route == null) return;
    context.go(route);
  }
}

class _HeroCardView extends ConsumerWidget {
  const _HeroCardView({required this.card});

  final HeroCard card;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    const white = LbmConst.onGradient;
    final photo = card.imageUrl;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => card.onTap(context, ref),
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
              if (photo != null && photo.isNotEmpty)
                Positioned.fill(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: FractionallySizedBox(
                      widthFactor: 0.52,
                      heightFactor: 1,
                      child: ShaderMask(
                        // Fades the photograph into the gradient rather than
                        // butting it against the type. Under `dstIn` these
                        // two are an alpha ramp, not colours.
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
              else
                Positioned(
                  right: -18,
                  top: -14,
                  child: Opacity(
                    opacity: 0.14,
                    child: Icon(
                      Icons.shopping_cart_outlined,
                      size: 150,
                      color: white,
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      card.kicker.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: LbmText.pinMeta.copyWith(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.4,
                        color: white.withValues(alpha: 0.85),
                      ),
                    ),
                    const SizedBox(height: 5),
                    // Held clear of the photograph fading in from the right.
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 235),
                      child: Text(
                        card.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: LbmText.headline.copyWith(
                          fontSize: 26,
                          color: white,
                        ),
                      ),
                    ),
                    if (card.body.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 235),
                        child: Text(
                          card.body,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: LbmText.pinMeta.copyWith(
                            fontSize: 12.5,
                            height: 1.35,
                            fontWeight: FontWeight.w600,
                            color: white.withValues(alpha: 0.92),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    DecoratedBox(
                      decoration: const BoxDecoration(
                        color: white,
                        borderRadius: LbmRadius.pillR,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 15,
                          vertical: 8,
                        ),
                        child: Text(
                          card.cta,
                          style: LbmText.pinTitle.copyWith(
                            fontSize: 12.5,
                            color: c.accentText,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.active});

  final int count;
  final int active;

  @override
  Widget build(BuildContext context) {
    const white = LbmConst.onGradient;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(horizontal: 2.5),
            width: i == active ? 16 : 6,
            height: 6,
            decoration: BoxDecoration(
              color: white.withValues(alpha: i == active ? 1 : 0.55),
              borderRadius: LbmRadius.pillR,
            ),
          ),
      ],
    );
  }
}
