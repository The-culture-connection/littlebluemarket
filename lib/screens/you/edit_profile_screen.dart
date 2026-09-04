import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/fixtures.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/primitives.dart';
import '../../widgets/screen.dart';

/// Photo, name, handle, bio, and the initiative hashtags that appear on your
/// storefront.
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final _name = TextEditingController(text: Fx.me.name);
  late final _handle = TextEditingController(text: Fx.me.handle);
  late final _bio = TextEditingController(text: Fx.me.bio);
  late final _tags = List<String>.of(Fx.me.tags);

  @override
  void dispose() {
    _name.dispose();
    _handle.dispose();
    _bio.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;

    return LbmScreen(
      appBar: LbmAppBar(
        title: 'Edit profile',
        actions: [
          PillButton(
            'Save',
            small: true,
            expand: false,
            onPressed: () =>
                context.canPop() ? context.pop() : context.go('/you'),
          ),
        ],
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 26),
        children: [
          Center(
            child: Column(
              children: [
                Avatar(Fx.me, size: AvatarSize.lg),
                const SizedBox(height: 9),
                TextButton(
                  onPressed: () {},
                  child: Text(
                    'Change photo',
                    style: TextStyle(
                      fontFamily: kBodyFont,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: c.skyDeep,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          LbmField(label: 'Name', controller: _name),
          const SizedBox(height: 16),
          LbmField(
            label: 'Handle · also your storefront',
            controller: _handle,
          ),
          const SizedBox(height: 16),
          LbmField(label: 'Bio', controller: _bio, maxLines: 3),
          const SizedBox(height: 16),
          Text(
            'Initiative hashtags',
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
              const LbmChip('+ add', style: ChipStyle.quiet),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'These show on your storefront and pull your posts into initiative '
            'shelves.',
            style: LbmText.xtiny.copyWith(color: c.ink2, height: 1.55),
          ),
          const SizedBox(height: 16),
          LbmCard(
            child: RowStack(
              children: [
                ListRow(
                  title: const Text('Payouts & bank'),
                  subtitle: const Text('Ends in 4471'),
                  trailing: Icon(
                    Icons.chevron_right_rounded,
                    size: 22,
                    color: c.ink3,
                  ),
                  onTap: () {},
                ),
                ListRow(
                  title: const Text('Shipping addresses'),
                  subtitle: const Text('2 saved'),
                  trailing: Icon(
                    Icons.chevron_right_rounded,
                    size: 22,
                    color: c.ink3,
                  ),
                  onTap: () => context.push('/you/shipping'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
