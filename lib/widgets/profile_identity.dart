import 'package:flutter/material.dart';

import '../models/models.dart';
import '../router/nav.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'primitives.dart';

/// The identity block shared by your own profile and any seller's feed.
///
/// The stat row is Instagram's, remapped: Followers becomes Revenue, Following
/// becomes Purchases. There is no Follow button on either version — discovery
/// runs on hashtags and search.
class ProfileIdentity extends StatelessWidget {
  const ProfileIdentity({
    super.key,
    required this.person,
    required this.actions,
  });

  final Person person;

  /// What sits below the bio: Message on someone else's feed, Edit profile and
  /// Post on your own.
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final c = context.c;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Avatar(person, size: AvatarSize.lg),
              const SizedBox(width: 14),
              Expanded(
                child: Row(
                  children: [
                    // Equal shares. Revenue can be a wide figure, so each cell
                    // takes a fixed share and shrinks its own value to fit
                    // rather than pushing its neighbours off the row.
                    Expanded(
                      child: _Stat(
                        value: Fmt.count(person.posts),
                        label: 'Posts',
                      ),
                    ),
                    // Buyers have no sales, and a "$0" next to their name
                    // reads as a judgement rather than a fact.
                    if (person.isSeller)
                      Expanded(
                        child: _Stat(
                          value: person.grossSalesLabel,
                          label: 'Total sales',
                        ),
                      ),
                    Expanded(
                      child: _Stat(
                        value: Fmt.count(person.purchases),
                        label: 'Purchases',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            person.name,
            style: LbmText.display.copyWith(fontSize: 18, color: c.ink),
          ),
          const SizedBox(height: 3),
          Text(
            person.bio,
            style: TextStyle(fontSize: 13.5, height: 1.55, color: c.ink2),
          ),
          if (person.tags.isNotEmpty) ...[
            const SizedBox(height: 14),
            TagChips(person.tags, onTap: (tag) => context.goToResults(tag)),
          ],
          const SizedBox(height: 14),
          ...actions,
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              maxLines: 1,
              style: LbmText.display.copyWith(
                fontSize: 18,
                height: 1.15,
                color: c.ink,
              ),
            ),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: c.ink3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
