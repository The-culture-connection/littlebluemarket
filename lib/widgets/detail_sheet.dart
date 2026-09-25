import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// How far the sheet is pulled up over the bottom of the picture.
const kDetailSheetOverlap = 26.0;

/// The picture at the top of a detail page, edge to edge.
///
/// No card, no margin, no corner radius: the photograph runs into all three
/// edges of the screen and the sheet below covers its bottom. A detail page
/// used to open on a photograph inside a white card inside blue paper, which
/// is three frames around one picture.
///
/// The controls float on top rather than sitting in an app bar, because an
/// app bar over a full-bleed image is a band of colour across the top of it.
class DetailGallery extends ConsumerWidget {
  const DetailGallery({
    super.key,
    required this.child,
    this.actions = const [],
    this.onBack,
  });

  /// The picture, usually a `ProductGallery`.
  final Widget child;

  /// Drawn as floating circles at the top right.
  final List<Widget> actions;

  final VoidCallback? onBack;

  /// Clear of the status bar without needing to know its height.
  static const _top = 50.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Stack(
      // Passthrough, so the picture gets the page's full width. A Stack hands
      // its non-positioned children loose constraints by default, which let
      // the photograph shrink to its own width and leave paper beside it.
      fit: StackFit.passthrough,
      children: [
        child,
        Positioned(
          top: _top,
          left: 12,
          right: 12,
          child: Row(
            children: [
              _FloatingCircle(
                icon: Icons.arrow_back_rounded,
                label: 'Back',
                onTap: onBack ?? () => _back(context),
              ),
              const Spacer(),
              for (final action in actions) ...[
                const SizedBox(width: 8),
                action,
              ],
            ],
          ),
        ),
      ],
    );
  }

  static void _back(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/market');
    }
  }
}

/// A round button floating over a photograph.
class FloatingCircleButton extends StatelessWidget {
  const FloatingCircleButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.badge = 0,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// A count in the corner. Zero draws nothing.
  final int badge;

  @override
  Widget build(BuildContext context) =>
      _FloatingCircle(icon: icon, label: label, onTap: onTap, badge: badge);
}

// There is deliberately no floating cart here. The mockup draws one over a
// detail page's picture, because the mockup's detail pages have no tab bar
// under them; this app keeps the tab bar on a pushed route, and its Cart tab
// already carries the count. Two carts on one screen is one too many.

class _FloatingCircle extends StatelessWidget {
  const _FloatingCircle({
    required this.icon,
    required this.label,
    required this.onTap,
    this.badge = 0,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final int badge;

  @override
  Widget build(BuildContext context) {
    final c = context.c;

    return Semantics(
      button: true,
      label: label,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Material(
            color: c.surface,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: SizedBox(
                width: 38,
                height: 38,
                child: Icon(icon, size: 19, color: c.ink),
              ),
            ),
          ),
          if (badge > 0)
            Positioned(
              top: -2,
              right: -2,
              child: Container(
                constraints: const BoxConstraints(minWidth: 17),
                padding: const EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 1,
                ),
                decoration: BoxDecoration(
                  color: c.accentDeep,
                  borderRadius: LbmRadius.pillR,
                  border: Border.all(color: c.surface, width: 1.5),
                ),
                child: Text(
                  '$badge',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    height: 1.3,
                    color: c.accentInk,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The white sheet that carries everything a detail page has to say.
///
/// Pulled up over the bottom of the picture by [kDetailSheetOverlap], which
/// is the whole trick: the photograph is not a thing on the page, the page
/// is a thing on the photograph.
class DetailSheet extends StatelessWidget {
  const DetailSheet({
    super.key,
    required this.children,
    this.padding = const EdgeInsets.fromLTRB(16, 18, 16, 16),
  });

  final List<Widget> children;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final c = context.c;

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        boxShadow: c.shadowLift,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }
}

/// Everything below the picture, lifted so the sheet covers its bottom edge.
///
/// One translate around the whole column rather than one around the sheet:
/// moving only the sheet would leave a 26 pixel band of picture showing
/// between it and whatever came next.
class DetailBody extends StatelessWidget {
  const DetailBody({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: const Offset(0, -kDetailSheetOverlap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }
}

/// A section under the sheet, sitting on the paper rather than on white.
class DetailSection extends StatelessWidget {
  const DetailSection({
    super.key,
    required this.title,
    required this.child,
    this.action,
  });

  final String title;

  /// A link on the right of the heading, e.g. "Write one" or "Their shop".
  final Widget? action;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.c;

    return Padding(
      // Negative top, because the sheet above has been pulled up and the
      // paper needs to close the gap it left.
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: LbmText.display.copyWith(
                      fontSize: 18,
                      color: c.ink,
                    ),
                  ),
                ),
                ?action,
              ],
            ),
          ),
          child,
        ],
      ),
    );
  }
}
