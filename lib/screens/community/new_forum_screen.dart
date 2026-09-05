import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/repositories/repositories.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/async.dart';
import '../../widgets/primitives.dart';
import '../../widgets/screen.dart';

/// Create a forum. Anyone can.
class NewForumScreen extends ConsumerStatefulWidget {
  const NewForumScreen({super.key});

  @override
  ConsumerState<NewForumScreen> createState() => _NewForumScreenState();
}

class _NewForumScreenState extends ConsumerState<NewForumScreen> {
  // Empty, not pre-filled with a demo forum the way the prototype was.
  final _name = TextEditingController();
  final _about = TextEditingController();
  final _newTag = TextEditingController();
  final _tags = <String>[];
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _about.dispose();
    _newTag.dispose();
    super.dispose();
  }

  void _addTag() {
    final raw = _newTag.text.trim();
    if (raw.isEmpty) return;
    final tag = raw.startsWith('#') ? raw : '#$raw';
    setState(() {
      if (!_tags.contains(tag)) _tags.add(tag);
      _newTag.clear();
    });
  }

  Future<void> _create() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final id = await ref
          .read(socialRepositoryProvider)
          .createForum(
            NewForum(title: _name.text, description: _about.text, tags: _tags),
          );
      if (!mounted) return;
      // Straight into the forum you just made, where you are the first member.
      context.pushReplacement('/community/forums/$id');
    } on RepositoryException catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = describeError(error).body;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;

    return LbmScreen(
      appBar: LbmAppBar(
        title: 'Create a forum',
        actions: [
          PillButton(
            _saving ? 'Creating…' : 'Create',
            small: true,
            expand: false,
            onPressed: _saving ? null : _create,
          ),
        ],
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 26),
        children: [
          LbmField(
            label: 'Forum name',
            controller: _name,
            hintText: 'Refill & Return Programs',
            autofocus: true,
          ),
          const SizedBox(height: 16),
          LbmField(
            label: "What it's for",
            controller: _about,
            hintText: 'Who should join, and what belongs here.',
            maxLines: 3,
          ),
          const SizedBox(height: 16),
          Text(
            'Starting hashtags',
            style: LbmText.fieldLabel.copyWith(color: c.ink2),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final tag in _tags)
                LbmChip(
                  tag,
                  style: ChipStyle.initiative,
                  trailingIcon: Icons.close_rounded,
                  onTap: () => setState(() => _tags.remove(tag)),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: LbmField(
                  controller: _newTag,
                  hintText: 'Add a hashtag',
                  pill: true,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _addTag(),
                ),
              ),
              const SizedBox(width: 8),
              PillButton(
                'Add',
                small: true,
                expand: false,
                style: PillStyle.quiet,
                onPressed: _addTag,
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            Text(_error!, style: LbmText.tiny.copyWith(color: c.clay)),
          ],
          const SizedBox(height: 16),
          LbmCard(
            padding: const EdgeInsets.all(15),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Every forum uses the same format',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: c.ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Threads with a vote column, a title, and nested comments — '
                  'the same shape as Vendor Corner. You moderate the ones you '
                  'create.',
                  style: TextStyle(fontSize: 12.5, height: 1.55, color: c.ink2),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
