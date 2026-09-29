import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/dev_error_sink.dart';
import '../data/repositories/repositories.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'primitives.dart';

/// User-facing copy for a failure.
///
/// The rule this exists to keep: an exception string never reaches a person.
/// Every repository throws one of the types in `exceptions.dart`, and this is
/// the single place those become sentences.
({String title, String body}) describeError(Object error) {
  return switch (error) {
    OfflineException() => (
      title: 'No connection',
      body: 'Check your signal and try again.',
    ),
    NotFoundException(:final kind) => (
      title: 'Not here',
      body: 'That $kind may have been removed.',
    ),
    UnauthenticatedException() => (
      title: 'Sign in to see this',
      body: 'You need a profile for this part of the market.',
    ),
    PermissionException() => (
      title: "You can't open this",
      body: 'This belongs to someone else.',
    ),
    RateLimitException() => (
      title: 'Too fast',
      body: 'Give it a moment and try again.',
    ),
    ValidationException(:final message) => (
      title: "That didn't work",
      body: message,
    ),
    BackendException() => (
      title: 'Something went wrong',
      body: 'That is on us. Try again in a moment.',
    ),
    _ => (
      title: 'Something went wrong',
      body: 'That is on us. Try again in a moment.',
    ),
  };
}

/// Renders an [AsyncValue] with the app's loading, error and empty conventions.
///
/// One widget instead of a `.when()` in twenty screens, because three rules
/// need to hold everywhere and would not survive being retyped each time:
///
///  1. **Stale data stays on screen while refreshing.** The skeleton shows only
///     on a first load. A refresh keeps what is already there and marks itself
///     with a hairline bar — this design has no blank state to fall back to, so
///     blanking a populated screen on every pull-to-refresh looks broken.
///  2. **Errors are copy.** [describeError] turns the exception into a sentence
///     and offers one action.
///  3. **Empty is a first-class state**, not something each screen invents. The
///     prototype never needed one because its search could not return nothing.
class LbmAsync<T> extends StatelessWidget {
  const LbmAsync(
    this.value, {
    super.key,
    required this.data,
    this.skeleton,
    this.empty,
    this.isEmpty,
    this.onRetry,
    this.errorBuilder,
  });

  final AsyncValue<T> value;
  final Widget Function(T value) data;

  /// Shown only on a first load. Defaults to a modest inline placeholder.
  final Widget? skeleton;

  /// Shown when [isEmpty] says the loaded value has nothing in it.
  final Widget? empty;
  final bool Function(T value)? isEmpty;

  /// Usually `() => ref.invalidate(theProvider)`.
  final VoidCallback? onRetry;

  final Widget Function(Object error, VoidCallback? retry)? errorBuilder;

  @override
  Widget build(BuildContext context) {
    // Order matters. `hasValue` is checked before `isLoading` so a refresh over
    // existing data keeps rendering it.
    if (value.hasValue) {
      final loaded = value.requireValue;
      final showEmpty = isEmpty?.call(loaded) ?? false;
      final body = showEmpty
          ? (empty ?? const LbmEmpty(title: 'Nothing here yet'))
          : data(loaded);

      // Always the same shape, whether or not a refresh is happening.
      //
      // This used to return `body` on its own and wrap it in the overlay only
      // while refreshing. Swapping between a bare child and a Stack changes
      // the element tree, so everything inside is unmounted and built again —
      // and a scroll view rebuilt that way gets a **new ScrollPosition**,
      // which restores the offset it last saved. On the feed that is a fling
      // snapping back to where it started, once per refresh (Grace,
      // 2026-09-29, with a screen recording).
      //
      // The hairline is drawn or not; the tree around it does not move.
      return _RefreshingOverlay(
        refreshing: value.isLoading,
        // Stale data plus a failed refresh: keep the content, say so quietly.
        failed: value.hasError,
        child: body,
      );
    }

    if (value.hasError) {
      final retry = onRetry;
      final builder = errorBuilder;
      if (builder != null) return builder(value.error!, retry);
      return LbmErrorCard(error: value.error!, onRetry: retry);
    }

    return skeleton ?? const _DefaultSkeleton();
  }
}

/// A hairline that marks a refresh happening over content already on screen.
///
/// Always present, and drawn only when there is something to say. The slot
/// has to exist either way: a widget that appears and disappears around the
/// content rebuilds the content with it, and a rebuilt scroll view loses its
/// place. See the note in [LbmAsync.build].
class _RefreshingOverlay extends StatelessWidget {
  const _RefreshingOverlay({
    required this.child,
    this.refreshing = false,
    this.failed = false,
  });

  final Widget child;
  final bool refreshing;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Stack(
      children: [
        child,
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: SizedBox(
              height: 2,
              child: !refreshing && !failed
                  ? const SizedBox.shrink()
                  : failed
                  ? ColoredBox(color: c.clay.withValues(alpha: 0.7))
                  : LinearProgressIndicator(
                      minHeight: 2,
                      backgroundColor: Colors.transparent,
                      valueColor: AlwaysStoppedAnimation(c.accent),
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The failure state: what happened, and the one thing to do about it.
class LbmErrorCard extends StatelessWidget {
  const LbmErrorCard({super.key, required this.error, this.onRetry});

  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final described = describeError(error);

    return LbmCard(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            described.title,
            style: LbmText.display.copyWith(fontSize: 16, color: c.ink),
          ),
          const SizedBox(height: 6),
          Text(
            described.body,
            style: TextStyle(fontSize: 13.5, height: 1.55, color: c.ink2),
          ),
          // The raw cause, for whoever is building the app. Only a developer
          // build (LBM_DEV=true) shows it; the copy above is what a person sees.
          if (kLbmDev && !kUnderFlutterTest) ...[
            const SizedBox(height: 8),
            Text(
              _rawCause(error),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, height: 1.4, color: c.clay),
            ),
          ],
          if (onRetry != null) ...[
            const SizedBox(height: 16),
            PillButton(
              'Try again',
              style: PillStyle.ghost,
              small: true,
              expand: false,
              onPressed: onRetry,
            ),
          ],
        ],
      ),
    );
  }
}

String _rawCause(Object error) {
  final report = DevErrorReport(error: error);
  final cause = error is RepositoryException ? error.cause : null;
  final code = report.code;
  final head = code == null ? report.typeName : '${report.typeName} · $code';
  return cause == null ? '$head: ${report.message}' : '$head: $cause';
}

/// The empty state. A sentence about what would fill this, not an apology.
class LbmEmpty extends StatelessWidget {
  const LbmEmpty({
    super.key,
    required this.title,
    this.body,
    this.action,
    this.compact = false,
  });

  final String title;
  final String? body;
  final Widget? action;

  /// For an empty section inside a screen that has other content.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: 20,
        vertical: compact ? 18 : 40,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: LbmText.display.copyWith(
              fontSize: compact ? 14.5 : 17,
              color: c.ink,
            ),
          ),
          if (body != null) ...[
            const SizedBox(height: 6),
            Text(
              body!,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, height: 1.55, color: c.ink2),
            ),
          ],
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    );
  }
}

class _DefaultSkeleton extends StatelessWidget {
  const _DefaultSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: 24),
      child: Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}
