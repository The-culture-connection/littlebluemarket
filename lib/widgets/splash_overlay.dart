import 'package:flutter/material.dart';

import '../app_assets.dart';
import '../data/repositories/dev_error_sink.dart';
import '../theme/tokens.dart';

/// The splash artwork, held over the app for a moment after launch.
///
/// The native launch screen is the same blue, so the phone goes blue →
/// artwork → welcome without a flash. The artwork stays for [hold], then
/// fades and is removed from the tree entirely. Under test nothing is
/// shown: a timer here would fail every widget test.
class SplashOverlay extends StatefulWidget {
  const SplashOverlay({
    super.key,
    required this.child,
    this.hold = const Duration(milliseconds: 1500),
    this.fade = const Duration(milliseconds: 450),
  });

  final Widget child;
  final Duration hold;
  final Duration fade;

  @override
  State<SplashOverlay> createState() => _SplashOverlayState();
}

class _SplashOverlayState extends State<SplashOverlay> {
  bool _visible = !kUnderFlutterTest;
  bool _mounted = !kUnderFlutterTest;

  @override
  void initState() {
    super.initState();
    if (!_visible) return;
    Future<void>.delayed(widget.hold, () {
      if (!mounted) return;
      setState(() => _visible = false);
      Future<void>.delayed(widget.fade, () {
        if (mounted) setState(() => _mounted = false);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_mounted) return widget.child;
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        IgnorePointer(
          child: AnimatedOpacity(
            opacity: _visible ? 1 : 0,
            duration: widget.fade,
            curve: Curves.easeOut,
            child: ColoredBox(
              color: LbmConst.splashBlue,
              child: Image.asset(
                LbmAssets.splash,
                fit: BoxFit.cover,
                alignment: Alignment.center,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
