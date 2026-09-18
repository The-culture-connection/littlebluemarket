import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../app_assets.dart';
import '../data/repositories/dev_error_sink.dart';
import '../theme/tokens.dart';

/// The launch animation, held over the app for a moment after start-up.
///
/// Three pictures have to line up or the launch flickers:
///
/// 1. The phone's own launch screen (`launch_background.xml`,
///    `LaunchScreen.storyboard`): the cart icon centred on `splashBlue`. The
///    OS draws this before Flutter exists and it cannot animate.
/// 2. [LbmAssets.splash], the identical icon at the identical size, drawn
///    here the instant Flutter takes over. The hand-off from (1) is invisible.
/// 3. [LbmAssets.splashVideo], Grace's animation, faded in over (2) once the
///    player has warmed up, then the whole overlay fades and is removed.
///
/// The video is the only part that can be slow or absent, and it is the only
/// part layered on top, so every failure lands back on the still icon rather
/// than on a white screen. Reduce-motion skips the video entirely, as the
/// welcome intro does. Under test nothing is shown at all: a timer here would
/// fail every widget test.
class SplashOverlay extends StatefulWidget {
  const SplashOverlay({
    super.key,
    required this.child,
    this.hold = const Duration(milliseconds: 1500),
    this.fade = const Duration(milliseconds: 450),
  });

  final Widget child;

  /// How long the still icon is held when the animation does not play:
  /// reduce-motion is on, or the video failed. The original splash timing.
  final Duration hold;

  final Duration fade;

  /// The icon's size in logical pixels. Matches the native launch screens
  /// (200dp on Android, 200pt on iOS) so nothing jumps at the hand-off.
  static const double iconSize = 200;

  /// Nobody is stranded on the splash by a bad asset. Armed before the player
  /// is even asked to load, and replaced by the video's real length as soon
  /// as that is known.
  static const backstop = Duration(seconds: 6);

  /// A little margin past the last frame, rather than clipping it. The same
  /// reasoning as `kIntroDuration` on the welcome screen.
  static const tail = Duration(milliseconds: 200);

  /// The still icon dissolving into the animation's first frame.
  static const videoFadeIn = Duration(milliseconds: 250);

  @override
  State<SplashOverlay> createState() => _SplashOverlayState();
}

class _SplashOverlayState extends State<SplashOverlay> {
  bool _visible = !kUnderFlutterTest;
  bool _mounted = !kUnderFlutterTest;
  bool _started = false;
  bool _failed = false;

  Timer? _timer;
  VideoPlayerController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Started here rather than in initState because the decision needs
    // MediaQuery. Runs once.
    if (_started || !_mounted) return;
    _started = true;

    // Honour the platform's reduce-motion setting: the still icon, held for
    // the same moment the splash always held for, and no animation.
    if (MediaQuery.disableAnimationsOf(context)) {
      _dismissIn(widget.hold);
      return;
    }

    _dismissIn(SplashOverlay.backstop);
    unawaited(_playVideo());
  }

  Future<void> _playVideo() async {
    final controller = VideoPlayerController.asset(LbmAssets.splashVideo);
    try {
      await controller.initialize();
      if (!mounted || !_mounted) {
        await controller.dispose();
        return;
      }
      // Silent: phones block sound on autoplay anyway, and a noise on launch
      // would be unwelcome. One pass, not a loop.
      await controller.setVolume(0);
      await controller.setLooping(false);
      await controller.play();
      controller.addListener(_onPlayerChanged);
      setState(() => _controller = controller);
      // The countdown only starts once the real length is known, so a slow
      // warm-up cannot cut the animation short.
      _dismissIn(controller.value.duration + SplashOverlay.tail);
    } catch (error, stack) {
      DevErrorSink.report(error, stack, 'splash video');
      await controller.dispose();
      // Fall back to the still icon on the original timing.
      if (mounted && _mounted) _dismissIn(widget.hold);
    }
  }

  /// The player failing mid-play: give up on it and let the still icon show
  /// for what is left of the normal hold.
  ///
  /// Once only. `hasError` stays true, and the listener fires again for every
  /// change after it, so without the latch each one would re-arm the timer
  /// and the splash would never leave.
  void _onPlayerChanged() {
    final controller = _controller;
    if (controller == null || !controller.value.hasError || _failed) return;
    _failed = true;
    DevErrorSink.report(
      controller.value.errorDescription ?? 'unknown',
      null,
      'splash video',
    );
    _dismissIn(widget.hold);
  }

  void _dismissIn(Duration delay) {
    _timer?.cancel();
    _timer = Timer(delay, () {
      if (!mounted) return;
      setState(() => _visible = false);
      Future<void>.delayed(widget.fade, () {
        if (!mounted) return;
        setState(() => _mounted = false);
        // Nothing is on screen any more; give the decoder back.
        _disposeController();
      });
    });
  }

  void _disposeController() {
    final controller = _controller;
    if (controller == null) return;
    _controller = null;
    controller.removeListener(_onPlayerChanged);
    unawaited(controller.dispose());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _disposeController();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_mounted) return widget.child;
    final controller = _controller;
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
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // The phone's launch screen, continued. Always present, so
                  // the blue is never bare and the video has something to
                  // dissolve out of.
                  Center(
                    child: Image.asset(
                      LbmAssets.splash,
                      width: SplashOverlay.iconSize,
                      height: SplashOverlay.iconSize,
                      filterQuality: FilterQuality.medium,
                      semanticLabel: 'little blue market',
                    ),
                  ),
                  if (controller != null && controller.value.isInitialized)
                    // Letterboxed against the same blue it was drawn on, so
                    // the edges of the video cannot be seen on any shape of
                    // phone. TweenAnimationBuilder runs once, on the build
                    // that first shows the video.
                    TweenAnimationBuilder<double>(
                      tween: Tween<double>(begin: 0, end: 1),
                      duration: SplashOverlay.videoFadeIn,
                      curve: Curves.easeOut,
                      builder: (context, value, child) =>
                          Opacity(opacity: value, child: child),
                      child: Center(
                        child: AspectRatio(
                          aspectRatio: controller.value.aspectRatio,
                          child: VideoPlayer(controller),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
