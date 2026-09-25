import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../state/providers.dart';
import '../router/nav.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'linked_text.dart';
import 'primitives.dart';
import 'unclaimed_shop.dart';

/// The identity block shared by your own profile and any seller's feed.
///
/// The stat row is Instagram's, remapped: Posts stays Posts, Following
/// becomes Bought. There is no Follow button on either version — discovery
/// runs on hashtags and search.
///
/// A shop gets a third, Products, on the left (Grace, 2026-09-24). It is the
/// first thing anyone wants to know about a shop and the only one of the
/// three that is really about the shop rather than the person behind it, so
/// it leads. A buyer has no products and gets two.
///
/// There was a different third stat, Total sales, between the other two. It
/// came off earlier the same day: gross sales are still counted and still
/// right, but a public shop's takings are a strange thing to print next to
/// their name, and "$0" beside a shop that opened last week reads as a
/// verdict rather than a fact. `Person.grossSalesLabel` is untouched and
/// ready if it earns its place back.
class ProfileIdentity extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    // Null until it arrives, and the cell holds its place with a dash
    // rather than a nought: a shop with two hundred products flashing "0"
    // for a moment is worse than one that admits it is still counting.
    final products = person.isSeller
        ? ref.watch(sellerProductCountProvider(person.id)).value
        : null;

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
                    // Equal shares. A count can be a wide figure, so each cell
                    // takes a fixed share and shrinks its own value to fit
                    // rather than pushing its neighbours off the row.
                    if (person.isSeller)
                      Expanded(
                        child: _Stat(
                          // A plain hyphen: the display font carries it, and
                          // it holds the cell's width while counting.
                          value: products == null ? '-' : Fmt.count(products),
                          label: 'Products',
                        ),
                      ),
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
          // Directly under the name, because it is a fact about this shop
          // rather than an announcement. It draws nothing at all for a shop
          // somebody has signed up for, which is every real seller and
          // every person (Grace, 2026-09-24).
          if (person.unclaimed) ...[
            const SizedBox(height: 7),
            Align(
              alignment: Alignment.centerLeft,
              child: UnclaimedShopBadge(person: person),
            ),
          ],
          const SizedBox(height: 3),
          // Web addresses in the bio open in the browser.
          LinkedText(
            person.bio,
            style: TextStyle(fontSize: 13.5, height: 1.55, color: c.ink2),
            linkColor: c.ink,
          ),
          if (person.tags.isNotEmpty) ...[
            const SizedBox(height: 14),
            TagChips(person.tags, onTap: (tag) => context.goToTag(tag)),
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
