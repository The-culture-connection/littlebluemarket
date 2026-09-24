import 'package:flutter/material.dart';

import '../models/models.dart';
import '../router/nav.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'linked_text.dart';
import 'primitives.dart';

/// The identity block shared by your own profile and any seller's feed.
///
/// The stat row is Instagram's, remapped: Posts stays Posts, Following
/// becomes Bought. There is no Follow button on either version — discovery
/// runs on hashtags and search.
///
/// There was a third stat, Total sales, between them. It came off on
/// 2026-09-24 (Grace): gross sales are still counted and still right, but a
/// public shop's takings are a strange thing to print next to their name,
/// and "$0" beside a shop that opened last week reads as a verdict rather
/// than a fact. `Person.grossSalesLabel` is untouched and ready if it earns
/// its place back.
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
                    // No sales figure here for now (Grace, 2026-09-24).
                    // Gross sales are still counted and still right; they
                    // are simply not a thing to put on a public profile
                    // while the numbers are this young, and "$0" beside a
                    // new shop's name reads as a verdict rather than a
                    // fact. `grossSalesLabel` is untouched and ready when
                    // it earns its place back.
                    Expanded(
                      child: _Stat(
                        value: Fmt.count(person.purchases),
                        // The same word as the tab below it.
                        label: 'Bought',
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
          // Web addresses in the bio open in the browser.
          LinkedText(
            person.bio,
            style: TextStyle(fontSize: 13.5, height: 1.55, color: c.ink2),
            linkColor: c.ink,
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
