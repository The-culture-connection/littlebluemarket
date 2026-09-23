import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/repositories/dev_error_sink.dart';
import '../models/models.dart';
import '../state/promos.dart';
import '../state/providers.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'primitives.dart';
import 'remote_image.dart';

/// Adverts and Little Blue announcements, as a card that fades in over the
/// app with everything behind it dimmed away.
///
/// Grace asked first for something "non abrasive", and then, having seen it,
/// for something "a bit more dramatic": the app behind greyed down, the popup
/// vibrant, the picture the thing your eye lands on (2026-09-14). So it is a
/// proper modal now rather than a card at the bottom of the screen, and the
/// cost of that is real: while it is up, the feed behind it does not scroll.
/// Non-abrasive is kept in how easily it goes: the X, the button, a tap
/// anywhere outside, a flick downwards, or twelve seconds of being ignored.
/// Still one per app opening, and never the same one twice.
///
/// Mounted in the `MaterialApp` builder inside `CartLayer`, which is why
/// it floats over every tab and a bug report's screenshot shows it.
class PromoLayer extends ConsumerStatefulWidget {
  const PromoLayer({super.key, required this.router, required this.child});

  final GoRouter router;
  final Widget child;

  /// Screens where a popup would be an intrusion: the welcome artwork and
  /// the account flows that follow it. Nobody signing up wants an advert.
  static const hiddenOn = {
    '/',
    '/welcome',
    '/signin',
    '/verify',
    '/setup',
    '/orient',
    '/delete-account',
  };

  /// How long after arriving on a real screen the card appears.
  static const delay = Duration(seconds: 3);

  /// How long it stays before fading out on its own.
  static const dwell = Duration(seconds: 12);

  static const fadeIn = Duration(milliseconds: 420);
  static const fadeOut = Duration(milliseconds: 260);

  @override
  ConsumerState<PromoLayer> createState() => _PromoLayerState();
}

class _PromoLayerState extends ConsumerState<PromoLayer> {
  Timer? _arrive;
  Timer? _leave;

  /// The promo being shown, once its turn has been taken.
  Promo? _showing;
  bool _visible = false;

  @override
  void dispose() {
    _arrive?.cancel();
    _leave?.cancel();
    super.dispose();
  }

  bool get _onAHiddenScreen {
    final path = widget.router.routerDelegate.currentConfiguration.uri.path;
    return PromoLayer.hiddenOn.contains(path);
  }

  /// Starts the clock, once, for the promo this launch has to offer.
  void _scheduleFor(Promo promo) {
    if (_showing != null || _arrive != null) return;
    _arrive = Timer(PromoLayer.delay, () {
      if (!mounted || _onAHiddenScreen) {
        // Still on a screen a popup has no business on. Let the next build
        // try again rather than burning this launch's one turn.
        _arrive = null;
        return;
      }
      ref.read(promoTurnTakenProvider.notifier).take();
      ref.read(promosSeenProvider.notifier).markSeen(promo.id);
      ref.read(promoRepositoryProvider).recordSeen(promo.id);
      setState(() {
        _showing = promo;
        _visible = true;
      });
      _leave = Timer(PromoLayer.dwell, _dismiss);
    });
  }

  /// Diagnostics asked for this one, now. None of the normal rules apply and
  /// nothing is counted: an impression logged while testing would be a lie
  /// in the advert's own numbers.
  void _showOverride(Promo promo) {
    _arrive?.cancel();
    _arrive = null;
    _leave?.cancel();
    setState(() {
      _showing = promo;
      _visible = true;
    });
    _leave = Timer(PromoLayer.dwell, _dismiss);
  }

  void _dismiss() {
    _leave?.cancel();
    _leave = null;
    // So the same one can be asked for again straight away.
    if (ref.read(promoOverrideProvider) != null) {
      ref.read(promoOverrideProvider.notifier).clear();
    }
    if (!mounted || !_visible) return;
    setState(() => _visible = false);
  }

  /// Removes the card once its fade has finished, so nothing invisible is
  /// left holding the screen.
  void _afterFade() {
    if (!mounted || _visible) return;
    setState(() => _showing = null);
  }

  Future<void> _tapCta(Promo promo) async {
    final uri = promo.ctaUri;
    _dismiss();
    if (uri == null) return;
    ref.read(promoRepositoryProvider).recordTap(promo.id);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) {
      messenger?.showSnackBar(SnackBar(content: Text('Could not open $uri')));
    }
  }

  @override
  Widget build(BuildContext context) {
    // Never under test: two timers pending at the end of a widget test is a
    // failure, and every test would inherit them from the app's own builder.
    if (kUnderFlutterTest) return widget.child;

    // Diagnostics can ask for one directly, which jumps the whole queue.
    final forced = ref.watch(promoOverrideProvider);
    if (forced != null && forced.id != _showing?.id) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && ref.read(promoOverrideProvider)?.id == forced.id) {
          _showOverride(forced);
        }
      });
    }

    final promo = ref.watch(promoForThisLaunchProvider).value;
    if (forced == null && promo != null && !_onAHiddenScreen) {
      _scheduleFor(promo);
    }

    final showing = _showing;
    if (showing == null) return widget.child;

    final c = context.c;
    final fade = _visible ? PromoLayer.fadeIn : PromoLayer.fadeOut;

    return Stack(
      children: [
        widget.child,
        // The app, greyed down to a dull dark grey so the blue underneath
        // goes quiet. c.ink was wrong twice over: a navy scrim rather than a
        // grey one, and nearly white in dark mode (Grace, 2026-09-14).
        Positioned.fill(
          child: IgnorePointer(
            ignoring: !_visible,
            child: GestureDetector(
              onTap: _dismiss,
              child: AnimatedOpacity(
                opacity: _visible ? 1 : 0,
                duration: fade,
                curve: Curves.easeOut,
                onEnd: _afterFade,
                child: ColoredBox(color: c.scrim),
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            ignoring: !_visible,
            child: AnimatedOpacity(
              opacity: _visible ? 1 : 0,
              duration: fade,
              curve: Curves.easeOut,
              child: AnimatedScale(
                // A whisper of a zoom on the way in; nothing bouncy.
                scale: _visible ? 1 : 0.96,
                duration: fade,
                curve: Curves.easeOutCubic,
                child: SafeArea(
                  child: PromoCard(
                    promo: showing,
                    onDismiss: _dismiss,
                    onCta: () => _tapCta(showing),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The card itself: the picture first, then who it is from, the title, the
/// caption and the button, with the way out above it.
///
/// Kept separate from [PromoLayer] so it can be pumped on its own, with no
/// timers and no backend, which is how it is tested.
class PromoCard extends StatefulWidget {
  const PromoCard({
    super.key,
    required this.promo,
    required this.onDismiss,
    required this.onCta,
  });

  final Promo promo;
  final VoidCallback onDismiss;
  final VoidCallback onCta;

  @override
  State<PromoCard> createState() => _PromoCardState();
}

class _PromoCardState extends State<PromoCard> {
  final _pages = PageController();
  int _page = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final promo = widget.promo;
    final isNews = promo.kind == PromoKind.announcement;
    final photos = promo.imageUrls;
    // The picture's share of the screen. Two fifths leaves room for a
    // 60-character title, a 180-character caption and the button on the
    // shortest phone we support, with nothing to scroll.
    final photoHeight = (MediaQuery.sizeOf(context).height * 0.4).clamp(
      180.0,
      420.0,
    );

    return Center(
      // Room for the X above, and never edge to edge on a small phone.
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _closeButton(c),
              Dismissible(
                  key: ValueKey('promo_${promo.id}'),
                  direction: DismissDirection.down,
                  onDismissed: (_) => widget.onDismiss(),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      // surface, not paper: paper is the app's cornflower
                      // background, so the card was blue on blue.
                      color: c.surface,
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: c.shadowLift,
                    ),
                    // A Material ancestor, the way LbmCard has one. Without
                    // it every Text here is painted with Flutter's
                    // missing-style marker, which is the gold underline
                    // under the title, the caption and the button
                    // (Grace, 2026-09-14).
                    child: Material(
                      type: MaterialType.transparency,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(22),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // The picture takes whatever height is left once
                            // the words have theirs, so the whole card fits
                            // at a glance with nothing to scroll.
                            if (photos.isNotEmpty)
                              SizedBox(
                                height: photoHeight,
                                child: _photos(photos, c),
                              ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(
                                18,
                                16,
                                18,
                                18,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    isNews
                                        ? 'FROM LITTLE BLUE MARKET'
                                        : 'SPONSORED',
                                    style: LbmText.tiny.copyWith(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.7,
                                      color: c.ink3,
                                    ),
                                  ),
                                  const SizedBox(height: 7),
                                  Text(
                                    promo.title,
                                    style: LbmText.display.copyWith(
                                      fontSize: 23,
                                      height: 1.15,
                                      color: c.ink,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    promo.caption,
                                    style: TextStyle(
                                      fontSize: 14.5,
                                      height: 1.5,
                                      color: c.ink2,
                                    ),
                                  ),
                                  if (promo.hasCta) ...[
                                    const SizedBox(height: 18),
                                    PillButton(
                                      promo.ctaLabel,
                                      onPressed: widget.onCta,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// The way out, on the dimmed app rather than inside the card, so the
  /// picture keeps the card's whole width.
  Widget _closeButton(LbmColors c) => Semantics(
    button: true,
    label: 'Dismiss',
    child: Tooltip(
      message: 'Dismiss',
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: c.shadowSoft,
          ),
          // The circle is its own Material: it floats on the dimmed app
          // with nothing above it, and an InkResponse with no Material
          // ancestor throws.
          child: Material(
            color: c.surface,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: widget.onDismiss,
              child: SizedBox(
                width: 38,
                height: 38,
                child: Icon(Icons.close_rounded, size: 21, color: c.ink),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  /// The picture, or a swipeable row of them with dots.
  ///
  /// Fills the height it is handed rather than forcing an aspect ratio: the
  /// card has to fit on screen without scrolling, so the words take what
  /// they need and the picture takes the rest. A 4:5 portrait is what the
  /// admin console asks for, which is the shape this flatters.
  Widget _photos(List<String> photos, LbmColors c) {
    if (photos.length == 1) {
      return RemoteImage(url: photos.first, fill: true, cacheWidth: 900);
    }
    return Stack(
      alignment: Alignment.bottomCenter,
      children: [
        Positioned.fill(
          child: PageView.builder(
            controller: _pages,
            itemCount: photos.length,
            onPageChanged: (i) => setState(() => _page = i),
            itemBuilder: (context, i) =>
                RemoteImage(url: photos[i], fill: true, cacheWidth: 900),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < photos.length; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == _page ? 18 : 7,
                  height: 7,
                  decoration: BoxDecoration(
                    // Over a photograph of any colour, so white, with a
                    // shadow to hold it apart from a pale picture.
                    // surface, not paper: paper is the app background.
                    color: i == _page
                        ? c.surface
                        : c.surface.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(4),
                    boxShadow: c.shadowSoft,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
