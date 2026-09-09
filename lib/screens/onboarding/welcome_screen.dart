import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app_assets.dart';
import '../../state/session.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';

/// How long the intro runs before the GIF is taken away.
///
/// The re-exported artwork (Grace's `Body.gif`, 2026-09-08) plays for 4070 ms
/// and stops on its resting frame; this leaves a little margin past the last
/// frame rather than clipping it. The timer does not start until the GIF's
/// first frame is on screen, so a slow decode cannot cut the animation short.
const kIntroDuration = Duration(milliseconds: 4190);

/// The artwork's own frame is 540 x 623: the animation with the painted
/// buttons cut off, since the buttons are real widgets now. The still and the
/// GIF are laid out in a box of exactly this ratio so they sit on top of each
/// other pixel for pixel.
const kWelcomeAspect = 540 / 623;

/// The welcome handoff.
///
/// The artwork (cart, bounce, wordmark) plays at the top; the still is its
/// exact final frame, drawn underneath in the same box, so when the GIF is
/// taken away nothing moves. The three buttons below it are ordinary widgets:
/// crisp at any size, readable by a screen reader, and tappable from the
/// first frame.
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
    // resting frame.
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

  /// Returning to the app.
  void _onSignIn() {
    _dismissIntro();
    context.push('/signin');
  }

  /// "Are you…", the seven doors.
  void _onCreateProfile() {
    _dismissIntro();
    context.push('/orient');
  }

  void _onGuest() {
    _dismissIntro();
    ref.read(sessionProvider.notifier).continueAsGuest();
    context.go('/market');
  }

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
        // The whole screen is the animation's own blue, so the artwork has no
        // visible edge and the buttons sit on the same ground.
        backgroundColor: LbmConst.welcomeBlue,
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: AspectRatio(
                    aspectRatio: kWelcomeAspect,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // The resting frame, underneath and always present.
                        Image.asset(
                          LbmAssets.welcomeStill,
                          fit: BoxFit.fill,
                          semanticLabel: 'little blue market',
                        ),
                        // The animation, on top, removed when it finishes.
                        if (_showIntro)
                          Image.asset(
                            LbmAssets.welcomeIntro,
                            fit: BoxFit.fill,
                            excludeFromSemantics: true,
                            frameBuilder: (context, child, frame, _) {
                              if (frame != null) _onFirstFrame();
                              return child;
                            },
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 8, 28, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _WelcomeButton(
                      label: 'Create a Profile',
                      onPressed: _onCreateProfile,
                    ),
                    const SizedBox(height: 12),
                    _WelcomeButton(
                      label: 'Sign in',
                      outlined: true,
                      onPressed: _onSignIn,
                    ),
                    const SizedBox(height: 6),
                    _QuietLink(
                      label: 'Continue as a guest',
                      onPressed: _onGuest,
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

/// The two big buttons: a filled slate pill and an outlined one, the same
/// shape the sign-in screens use, so the artwork and the forms read as one
/// flow.
class _WelcomeButton extends StatelessWidget {
  const _WelcomeButton({
    required this.label,
    required this.onPressed,
    this.outlined = false,
  });

  final String label;
  final VoidCallback onPressed;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: outlined ? Colors.transparent : LbmConst.slate,
        borderRadius: LbmRadius.pillR,
        border: outlined
            ? Border.all(color: LbmConst.onWelcome.withValues(alpha: 0.9), width: 1.6)
            : null,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onPressed,
          borderRadius: LbmRadius.pillR,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: kBodyFont,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: LbmConst.onWelcome,
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

class _QuietLink extends StatelessWidget {
  const _QuietLink({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        minimumSize: const Size.fromHeight(44),
        padding: const EdgeInsets.all(10),
        foregroundColor: LbmConst.onWelcome,
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: kBodyFont,
          fontSize: 13.5,
          fontWeight: FontWeight.w700,
          color: LbmConst.onWelcome.withValues(alpha: 0.88),
        ),
      ),
    );
  }
}
