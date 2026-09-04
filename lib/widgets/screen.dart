import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';
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
        child: Column(children: [?appBar, Expanded(child: child), ?bottom]),
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
            onBack ?? () => context.canPop() ? context.pop() : context.go('/market'),
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
          for (final action in actions) ...[
            const SizedBox(width: 10),
            action,
          ],
        ],
      ),
    );
  }
}

/// The composer pinned above the tab bar on the chatroom, threads and DMs.
class Composer extends StatelessWidget {
  const Composer({super.key, required this.hintText, this.onSend});

  final String hintText;
  final ValueChanged<String>? onSend;

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
  final ValueChanged<String>? onSend;
  final LbmColors colors;

  @override
  State<_ComposerBody> createState() => _ComposerBodyState();
}

class _ComposerBodyState extends State<_ComposerBody> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.onSend?.call(text);
    _controller.clear();
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
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
            ),
          ),
          const SizedBox(width: 9),
          CircleIconButton(
            icon: Icons.send_rounded,
            iconSize: 20,
            tooltip: 'Send',
            background: c.accentDeep,
            color: c.accentInk,
            onPressed: _send,
          ),
        ],
      ),
    );
  }
}
