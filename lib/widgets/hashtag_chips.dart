import 'package:flutter/material.dart';

import '../models/models.dart';
import 'primitives.dart';

/// The hashtags typed into a composer, shown as chips above the field.
///
/// A tester's ask: "entering a tag should make it appear at the top with the
/// x button". The text stays the source of truth, so the chips are read from
/// it on every keystroke and the x removes that tag from the text; nothing
/// is stored twice. Renders nothing while there is no tag.
class HashtagChips extends StatefulWidget {
  const HashtagChips({super.key, required this.controller});

  final TextEditingController controller;

  @override
  State<HashtagChips> createState() => _HashtagChipsState();
}

class _HashtagChipsState extends State<HashtagChips> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  @override
  void didUpdateWidget(HashtagChips oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  void _changed() => setState(() {});

  /// Takes every occurrence of [tag] out of the text, along with the space
  /// that followed it, and keeps the caret at the end.
  void _remove(String tag) {
    final pattern = RegExp(
      '${RegExp.escape(tag)}(?!\\w) ?',
      caseSensitive: false,
    );
    final next = widget.controller.text.replaceAll(pattern, '');
    widget.controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tags = parseHashtags(widget.controller.text);
    if (tags.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Wrap(
        spacing: 7,
        runSpacing: 7,
        children: [
          for (final tag in tags)
            Semantics(
              button: true,
              label: 'Remove $tag',
              child: LbmChip(
                tag,
                style: ChipStyle.initiative,
                trailingIcon: Icons.close_rounded,
                onTap: () => _remove(tag),
              ),
            ),
        ],
      ),
    );
  }
}
