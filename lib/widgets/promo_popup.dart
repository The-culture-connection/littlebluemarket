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

/// Adverts and Little Blue announcements, as a card that fades in over
/// whatever is on screen.
///
/// Grace's words were "non abrasive", and every decision here follows from
/// them. It never takes the screen: there is no barrier, so the feed behind
/// it keeps scrolling and every button behind it keeps working. It arrives
/// late enough not to fight the first paint, leaves on its own after twelve
/// seconds, and can be pushed away with the X or a flick downwards. One per
/// app opening, and never the same one twice.
///
/// Mounted in the `MaterialApp` builder beside [FeedbackLayer], which is why
/// it floats above sheets and tabs alike.
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

  static const fadeIn = Duration(milliseconds: 400);
  static const fadeOut = Duration(milliseconds: 300);

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

  void _dismiss() {
    _leave?.cancel();
    _leave = null;
    if (!mounted || !_visible) return;
    setState(() => _visible = false);
  }

  /// Removes the card from the tree once its fade has finished, so nothing
  /// invisible is left holding a hit-test region.
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
      messenger?.showSnackBar(
        SnackBar(content: Text('Could not open $uri')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Never under test: two timers pending at the end of a widget test is a
    // failure, and every test would inherit them from the app's own builder.
    if (kUnderFlutterTest) return widget.child;

    final promo = ref.watch(promoForThisLaunchProvider).value;
    if (promo != null && !_onAHiddenScreen) _scheduleFor(promo);

    final showing = _showing;
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;

    return Stack(
      children: [
        widget.child,
        if (showing != null && !keyboardOpen)
          Positioned(
            left: 0,
            right: 0,
            // Clear of the floating pill tab bar, the same measurement the
            // bug button uses.
            bottom: MediaQuery.viewPaddingOf(context).bottom + 96,
            child: AnimatedSlide(
              offset: Offset(0, _visible ? 0 : 0.18),
              duration: _visible ? PromoLayer.fadeIn : PromoLayer.fadeOut,
              curve: Curves.easeOutCubic,
              child: AnimatedOpacity(
                opacity: _visible ? 1 : 0,
                duration: _visible ? PromoLayer.fadeIn : PromoLayer.fadeOut,
                curve: Curves.easeOut,
                onEnd: _afterFade,
                child: PromoCard(
                  promo: showing,
                  onDismiss: _dismiss,
                  onCta: () => _tapCta(showing),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// The card itself: the photo, who it is from, the words, the button, an X.
///
/// Kept separate from [PromoLayer] so it can be pumped on its own, with no
/// timers and no backend, which is how it is tested.
class PromoCard extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final c = context.c;
    final isNews = promo.kind == PromoKind.announcement;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Dismissible(
        key: ValueKey('promo_${promo.id}'),
        direction: DismissDirection.down,
        onDismissed: (_) => onDismiss(),
        child: LbmCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (promo.hasPhoto)
                // Only the top corners: the card's own radius carries the
                // bottom two.
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(16),
                  ),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: promo.imageUrls.first.startsWith('asset://')
                        ? Image.asset(
                            promo.imageUrls.first.substring(8),
                            fit: BoxFit.cover,
                          )
                        : Image.network(
                            promo.imageUrls.first,
                            fit: BoxFit.cover,
                            cacheWidth: 900,
                            errorBuilder: (_, _, _) =>
                                ColoredBox(color: c.skyWash),
                          ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            isNews
                                ? 'FROM LITTLE BLUE MARKET'
                                : 'SPONSORED',
                            style: LbmText.tiny.copyWith(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.6,
                              color: c.ink3,
                            ),
                          ),
                        ),
                        // The way out, always in the same corner. The app's
                        // own icon button, tooltip and all, rather than a
                        // hand-rolled one: a bare Semantics wrapper around
                        // an Icon was silently merged into an ancestor node
                        // whenever the card had no CTA (found by test,
                        // 2026-09-14).
                        CircleIconButton(
                          icon: Icons.close_rounded,
                          bare: true,
                          tooltip: 'Dismiss',
                          size: 30,
                          iconSize: 18,
                          color: c.ink3,
                          onPressed: onDismiss,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Text(
                        promo.title,
                        style: LbmText.display.copyWith(
                          fontSize: 17,
                          color: c.ink,
                        ),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Text(
                        promo.caption,
                        style: TextStyle(
                          fontSize: 13.5,
                          height: 1.45,
                          color: c.ink2,
                        ),
                      ),
                    ),
                    if (promo.hasCta) ...[
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: PillButton(
                          promo.ctaLabel,
                          small: true,
                          expand: false,
                          onPressed: onCta,
                        ),
                      ),
                    ],
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
