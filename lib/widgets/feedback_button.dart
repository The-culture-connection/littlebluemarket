import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/repositories/dev_error_sink.dart';
import '../data/repositories/repositories.dart';
import '../models/models.dart';
import '../state/providers.dart';
import '../state/session.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'async.dart';
import 'primitives.dart';
import 'sheets.dart';

/// The floating bug button, bottom right on every screen.
///
/// Sits above the whole app (it is mounted in the MaterialApp builder), so
/// it is there on the feed, on a product, inside a sheet. A tap takes a
/// picture of the screen as it is at that moment, then opens a small sheet:
/// bug or critique, a few words, the picture, Send. Everything lands in
/// `feedback/`, which the Admin screen and the admin website list.
class FeedbackLayer extends ConsumerStatefulWidget {
  const FeedbackLayer({super.key, required this.router, required this.child});

  final GoRouter router;
  final Widget child;

  /// Screens where the button stays out of the way: the welcome artwork.
  static const hiddenOn = {'/', '/welcome'};

  @override
  ConsumerState<FeedbackLayer> createState() => _FeedbackLayerState();
}

class _FeedbackLayerState extends ConsumerState<FeedbackLayer> {
  final _shot = GlobalKey();
  bool _busy = false;

  String get _route => widget.router.routerDelegate.currentConfiguration.uri
      .toString();

  Future<List<int>?> _capture() async {
    // The test harness never delivers the engine's image callback, so a
    // test would wait forever; a note without a picture is still a note.
    if (kUnderFlutterTest) return null;
    try {
      final boundary =
          _shot.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return null;
      final image = await boundary.toImage(pixelRatio: 1.5);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return data?.buffer.asUint8List();
    } catch (_) {
      // A note without a picture is still a note.
      return null;
    }
  }

  Future<void> _open() async {
    if (_busy) return;
    setState(() => _busy = true);
    final route = _route;
    final bytes = await _capture();
    if (!mounted) return;
    setState(() => _busy = false);
    _openSheet(route, bytes);
  }

  void _openSheet(String route, List<int>? bytes) {
    // The sheet needs a context *below* the root Navigator; its overlay's
    // context is one (the Navigator's own would look up past itself).
    final host =
        widget.router.routerDelegate.navigatorKey.currentState?.overlay?.context;
    if (host == null || !host.mounted) return;
    showFeedbackSheet(host, route: route, screenshot: bytes);
  }

  @override
  Widget build(BuildContext context) {
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    return Stack(
      children: [
        RepaintBoundary(key: _shot, child: widget.child),
        ListenableBuilder(
          listenable: widget.router.routerDelegate,
          builder: (context, _) {
            final path = widget.router.routerDelegate.currentConfiguration.uri
                .path;
            if (keyboardOpen || FeedbackLayer.hiddenOn.contains(path)) {
              return const SizedBox.shrink();
            }
            return Positioned(
              right: 14,
              // Above the floating pill tab bar, which is 18 from the bottom
              // and about 64 tall, plus the phone's own gesture inset.
              bottom: MediaQuery.viewPaddingOf(context).bottom + 96,
              child: _BugButton(busy: _busy, onPressed: _open),
            );
          },
        ),
      ],
    );
  }
}

class _BugButton extends StatelessWidget {
  const _BugButton({required this.busy, required this.onPressed});

  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Semantics(
      button: true,
      label: 'Report a bug or send a critique',
      child: Material(
        color: c.ink.withValues(alpha: 0.78),
        shape: const CircleBorder(),
        elevation: 3,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: busy ? null : onPressed,
          child: SizedBox(
            width: 42,
            height: 42,
            child: busy
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Icon(Icons.bug_report_outlined, color: c.paper, size: 22),
          ),
        ),
      ),
    );
  }
}

/// The sheet on its own, so a test or another screen can open it directly.
Future<void> showFeedbackSheet(
  BuildContext context, {
  required String route,
  List<int>? screenshot,
}) => showLbmSheet<void>(
  context,
  (_) => _FeedbackSheet(route: route, screenshot: screenshot),
);

class _FeedbackSheet extends ConsumerStatefulWidget {
  const _FeedbackSheet({required this.route, this.screenshot});

  final String route;
  final List<int>? screenshot;

  @override
  ConsumerState<_FeedbackSheet> createState() => _FeedbackSheetState();
}

class _FeedbackSheetState extends ConsumerState<_FeedbackSheet> {
  final _text = TextEditingController();
  int _kind = 0;
  bool _includeShot = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  NewFeedback get _draft {
    final session = ref.read(sessionProvider).value;
    return NewFeedback(
      kind: FeedbackKind.values[_kind],
      text: _text.text,
      route: widget.route,
      includeScreenshot: _includeShot && widget.screenshot != null,
      fromName: session is MemberSession ? session.profile.name : '',
      isGuest: session is! MemberSession,
    );
  }

  Future<void> _send() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await ref
          .read(feedbackRepositoryProvider)
          .submit(_draft, screenshot: widget.screenshot);
      if (!mounted) return;
      Navigator.of(context).pop();
      messenger?.showSnackBar(
        const SnackBar(content: Text('Sent. Thank you for telling us.')),
      );
    } on RepositoryException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = describeError(error).body;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final shot = widget.screenshot;
    final draft = _draft;
    return LbmSheet(
      children: [
        Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Tell us what happened',
            style: LbmText.display.copyWith(fontSize: 20, color: c.ink),
          ),
          const SizedBox(height: 6),
          Text(
            'A bug, a confusing screen, or something you wish worked '
            'differently. It goes straight to the people who build the app.',
            style: LbmText.tiny.copyWith(color: c.ink2, height: 1.5),
          ),
          SegmentedTabs(
            labels: [for (final k in FeedbackKind.values) k.label],
            selected: _kind,
            onChanged: (i) => setState(() => _kind = i),
            padding: const EdgeInsets.fromLTRB(0, 12, 0, 6),
          ),
          LbmField(
            label: 'What happened?',
            controller: _text,
            maxLines: 4,
            autofocus: true,
            hintText: _kind == 0
                ? 'What were you doing, and what went wrong?'
                : 'What would you change?',
          ),
          if (shot != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(
                    Uint8List.fromList(shot),
                    height: 96,
                    fit: BoxFit.contain,
                    gaplessPlayback: true,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'A picture of the screen you were on goes with it.',
                    style: LbmText.tiny.copyWith(color: c.ink2, height: 1.5),
                  ),
                ),
                Switch.adaptive(
                  value: _includeShot,
                  onChanged: (v) => setState(() => _includeShot = v),
                ),
              ],
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              style: LbmText.tiny.copyWith(
                color: c.clay,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: 16),
          PillButton(
            _busy ? 'Sending…' : 'Send',
            onPressed: _busy || !draft.isValid ? null : _send,
          ),
          const SizedBox(height: 8),
        ],
        ),
      ],
    );
  }
}
