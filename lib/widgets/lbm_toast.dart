import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'product_art.dart';

/// A small card that slides in at the top of the screen and leaves on its own.
///
/// It exists because the grid should never have to be left to find out that
/// something worked: adding to the cart from a pin used to push a snackbar up
/// from the bottom, behind the floating tab bar, under the thumb that had just
/// tapped. This lands where the eye already is, carries the photograph of the
/// thing that happened, and takes no decision to get rid of.
///
/// **Only for the person's own actions** — carted, reposted, review posted,
/// tag followed — and for a push that arrives while the app is open. Never for
/// other people's events; the bell is for those. A toast is an interruption,
/// and one the person did not cause is one they did not ask for.
abstract final class LbmToast {
  /// Where it hangs: clear of the status bar and the header row.
  static const _top = 58.0;

  /// Long enough to read a shop name, short enough not to sit over the pin
  /// the person is already looking at.
  static const _linger = Duration(milliseconds: 2400);
  static const _slideIn = Duration(milliseconds: 400);
  static const _slideOut = Duration(milliseconds: 200);

  static OverlayEntry? _current;

  /// Shows [title], with an optional second line, thumbnail and one action.
  ///
  /// A second call replaces whatever is already up: two toasts stacked is a
  /// notification centre, which this is not.
  static void show(
    BuildContext context, {
    required String title,
    String? subtitle,
    String? thumbnailUrl,
    (String label, VoidCallback onTap)? action,
  }) {
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;

    _dismissCurrent();

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => _Toast(
        title: title,
        subtitle: subtitle,
        thumbnailUrl: thumbnailUrl,
        action: action,
        onGone: () {
          if (_current == entry) _current = null;
          if (entry.mounted) entry.remove();
        },
      ),
    );
    _current = entry;
    overlay.insert(entry);
  }

  /// Takes down whatever is showing. Used when a second toast replaces it, and
  /// worth calling from a test's tearDown so an entry never outlives its
  /// overlay.
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
    required this.thumbnailUrl,
    required this.action,
    required this.onGone,
  });

  final String title;
  final String? subtitle;
  final String? thumbnailUrl;
  final (String label, VoidCallback onTap)? action;
  final VoidCallback onGone;

  @override
  State<_Toast> createState() => _ToastState();
}

class _ToastState extends State<_Toast> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: LbmToast._slideIn,
    reverseDuration: LbmToast._slideOut,
  );
  Timer? _timer;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _controller.forward();
    _timer = Timer(LbmToast._linger, _leave);
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
    final c = context.c;
    final action = widget.action;
    final thumb = widget.thumbnailUrl;

    final curve = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
      reverseCurve: Curves.easeIn,
    );

    return Positioned(
      top: LbmToast._top,
      left: 12,
      right: 12,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, -1.4),
          end: Offset.zero,
        ).animate(curve),
        child: FadeTransition(
          opacity: _controller,
          child: Material(
            type: MaterialType.transparency,
            child: GestureDetector(
              // Up, not sideways: the toast came down from the top edge, so
              // pushing it back the way it arrived is the gesture people try.
              onVerticalDragEnd: (d) {
                if ((d.primaryVelocity ?? 0) < 0) _leave();
              },
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: const BorderRadius.all(Radius.circular(18)),
                  boxShadow: c.shadowLift,
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
                  child: Row(
                    children: [
                      if (thumb != null && thumb.isNotEmpty) ...[
                        ClipRRect(
                          borderRadius: const BorderRadius.all(
                            Radius.circular(12),
                          ),
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
                        ),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              widget.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: LbmText.pinTitle.copyWith(
                                fontSize: 13.5,
                                color: c.ink,
                              ),
                            ),
                            if (widget.subtitle case final s?) ...[
                              const SizedBox(height: 1),
                              Text(
                                s,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: LbmText.pinMeta.copyWith(color: c.ink2),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (action != null) ...[
                        const SizedBox(width: 8),
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
              ),
            ),
          ),
        ),
      ),
    );
  }
}
