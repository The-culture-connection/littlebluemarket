import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'primitives.dart';

/// Hashtags, one at a time: type a word, tap the blue check (or the
/// keyboard's done key), and it lands above the field as a small chip with
/// an x. The chips are the truth; the field is only ever the next tag.
///
/// The same control everywhere a tag is asked for — profile, product form,
/// the three composers — so the flow is learned once.
class TagEntry extends StatefulWidget {
  const TagEntry({
    super.key,
    required this.tags,
    required this.onChanged,
    this.hintText = 'Add a hashtag',
    this.enabled = true,
  });

  final List<String> tags;
  final ValueChanged<List<String>> onChanged;
  final String hintText;
  final bool enabled;

  /// `plastic free` and `#PlasticFree` are the same tag: one leading `#`,
  /// no spaces or punctuation inside. Empty when nothing usable was typed.
  static String normalize(String raw) {
    final word = raw.replaceAll(RegExp(r'[^\w]'), '');
    return word.isEmpty ? '' : '#$word';
  }

  @override
  State<TagEntry> createState() => _TagEntryState();
}

class _TagEntryState extends State<TagEntry> {
  final _field = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _field.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _add() {
    final tag = TagEntry.normalize(_field.text);
    _field.clear();
    if (tag.isEmpty) return;
    final exists = widget.tags.any((t) => t.toLowerCase() == tag.toLowerCase());
    if (!exists) widget.onChanged([...widget.tags, tag]);
    // Keep the keyboard up: people add several in a row.
    _focus.requestFocus();
  }

  void _remove(String tag) => widget.onChanged([...widget.tags]..remove(tag));

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.tags.isNotEmpty) ...[
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final tag in widget.tags)
                LbmChip(
                  tag,
                  style: ChipStyle.initiative,
                  fontSize: 11,
                  trailingIcon: Icons.close_rounded,
                  onTap: widget.enabled ? () => _remove(tag) : null,
                ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        Row(
          children: [
            Expanded(
              child: LbmField(
                controller: _field,
                focusNode: _focus,
                hintText: widget.hintText,
                pill: true,
                readOnly: !widget.enabled,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _add(),
              ),
            ),
            const SizedBox(width: 8),
            CircleIconButton(
              icon: Icons.check_rounded,
              tooltip: 'Add tag',
              background: c.skyDeep,
              color: Colors.white,
              onPressed: widget.enabled ? _add : null,
            ),
          ],
        ),
      ],
    );
  }
}
