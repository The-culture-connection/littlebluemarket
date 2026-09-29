import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'primitives.dart';
import 'product_art.dart';

/// The three shapes the one slot at the top can take.
enum ToastVariant {
  /// A card: icon or photo, a line or two, one action.
  toast,

  /// A direct message: the sender's face, their name, what they said, and
  /// Reply.
  banner,

  /// "Quiet hours · 3 waiting": one line on a dark glass bar.
  quietStrip,
}

/// A small card that drops in at the top of the screen and leaves on its own.
///
/// It exists because the grid should never have to be left to find out that
/// something worked: adding to the cart from a pin used to push a snackbar up
/// from the bottom, behind the floating tab bar, under the thumb that had just
/// tapped. This lands where the eye already is, carries the photograph of the
/// thing that happened, and takes no decision to get rid of.
///
/// **One slot.** A second one replaces the first; two stacked is a
/// notification centre, which this is not. It carries the person's own
/// actions, and, through the choreography in `state/notifications_ui.dart`,
/// only the other people's events that are somebody talking *to them*: a DM
/// (as the banner), a mention, a reply, a post under a tag they follow.
/// Never an announcement: those have their popup and their banner.
abstract final class LbmToast {
  /// Where it hangs: clear of the status bar and the header row.
  static const _top = 58.0;

  /// Your own action: long enough to read a shop name, short enough not to
  /// sit over the pin you are already looking at.
  static const ownLinger = Duration(milliseconds: 2400);

  /// Somebody else's event, which takes a moment longer to take in.
  static const otherLinger = Duration(milliseconds: 3200);

  /// A DM, which people read to the end.
  static const bannerLinger = Duration(seconds: 4);

  static const _stripLinger = Duration(milliseconds: 2500);

  static OverlayEntry? _current;

  /// Shows [title], with an optional kicker, second line, thumbnail or icon,
  /// and one action. Replaces whatever is already up.
  static void show(
    BuildContext context, {
    required String title,
    String? subtitle,
    String? kicker,
    String? thumbnailUrl,
    IconData? icon,
    Widget? leading,
    (String label, VoidCallback onTap)? action,
    ToastVariant variant = ToastVariant.toast,
    Duration linger = ownLinger,
    VoidCallback? onGone,
  }) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    _dismissCurrent();

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => _Toast(
        title: title,
        subtitle: subtitle,
        kicker: kicker,
        thumbnailUrl: thumbnailUrl,
        icon: icon,
        leading: leading,
        action: action,
        variant: variant,
        linger: linger,
        onGone: () {
          if (_current == entry) _current = null;
          if (entry.mounted) entry.remove();
          onGone?.call();
        },
      ),
    );
    _current = entry;
    overlay.insert(entry);
  }

  /// A direct message, while the app is open.
  static void showBanner(
    BuildContext context, {
    required Widget avatar,
    required String name,
    required String message,
    required VoidCallback onReply,
    VoidCallback? onGone,
  }) => show(
    context,
    title: name,
    subtitle: message,
    leading: avatar,
    action: ('Reply', onReply),
    variant: ToastVariant.banner,
    linger: bannerLinger,
    onGone: onGone,
  );

  /// What quiet hours held back, said once.
  static void showQuietStrip(
    BuildContext context,
    String text, {
    VoidCallback? onGone,
  }) => show(
    context,
    title: text,
    variant: ToastVariant.quietStrip,
    linger: _stripLinger,
    onGone: onGone,
  );

  /// Takes down whatever is showing. Used when a second toast replaces it.
  static void _dismissCurrent() {
    final entry = _current;
    _current = null;
    if (entry != null && entry.mounted) entry.remove();
  }
}

class _Toast extends StatefulWidget {
  const _Toast({
    required this.title,
    required this.subtitle,
    required this.kicker,
    required this.thumbnailUrl,
    required this.icon,
    required this.leading,
    required this.action,
    required this.variant,
    required this.linger,
    required this.onGone,
  });

  final String title;
  final String? subtitle;
  final String? kicker;
  final String? thumbnailUrl;
  final IconData? icon;
  final Widget? leading;
  final (String label, VoidCallback onTap)? action;
  final ToastVariant variant;
  final Duration linger;
  final VoidCallback onGone;

  @override
  State<_Toast> createState() => _ToastState();
}

class _ToastState extends State<_Toast> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: LbmMotion.enter,
    reverseDuration: LbmMotion.exit,
  );
  Timer? _timer;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _controller.forward();
    _timer = Timer(widget.linger, _leave);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller
        ..duration = Duration.zero
        ..reverseDuration = Duration.zero;
    }
  }

  /// Runs the exit animation, then hands the entry back to be removed.
  ///
  /// Guarded because three things can start it: the timer, a swipe, and the
  /// action being tapped.
  Future<void> _leave() async {
    if (_leaving) return;
    _leaving = true;
    _timer?.cancel();
    if (mounted) await _controller.reverse();
    widget.onGone();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // In with the overshoot, dropping from above and swelling 3% past its
    // size before it settles; out quickly, straight back up.
    final drop = CurvedAnimation(
      parent: _controller,
      curve: LbmMotion.overshoot,
      reverseCurve: Curves.easeIn,
    );

    return Positioned(
      top: LbmToast._top,
      left: 14,
      right: 14,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, -1.4),
          end: Offset.zero,
        ).animate(drop),
        child: ScaleTransition(
          scale: Tween(begin: 0.9, end: 1.0).animate(drop),
          child: FadeTransition(
            opacity: CurvedAnimation(
              parent: _controller,
              curve: const Interval(0, 0.4),
            ),
            child: Material(
              type: MaterialType.transparency,
              child: GestureDetector(
                // Up, not sideways: it came down from the top edge, so
                // pushing it back the way it arrived is the gesture people
                // try.
                onVerticalDragEnd: (d) {
                  if ((d.primaryVelocity ?? 0) < 0) _leave();
                },
                child: switch (widget.variant) {
                  ToastVariant.quietStrip => _QuietStrip(text: widget.title),
                  _ => _card(context),
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _card(BuildContext context) {
    final c = context.c;
    final action = widget.action;
    final banner = widget.variant == ToastVariant.banner;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: const BorderRadius.all(Radius.circular(20)),
        boxShadow: c.shadowLift,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
        child: Row(
          children: [
            if (_leading(context) case final leading?) ...[
              // A shake of the head once it has landed.
              Bounce(
                kind: BounceKind.jiggle,
                delay: Duration(milliseconds: banner ? 300 : 250),
                child: leading,
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.kicker case final k? when k.isNotEmpty)
                    Text(
                      k.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: LbmText.pinMeta.copyWith(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.95,
                        color: c.ink3,
                      ),
                    ),
                  Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: LbmText.pinTitle.copyWith(
                      fontSize: banner ? 13 : 13.5,
                      color: c.ink,
                    ),
                  ),
                  if (widget.subtitle case final s?) ...[
                    const SizedBox(height: 1),
                    Text(
                      s,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: banner
                          ? LbmText.pinMeta.copyWith(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: c.ink,
                            )
                          : LbmText.pinMeta.copyWith(color: c.ink2),
                    ),
                  ],
                ],
              ),
            ),
            if (action != null) ...[
              const SizedBox(width: 8),
              if (banner)
                Bounce(
                  kind: BounceKind.hop,
                  delay: const Duration(milliseconds: 400),
                  child: _ReplyPill(
                    label: action.$1,
                    onTap: () {
                      _leave();
                      action.$2();
                    },
                  ),
                )
              else
                TextButton(
                  onPressed: () {
                    _leave();
                    action.$2();
                  },
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 32),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    action.$1,
                    style: LbmText.pinTitle.copyWith(color: c.skyDeep),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  /// The photograph, the icon tile, or the face, in that order of preference.
  Widget? _leading(BuildContext context) {
    final c = context.c;
    if (widget.leading case final leading?) return leading;
    final thumb = widget.thumbnailUrl;
    if (thumb != null && thumb.isNotEmpty) {
      return ClipRRect(
        borderRadius: const BorderRadius.all(Radius.circular(12)),
        child: SizedBox(
          width: 40,
          height: 40,
          child: ColoredBox(
            color: c.skyWash,
            child: ProductPhoto(
              url: thumb,
              cacheWidth: 120,
              fallback: ColoredBox(color: c.skyMist),
            ),
          ),
        ),
      );
    }
    if (widget.icon case final icon?) {
      return Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: c.accentMist,
          borderRadius: const BorderRadius.all(Radius.circular(12)),
        ),
        child: Icon(icon, size: 20, color: c.accentText),
      );
    }
    return null;
  }
}

/// The orchid-mist Reply on a DM banner.
class _ReplyPill extends StatelessWidget {
  const _ReplyPill({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          decoration: BoxDecoration(
            color: c.accentMist,
            borderRadius: LbmRadius.pillR,
          ),
          child: Text(
            label,
            style: LbmText.pinTitle.copyWith(fontSize: 12, color: c.accentText),
          ),
        ),
      ),
    );
  }
}

/// One line on dark glass: what quiet hours held back.
///
/// Fixed dark in both themes, like the chat pin, so it reads as the app
/// talking quietly rather than as another card.
class _QuietStrip extends StatelessWidget {
  const _QuietStrip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    const white = LbmConst.onGradient;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: LbmConst.chatInk.withValues(alpha: 0.85),
        borderRadius: const BorderRadius.all(Radius.circular(14)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.bedtime_rounded, size: 15, color: white),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              'Quiet hours · $text',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: LbmText.pinTitle.copyWith(fontSize: 12, color: white),
            ),
          ),
        ],
      ),
    );
  }
}
