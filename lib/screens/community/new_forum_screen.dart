import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../theme/tokens.dart';
import '../../widgets/primitives.dart';
import '../../widgets/screen.dart';

/// Name, description, and starting hashtags. Once it exists it uses the same
/// format as every other forum.
class NewForumScreen extends StatefulWidget {
  const NewForumScreen({super.key});

  @override
  State<NewForumScreen> createState() => _NewForumScreenState();
}

class _NewForumScreenState extends State<NewForumScreen> {
  final _name = TextEditingController(text: 'Refill & Return Programs');
  final _about = TextEditingController(
    text:
        'For sellers running vessel returns, refills, and take-back programs. '
        'Logistics, costs, what customers actually do.',
  );
  final _tags = <String>['#PlasticFree', '#WomanOwned'];

  @override
  void dispose() {
    _name.dispose();
    _about.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;

    return LbmScreen(
      appBar: LbmAppBar(
        title: 'Create a forum',
        actions: [
          PillButton(
            'Create',
            small: true,
            expand: false,
            onPressed: () => context.canPop()
                ? context.pop()
                : context.go('/community/forums'),
          ),
        ],
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 26),
        children: [
          LbmField(label: 'Forum name', controller: _name),
          const SizedBox(height: 16),
          LbmField(
            label: "What it's for",
            controller: _about,
            maxLines: 3,
          ),
          const SizedBox(height: 16),
          Text(
            'Starting hashtags',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.36,
              color: c.ink2,
            ),
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
              const LbmChip('+ add', style: ChipStyle.quiet),
            ],
          ),
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
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.55,
                    color: c.ink2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
