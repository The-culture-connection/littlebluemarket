import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/repositories/dev_error_sink.dart' show kUnderFlutterTest;
import '../../models/feed_item.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';

/// The open chatroom, as a dark pin in the middle of the grid.
///
/// Dark on purpose: it is the one tile that is not a photograph and not a
/// white card, so a scroll past it registers as "something is happening over
/// there" without a label having to say so.
///
/// It never says how many people are in the room. There is no presence data
/// in this system, and the mockup's "23 here now" is a drawing. What it can
/// honestly say is how much was said in the last hour, which the messages
/// themselves answer.
class ChatPin extends StatelessWidget {
  const ChatPin({super.key, required this.item, this.onTap});

  final ChatItem item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final moment = item.moment;
    // Everything on this pin is fixed, because the tile it sits on is fixed.
    const white = LbmConst.onGradient;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap ?? () => context.go('/community'),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: const BoxDecoration(
          // Fixed, not themed: see [LbmConst.chatInk].
          color: LbmConst.chatInk,
          borderRadius: LbmRadius.imageR,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const _LiveDot(),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'OPEN CHAT',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: LbmText.pinMeta.copyWith(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.3,
                      color: white.withValues(alpha: 0.85),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final message in moment.latest.take(2)) ...[
              _Bubble(text: message.text, color: white),
              const SizedBox(height: 6),
            ],
            if (moment.latest.isEmpty)
              _Bubble(text: 'Nobody has said anything yet.', color: white),
            const SizedBox(height: 4),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 6,
              children: [
                Text(
                  moment.isQuiet
                      ? 'Quiet in here'
                      : '${moment.lastHourCount} in the last hour',
                  style: LbmText.pinMeta.copyWith(
                    fontWeight: FontWeight.w800,
                    color: white.withValues(alpha: 0.8),
                  ),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: white,
                    borderRadius: LbmRadius.pillR,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    child: Text(
                      'Jump in',
                      style: LbmText.pinMeta.copyWith(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w900,
                        // Against the fixed tile, not the theme's ink, which
                        // would go white-on-white in dark mode.
                        color: LbmConst.chatInk,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A translucent chat bubble, squared off at the bottom-left like the ones in
/// the room itself.
class _Bubble extends StatelessWidget {
  const _Bubble({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(14),
          topRight: Radius.circular(14),
          bottomRight: Radius.circular(14),
          bottomLeft: Radius.circular(4),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Text(
          text,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: LbmText.pinMeta.copyWith(
            fontSize: 12.5,
            height: 1.35,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ),
    );
  }
}

/// The sage dot that breathes, so the pin reads as live without claiming a
/// number it does not have.
class _LiveDot extends StatefulWidget {
  const _LiveDot();

  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
    // Held at full brightness under test. A repeating animation never lets
    // `pumpAndSettle` return, and it is called on every one of the smoke
    // test's routes; the pulse is decoration, the deadlock would not be.
    value: 1,
  );

  @override
  void initState() {
    super.initState();
    if (!kUnderFlutterTest) _controller.repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sage = context.c.sage;
    return FadeTransition(
      opacity: Tween(begin: 0.45, end: 1.0).animate(_controller),
      child: Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(color: sage, shape: BoxShape.circle),
      ),
    );
  }
}
