import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'async.dart';
import 'primitives.dart';

/// The frame every screen inside the tab shell sits in.
///
/// The bottom inset is left to the shell's tab bar, so screens never pad for it
/// themselves.
class LbmScreen extends StatelessWidget {
  const LbmScreen({super.key, this.appBar, this.bottom, required this.child});

  /// A sticky header, usually [LbmAppBar].
  final Widget? appBar;

  /// A composer pinned beneath the scroll area.
  final Widget? bottom;

  /// The scrolling body.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: context.c.paper,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            ?appBar,
            Expanded(child: child),
            ?bottom,
          ],
        ),
      ),
    );
  }
}

/// The sticky header: an optional back button, a Fraunces title, and actions.
class LbmAppBar extends StatelessWidget {
  const LbmAppBar({
    super.key,
    this.title,
    this.showBack = true,
    this.leading,
    this.actions = const [],
    this.titleWidget,
    this.centerTitle = false,
    this.titleSize = 19,
    this.onBack,
  });

  final String? title;
  final bool showBack;
  final Widget? leading;
  final List<Widget> actions;

  /// Replaces the title entirely — used by the search header.
  final Widget? titleWidget;
  final bool centerTitle;
  final double titleSize;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    Widget? lead = leading;
    if (lead == null && showBack) {
      lead = CircleIconButton(
        icon: Icons.arrow_back_ios_new_rounded,
        iconSize: 20,
        tooltip: 'Back',
        onPressed:
            onBack ??
            () => context.canPop() ? context.pop() : context.go('/market'),
      );
    }

    final titleChild =
        titleWidget ??
        Text(
          title ?? '',
          textAlign: centerTitle ? TextAlign.center : TextAlign.start,
          style: LbmText.display.copyWith(
            fontSize: titleSize,
            color: c.ink,
            height: 1.2,
          ),
        );

    return Container(
      color: c.paper,
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
      child: Row(
        children: [
          if (lead != null) ...[lead, const SizedBox(width: 10)],
          Expanded(child: titleChild),
          for (final action in actions) ...[const SizedBox(width: 10), action],
        ],
      ),
    );
  }
}

/// The composer pinned above the tab bar on the chatroom, threads and DMs.
/// The shared send bar: DMs, the chatroom, thread replies, post comments.
///
/// [onSend] is awaited. The field keeps its text and the button stays off
/// until the write lands; a rejected or offline write puts the text back and
/// says why, instead of the message silently vanishing. A second tap while
/// one is in flight does nothing, so a double tap is one message.
class Composer extends StatelessWidget {
  const Composer({super.key, required this.hintText, this.onSend});

  final String hintText;
  final Future<void> Function(String text)? onSend;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return _ComposerBody(hintText: hintText, onSend: onSend, colors: c);
  }
}

class _ComposerBody extends StatefulWidget {
  const _ComposerBody({
    required this.hintText,
    required this.onSend,
    required this.colors,
  });

  final String hintText;
  final Future<void> Function(String text)? onSend;
  final LbmColors colors;

  @override
  State<_ComposerBody> createState() => _ComposerBodyState();
}

class _ComposerBodyState extends State<_ComposerBody> {
  final _controller = TextEditingController();
  var _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    final onSend = widget.onSend;
    if (text.isEmpty || onSend == null || _sending) return;
    setState(() => _sending = true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await onSend(text);
      if (mounted) _controller.clear();
    } catch (error) {
      // The text is still in the field; say why it did not go.
      messenger?.showSnackBar(
        SnackBar(content: Text(describeError(error).body)),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    return Container(
      color: c.paper,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
      child: Row(
        children: [
          Expanded(
            child: LbmField(
              controller: _controller,
              hintText: widget.hintText,
              pill: true,
              readOnly: _sending,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
            ),
          ),
          const SizedBox(width: 9),
          CircleIconButton(
            icon: _sending ? Icons.hourglass_top_rounded : Icons.send_rounded,
            iconSize: 20,
            tooltip: _sending ? 'Sending' : 'Send',
            background: c.accentDeep,
            color: c.accentInk,
            onPressed: _sending ? null : _send,
          ),
        ],
      ),
    );
  }
}
