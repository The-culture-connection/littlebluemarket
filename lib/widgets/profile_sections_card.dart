import 'package:flutter/material.dart';

import '../models/profile_activity.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'primitives.dart';

/// "What shows on your profile", six switches.
///
/// The switches govern what *other people* see. Your own profile keeps every
/// section, with the hidden ones marked, because a control whose effect you
/// cannot see is one you cannot trust.
class ProfileSectionsCard extends StatelessWidget {
  const ProfileSectionsCard({
    super.key,
    required this.sections,
    required this.onChanged,
  });

  final ProfileSections sections;
  final ValueChanged<ProfileSections> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHead('What shows on your profile'),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
          child: Text(
            'Turning one off hides it from everyone else. You still see all of '
            'yours, marked.',
            style: LbmText.xtiny.copyWith(color: c.ink2),
          ),
        ),
        LbmCard(
          child: RowStack(
            children: [
              _Switch(
                title: 'Bought',
                subtitle: 'The things you have bought',
                value: sections.bought,
                onChanged: (v) => onChanged(sections.copyWith(bought: v)),
              ),
              _Switch(
                title: 'Reviews',
                subtitle: 'Reviews you have written',
                value: sections.reviews,
                onChanged: (v) => onChanged(sections.copyWith(reviews: v)),
              ),
              _Switch(
                title: 'Posts',
                subtitle: 'What you have posted to the market',
                value: sections.posts,
                onChanged: (v) => onChanged(sections.copyWith(posts: v)),
              ),
              _Switch(
                title: 'Carts',
                subtitle: 'Carts you have shared',
                value: sections.carts,
                onChanged: (v) => onChanged(sections.copyWith(carts: v)),
              ),
              _Switch(
                title: 'Threads',
                subtitle: 'Forum threads you started',
                value: sections.threads,
                onChanged: (v) => onChanged(sections.copyWith(threads: v)),
              ),
              _Switch(
                title: 'Comments',
                subtitle: 'What you have said in the community',
                value: sections.comments,
                onChanged: (v) => onChanged(sections.copyWith(comments: v)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Switch extends StatelessWidget {
  const _Switch({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListRow(
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: Switch.adaptive(value: value, onChanged: onChanged),
      onTap: () => onChanged(!value),
    );
  }
}
