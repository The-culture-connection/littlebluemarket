import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/fixtures.dart';
import '../../state/session.dart';
import '../../theme/tokens.dart';

/// How long the intro runs before the GIF is taken away.
///
/// The prototype's script uses 4190 ms; the README's prose says 4070 ms. The
/// script value is the one that has actually been watched against the asset, so
/// it is the one used here — it leaves a little margin past the last frame
/// rather than clipping it. The timer does not start until the GIF's first
/// frame is on screen, so a slow decode cannot cut the animation short.
const kIntroDuration = Duration(milliseconds: 4190);

/// The animation's own resting frame is 540 x 960. Both images are laid out in
/// a box of exactly this ratio so they sit on top of each other pixel for
/// pixel.
const kWelcomeAspect = 540 / 960;

/// Where the buttons are in the artwork, as fractions of the image.
///
/// These are measured from the animation's resting frame. If the GIF is ever
/// re-exported these must be re-measured — nothing in the layout will tell you
/// they have drifted, the buttons will just stop working.
enum _Hotspot {
  signIn('Sign in', 0.184, 0.669, 0.651, 0.085),
  createProfile('Create a Profile', 0.184, 0.786, 0.653, 0.085),
  guest('Continue as a guest', 0.288, 0.900, 0.441, 0.042);

  const _Hotspot(this.label, this.left, this.top, this.width, this.height);

  final String label;
  final double left;
  final double top;
  final double width;
  final double height;
}

/// The smallest comfortable touch height. The "Continue as a guest" target is
/// only 4.2% of the artwork, which lands under this on a phone, so its touch
/// area is grown around its own centre. The rectangle above it is far enough
/// away that the two never overlap.
const _kMinTouchHeight = 44.0;

/// The welcome handoff.
///
/// The still is the GIF's exact final frame. Both are drawn in the same box, so
/// when the GIF is taken away nothing moves — the buttons simply become
/// tappable. The hotspots sit above both images, which also means an impatient
/// tap during the animation works rather than being swallowed.
class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key, this.playIntro = true});

  /// False when returning to this screen from sign-in, so the animation does
  /// not replay.
  final bool playIntro;

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  Timer? _timer;
  late bool _showIntro = widget.playIntro;
  bool _rebasedOnFirstFrame = false;

  @override
  void initState() {
    super.initState();
    // Armed up front so the intro always ends, even if the GIF never decodes.
    // Nobody should be stranded on the splash by a bad asset.
    if (_showIntro) _armTimer();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Honour the platform's reduce-motion setting: skip straight to the
    // resting frame, exactly as the prototype's prefers-reduced-motion rule
    // does.
    if (_showIntro && MediaQuery.disableAnimationsOf(context)) {
      _timer?.cancel();
      _showIntro = false;
    }
  }

  void _armTimer() {
    _timer?.cancel();
    _timer = Timer(kIntroDuration, () {
      if (mounted) setState(() => _showIntro = false);
    });
  }

  /// Re-bases the countdown on the moment the GIF's first frame actually
  /// painted, so a slow decode cannot cut the animation short. Runs once; the
  /// frame builder fires for every frame after that.
  void _onFirstFrame() {
    if (_rebasedOnFirstFrame) return;
    _rebasedOnFirstFrame = true;
    _armTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _dismissIntro() {
    _timer?.cancel();
    if (_showIntro) setState(() => _showIntro = false);
  }

  void _onSignIn() {
    _dismissIntro();
    context.push('/signin');
  }

  void _onCreateProfile() {
    _dismissIntro();
    context.push('/signin?create=1');
  }

  void _onGuest() {
    _dismissIntro();
    ref.read(sessionProvider.notifier).continueAsGuest();
    context.go('/market');
  }

  VoidCallback _actionFor(_Hotspot spot) => switch (spot) {
    _Hotspot.signIn => _onSignIn,
    _Hotspot.createProfile => _onCreateProfile,
    _Hotspot.guest => _onGuest,
  };

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: LbmConst.welcomeBlue,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        // The container is painted the animation's own blue, so the letterboxing
        // above and below the artwork is invisible.
        backgroundColor: LbmConst.welcomeBlue,
        body: SafeArea(
          bottom: false,
          child: Center(
            child: AspectRatio(
              aspectRatio: kWelcomeAspect,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final w = constraints.maxWidth;
                  final h = constraints.maxHeight;
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      // The resting frame, underneath and always present.
                      Image.asset(
                        Fx.still,
                        fit: BoxFit.fill,
                        semanticLabel:
                            'little blue market — sign in, create a profile, '
                            'or continue as a guest',
                      ),

                      // The animation, on top, removed when it finishes.
                      if (_showIntro)
                        Image.asset(
                          Fx.gif,
                          fit: BoxFit.fill,
                          excludeFromSemantics: true,
                          frameBuilder: (context, child, frame, _) {
                            if (frame != null) _onFirstFrame();
                            return child;
                          },
                        ),

                      // Invisible targets over the artwork's buttons. Above the
                      // GIF so they stay tappable while it plays.
                      for (final spot in _Hotspot.values)
                        _HotspotTarget(
                          spot: spot,
                          boxWidth: w,
                          boxHeight: h,
                          onTap: _actionFor(spot),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HotspotTarget extends StatelessWidget {
  const _HotspotTarget({
    required this.spot,
    required this.boxWidth,
    required this.boxHeight,
    required this.onTap,
  });

  final _Hotspot spot;
  final double boxWidth;
  final double boxHeight;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final left = spot.left * boxWidth;
    final width = spot.width * boxWidth;
    final drawnTop = spot.top * boxHeight;
    final drawnHeight = spot.height * boxHeight;

    // Grow the touch area around the artwork button's own centre when it is
    // smaller than a comfortable target. The drawn position never moves.
    final height = drawnHeight < _kMinTouchHeight
        ? _kMinTouchHeight
        : drawnHeight;
    final top = drawnTop - (height - drawnHeight) / 2;

    return Positioned(
      left: left,
      top: top,
      width: width,
      height: height,
      child: Semantics(
        button: true,
        label: spot.label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}
