import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../state/providers.dart';
import '../state/session.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'haptics.dart';
import 'sheets.dart';

/// Long press to react, and the emoji counts under a message (Grace,
/// 2026-11-04: "for chats, forums, and messages allow to long press and
/// react with emojis to messages"). The same three pieces in the open chat,
/// direct messages and forum threads.

/// Sets the person's reaction, or takes it back, with a message if it did
/// not land.
Future<void> _react(
  BuildContext context,
  WidgetRef ref,
  ReactionTarget target,
  String? emoji,
) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    await ref.read(messagingRepositoryProvider).setReaction(target, emoji);
  } catch (error) {
    messenger?.showSnackBar(
      const SnackBar(content: Text('That reaction did not save. Try again.')),
    );
  }
}

/// The row of six favourites and a + for any emoji at all. Picking the one
/// you already chose takes it back.
Future<void> showReactionPicker(
  BuildContext context,
  WidgetRef ref, {
  required ReactionTarget target,
  required Map<String, String> reactions,
}) async {
  if (!requireProfile(context, ref, () {})) return;
  final me = ref.read(currentUidProvider);
  final current = me == null ? null : reactions[me];
  LbmHaptics.done();
  final picked = await showLbmSheet<String>(
    context,
    (sheet) => _QuickPicker(current: current),
  );
  if (picked == null || !context.mounted) return;
  await _react(context, ref, target, toggledReaction(current, picked));
}

class _QuickPicker extends StatefulWidget {
  const _QuickPicker({required this.current});

  final String? current;

  @override
  State<_QuickPicker> createState() => _QuickPickerState();
}

class _QuickPickerState extends State<_QuickPicker> {
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(24),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'React',
              style: LbmText.pinTitle.copyWith(fontSize: 15, color: c.ink),
            ),
            const SizedBox(height: 10),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final emoji in quickReactions)
                  _EmojiButton(
                    emoji: emoji,
                    selected: emoji == widget.current,
                    onTap: () => Navigator.of(context).pop(emoji),
                  ),
                Semantics(
                  button: true,
                  label: 'Any emoji',
                  child: _EmojiButton(
                    icon: _all ? Icons.expand_less_rounded : Icons.add_rounded,
                    selected: _all,
                    onTap: () => setState(() => _all = !_all),
                  ),
                ),
              ],
            ),
            if (_all) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: EmojiPicker(
                  onEmojiSelected: (_, emoji) =>
                      Navigator.of(context).pop(emoji.emoji),
                  config: Config(
                    height: 300,
                    emojiViewConfig: EmojiViewConfig(
                      backgroundColor: c.surface,
                      columns: 8,
                      emojiSizeMax: 26,
                    ),
                    categoryViewConfig: CategoryViewConfig(
                      backgroundColor: c.surface,
                      indicatorColor: c.accent,
                      iconColor: c.ink3,
                      iconColorSelected: c.ink,
                      backspaceColor: c.ink,
                    ),
                    bottomActionBarConfig: const BottomActionBarConfig(
                      enabled: false,
                    ),
                    searchViewConfig: SearchViewConfig(
                      backgroundColor: c.surface,
                    ),
                  ),
                ),
              ),
            ],
            if (widget.current != null) ...[
              const SizedBox(height: 10),
              Text(
                'Tap ${widget.current} again to take it back.',
                style: LbmText.tiny.copyWith(color: c.ink2),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EmojiButton extends StatelessWidget {
  const _EmojiButton({
    this.emoji,
    this.icon,
    required this.selected,
    required this.onTap,
  });

  final String? emoji;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 46,
        height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected ? c.skyMist : c.skyWash,
          border: selected ? Border.all(color: c.accent, width: 2) : null,
        ),
        child: emoji != null
            ? Text(emoji!, style: const TextStyle(fontSize: 24))
            : Icon(icon, color: c.ink, size: 24),
      ),
    );
  }
}

/// A message that reacts to a long press. Wraps the bubble, the reply or
/// the post; a short tap still does whatever it did before.
class Reactable extends ConsumerWidget {
  const Reactable({
    super.key,
    required this.target,
    required this.reactions,
    required this.child,
  });

  final ReactionTarget target;
  final Map<String, String> reactions;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Semantics(
      onLongPressHint: 'react',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: () => showReactionPicker(
          context,
          ref,
          target: target,
          reactions: reactions,
        ),
        child: child,
      ),
    );
  }
}

/// The counts under a message: one chip per emoji, yours outlined. Tapping
/// one adds yours to it, or takes yours back if it is already yours.
/// Nothing at all when nobody has reacted.
class ReactionChips extends ConsumerWidget {
  const ReactionChips({
    super.key,
    required this.target,
    required this.reactions,
    this.alignEnd = false,
  });

  final ReactionTarget target;
  final Map<String, String> reactions;

  /// Under one's own chat bubble, which sits on the right.
  final bool alignEnd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final me = ref.watch(currentUidProvider);
    final summary = reactionSummary(reactions, me);
    if (summary.isEmpty) return const SizedBox.shrink();
    final current = me == null ? null : reactions[me];
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        alignment: alignEnd ? WrapAlignment.end : WrapAlignment.start,
        spacing: 4,
        runSpacing: 4,
        children: [
          for (final r in summary)
            Semantics(
              button: true,
              label:
                  '${r.emoji} ${r.count}${r.mine ? ', yours, tap to take back' : ''}',
              child: InkWell(
                borderRadius: LbmRadius.pillR,
                onTap: () {
                  if (!requireProfile(context, ref, () {})) return;
                  _react(
                    context,
                    ref,
                    target,
                    toggledReaction(current, r.emoji),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: r.mine ? c.skyMist : c.surface,
                    borderRadius: LbmRadius.pillR,
                    border: Border.all(
                      color: r.mine ? c.accent : c.skyMist,
                      width: r.mine ? 1.5 : 1,
                    ),
                  ),
                  child: Text(
                    '${r.emoji} ${r.count}',
                    style: LbmText.tiny.copyWith(
                      color: c.ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
