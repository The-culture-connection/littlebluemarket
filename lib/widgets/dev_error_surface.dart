import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';
import '../state/dev_errors.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'primitives.dart';
import 'sheets.dart';

/// The dev-only strip that says what just failed.
///
/// A release build shows the friendly copy from `describeError` and nothing
/// else. While the app is being built that hides exactly the thing the person
/// testing it needs: the function name, the code, the message. This overlays
/// the newest failure at the top of every screen, with a button that copies a
/// bug report to the clipboard. Off in release, off under `flutter test`.
class DevErrorSurface extends ConsumerWidget {
  const DevErrorSurface({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(devSurfaceEnabledProvider)) return child;

    final errors = ref.watch(devErrorsProvider);
    if (errors.isEmpty) return child;

    return Stack(
      children: [
        child,
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            bottom: false,
            child: _ErrorStrip(entry: errors.last, count: errors.length),
          ),
        ),
      ],
    );
  }
}

class _ErrorStrip extends ConsumerStatefulWidget {
  const _ErrorStrip({required this.entry, required this.count});

  final DevErrorEntry entry;
  final int count;

  @override
  ConsumerState<_ErrorStrip> createState() => _ErrorStripState();
}

class _ErrorStripState extends ConsumerState<_ErrorStrip> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: formatForClaude(widget.entry)));
    if (!mounted) return;
    setState(() => _copied = true);
  }

  @override
  void didUpdateWidget(covariant _ErrorStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entry != widget.entry) _copied = false;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final entry = widget.entry;

    return Material(
      type: MaterialType.transparency,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
        child: LbmCard(
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
          onTap: () => _showAll(context),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 4,
                height: 44,
                margin: const EdgeInsets.only(right: 10, top: 2),
                decoration: BoxDecoration(
                  color: c.clay,
                  borderRadius: LbmRadius.pillR,
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.count > 1
                          ? 'DEV · ${entry.headline} · +${widget.count - 1} more'
                          : 'DEV · ${entry.headline}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: LbmText.tiny.copyWith(
                        fontFamily: kBodyFont,
                        fontWeight: FontWeight.w800,
                        color: c.clay,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      entry.report.message,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: LbmText.xtiny.copyWith(color: c.ink),
                    ),
                    const SizedBox(height: 6),
                    // Wrap, not Row: at 2.0 text scale two pills do not fit
                    // on one line, and an overflow stripe on the error strip
                    // would be a poor joke.
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        PillButton(
                          _copied ? 'Copied' : 'Copy for Claude',
                          small: true,
                          expand: false,
                          style: PillStyle.solid,
                          onPressed: _copy,
                        ),
                        PillButton(
                          'Dismiss',
                          small: true,
                          expand: false,
                          style: PillStyle.ghost,
                          onPressed: () => ref
                              .read(devErrorsProvider.notifier)
                              .dismissLatest(),
                        ),
                      ],
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

  void _showAll(BuildContext context) {
    showLbmSheet<void>(context, (sheetContext) => const _DevErrorList());
  }
}

class _DevErrorList extends ConsumerWidget {
  const _DevErrorList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final errors = ref.watch(devErrorsProvider).reversed.toList();

    return LbmSheet(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Recent failures (dev)',
                style: LbmText.display.copyWith(fontSize: 18, color: c.ink),
              ),
            ),
            PillButton(
              'Clear',
              small: true,
              expand: false,
              style: PillStyle.ghost,
              onPressed: () {
                ref.read(devErrorsProvider.notifier).clear();
                Navigator.of(context).pop();
              },
            ),
          ],
        ),
        const SizedBox(height: 10),
        for (final entry in errors) ...[
          _DevErrorRow(entry: entry),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _DevErrorRow extends StatelessWidget {
  const _DevErrorRow({required this.entry});

  final DevErrorEntry entry;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.skyWash,
        borderRadius: LbmRadius.imageR,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            entry.headline,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: LbmText.tiny.copyWith(
              fontWeight: FontWeight.w800,
              color: c.clay,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${entry.route} · ${entry.backend}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: LbmText.xtiny.copyWith(color: c.ink3),
          ),
          const SizedBox(height: 4),
          Text(
            entry.report.message,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: LbmText.xtiny.copyWith(color: c.ink),
          ),
          const SizedBox(height: 8),
          PillButton(
            'Copy for Claude',
            small: true,
            expand: false,
            style: PillStyle.quiet,
            onPressed: () =>
                Clipboard.setData(ClipboardData(text: formatForClaude(entry))),
          ),
        ],
      ),
    );
  }
}

/// The corner chip that says which backend the app is talking to.
///
/// "Which project am I pointed at" is otherwise answered by remembering,
/// which is how dev secrets end up over production. Debug only, and never
/// under test.
class DevBackendBadge extends ConsumerWidget {
  const DevBackendBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(devSurfaceEnabledProvider)) return const SizedBox.shrink();

    final c = context.c;
    final label = ref.watch(backendLabelProvider);

    return Positioned(
      right: 8,
      top: 0,
      child: SafeArea(
        bottom: false,
        child: IgnorePointer(
          child: Container(
            margin: const EdgeInsets.only(top: 2),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: c.ink.withValues(alpha: 0.72),
              borderRadius: LbmRadius.pillR,
            ),
            child: Text(
              'DEV · $label',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: kBodyFont,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: c.surface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
