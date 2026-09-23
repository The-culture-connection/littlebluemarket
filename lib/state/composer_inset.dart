import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// How much room a composer pinned along the bottom is taking right now.
///
/// The floating cart sits in the bottom right corner of every screen, and on a
/// screen that ends in a composer it has to be **above** the Send button
/// rather than on top of it. That was a list of route prefixes, and a list of
/// route prefixes is a thing that goes stale: it was reported wrong twice,
/// "fixed" once by guessing a route that did not exist, and was still wrong on
/// the post screen (Grace, 2026-09-23, with a photograph of the cart sitting
/// on Send).
///
/// So the composer says how tall it is instead. Nothing has to be listed, a
/// new screen with a composer is handled by having one, and the number is the
/// composer's real height rather than an estimate of it.
class ComposerInsetNotifier extends Notifier<double> {
  @override
  double build() => 0;

  /// Reported by the composer as it lays out, and again on the way out.
  ///
  /// Last writer wins, which is right: only one composer is ever on screen,
  /// and when one screen's composer replaces another's the new height is the
  /// one that matters. A composer leaving clears the inset only if nothing
  /// has claimed it since.
  void report(double height) {
    // Both of these arrive from a post-frame callback, which can outlive the
    // scope that owns this notifier — at the end of a test, or when the app
    // is torn down with a composer on screen.
    if (!ref.mounted || state == height) return;
    state = height;
  }

  void clear(double mine) {
    if (!ref.mounted || state != mine) return;
    state = 0;
  }
}

final composerInsetProvider = NotifierProvider<ComposerInsetNotifier, double>(
  ComposerInsetNotifier.new,
);

/// Reports its child's height into [composerInsetProvider] while it is on
/// screen. Draws nothing of its own.
class ComposerInsetReporter extends ConsumerStatefulWidget {
  const ComposerInsetReporter({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<ComposerInsetReporter> createState() =>
      _ComposerInsetReporterState();
}

class _ComposerInsetReporterState extends ConsumerState<ComposerInsetReporter> {
  final _key = GlobalKey();
  double _reported = 0;

  /// Held rather than reached for through `ref` at the end: `ref` is unsafe
  /// once the widget is on its way out, and the way out is exactly when the
  /// inset has to be cleared.
  ComposerInsetNotifier? _inset;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _inset = ref.read(composerInsetProvider.notifier);
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  /// Measured after layout, because that is the only moment the height is
  /// known, and written outside the build phase for the same reason.
  void _measure() {
    if (!mounted) return;
    final box = _key.currentContext?.findRenderObject() as RenderBox?;
    final height = box?.hasSize == true ? box!.size.height : 0.0;
    if (height == _reported) return;
    _reported = height;
    _inset?.report(height);
  }

  @override
  void dispose() {
    final notifier = _inset;
    final mine = _reported;
    // After the frame that removed this composer, so a screen that replaces
    // one composer with another does not blink back to zero in between.
    if (notifier != null && mine > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) => notifier.clear(mine));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Every rebuild may have changed the height: the keyboard opening, the
    // reader's text size, a composer that grew a second line.
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    return KeyedSubtree(key: _key, child: widget.child);
  }
}
