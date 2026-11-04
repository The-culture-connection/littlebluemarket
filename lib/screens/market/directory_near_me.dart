import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../analytics/analytics.dart';
import '../../models/models.dart';
import '../../state/location.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/async.dart';
import '../../widgets/directory_listing_card.dart';
import '../../widgets/filter_chips.dart';
import '../../widgets/primitives.dart';

/// Near me in the directory: on or off, and how far (Grace, 2026-11-04: "I
/// would like to add near me for the directory").
///
/// Its own switch rather than the feed's: the feed's Near me turns the home
/// screen into a map of products, and finding a business nearby should not
/// do that behind the person's back. It measures from the same place as the
/// feed's, the phone's location or else the city on the profile.
class DirectoryNearMe extends Notifier<({bool on, double radiusMiles})> {
  @override
  ({bool on, double radiusMiles}) build() =>
      (on: false, radiusMiles: SearchFilters.defaultRadiusMiles);

  void set({bool? on, double? radiusMiles}) => state = (
    on: on ?? state.on,
    radiusMiles: radiusMiles ?? state.radiusMiles,
  );
}

final directoryNearMeProvider =
    NotifierProvider<DirectoryNearMe, ({bool on, double radiusMiles})>(
      DirectoryNearMe.new,
    );

/// Whether the directory is showing what is near, which needs a place to
/// measure from as well as the switch.
final directoryNearMeOnProvider = Provider<bool>(
  (ref) =>
      ref.watch(directoryNearMeProvider).on &&
      ref.watch(searchFiltersProvider.select((f) => f.origin)) != null,
);

/// Every published business within the circle, nearest first, with how far.
/// Up to 200, so a category still finds its own after the nearest of every
/// other kind.
final directoryNearbyProvider =
    FutureProvider.family<
      List<(DirectoryListing, double)>,
      ({double lat, double lng, double radiusMiles})
    >((ref, where) async {
      final listings = await ref
          .watch(directoryRepositoryProvider)
          .nearbyListings(
            lat: where.lat,
            lng: where.lng,
            radiusMiles: where.radiusMiles,
            limit: 200,
          );
      return nearestFirst(listings, where.lat, where.lng);
    });

/// [listings] with their distance from the point, nearest first; the ones
/// with no known town left out. Pure.
List<(DirectoryListing, double)> nearestFirst(
  List<DirectoryListing> listings,
  double lat,
  double lng,
) => [
  for (final l in listings)
    if (l.lat != null && l.lng != null)
      (l, Geo.milesBetween(lat, lng, l.lat!, l.lng!)),
]..sort((a, b) => a.$2.compareTo(b.$2));

/// Whether [listing] is filed under the category called [name]. The site's
/// names can arrive with their ampersands escaped. Pure.
bool inCategory(DirectoryListing listing, String name) {
  String norm(String s) => s
      .replaceAll('&amp;', '&')
      .toLowerCase()
      .replaceAll(RegExp('[^a-z0-9]'), '');
  final want = norm(name);
  return listing.categories.any((c) => norm(c) == want);
}

/// The Near me switch, the distance chips and, when on, the businesses
/// nearby (in [categoryName] only, on a category's screen).
class DirectoryNearMeSection extends ConsumerWidget {
  const DirectoryNearMeSection({super.key, this.categoryName});

  final String? categoryName;

  Future<void> _toggle(BuildContext context, WidgetRef ref, bool on) async {
    final near = ref.read(directoryNearMeProvider.notifier);
    if (on) {
      Analytics.track('directory_near_me', {'on': false});
      near.set(on: false);
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final outcome = await ensureNearMeOrigin(ref);
    if (outcome == NearMeOutcome.needsCity) {
      Analytics.track('near_me_needs_place', {'from': 'directory'});
      messenger.showSnackBar(
        const SnackBar(
          duration: Duration(seconds: 8),
          content: Text(
            'Near me needs a place to measure from. Allow location, or add '
            'your city in Edit profile.',
          ),
        ),
      );
      return;
    }
    Analytics.track('directory_near_me', {'on': true});
    near.set(on: true);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final near = ref.watch(directoryNearMeProvider);
    final origin = ref.watch(searchFiltersProvider.select((f) => f.origin));
    final on = ref.watch(directoryNearMeOnProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
          child: Align(
            alignment: Alignment.centerLeft,
            child: PillButton(
              on ? 'Near me: on' : 'Near me',
              icon: Icons.near_me_rounded,
              small: true,
              expand: false,
              style: on ? PillStyle.solid : PillStyle.ghost,
              onPressed: () => _toggle(context, ref, on),
            ),
          ),
        ),
        if (on && origin != null) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Text(
              'Within ${Fmt.distanceMiles(near.radiusMiles)} '
              'of ${origin.label}',
              style: LbmText.tiny.copyWith(
                color: c.ink2,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          FilterChips(
            items: [
              for (final miles in const [5.0, 10.0, 25.0, 50.0, 100.0])
                (miles.toString(), Fmt.distanceMiles(miles)),
            ],
            selected: near.radiusMiles.toString(),
            onSelect: (value) => ref
                .read(directoryNearMeProvider.notifier)
                .set(radiusMiles: double.parse(value)),
          ),
          const SizedBox(height: 10),
          _NearbyList(
            where: (
              lat: origin.lat,
              lng: origin.lng,
              radiusMiles: near.radiusMiles,
            ),
            categoryName: categoryName,
          ),
        ],
      ],
    );
  }
}

class _NearbyList extends ConsumerWidget {
  const _NearbyList({required this.where, this.categoryName});

  final ({double lat, double lng, double radiusMiles}) where;
  final String? categoryName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nearby = ref.watch(directoryNearbyProvider(where));
    final name = categoryName;
    final circle = Fmt.distanceMiles(where.radiusMiles);
    return nearby.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => LbmEmpty(
        compact: true,
        title: 'Could not look nearby',
        body: 'Check the connection and try again.',
        action: PillButton(
          'Try again',
          expand: false,
          onPressed: () => ref.invalidate(directoryNearbyProvider(where)),
        ),
      ),
      data: (all) {
        final shown = name == null
            ? all
            : all.where((e) => inCategory(e.$1, name)).toList();
        if (shown.isEmpty) {
          return LbmEmpty(
            compact: true,
            title: name == null
                ? 'Nothing within $circle'
                : 'Nothing within $circle in $name',
            body:
                'Try a wider circle. A business counts as nearby once its '
                'listing says what town it is in.',
          );
        }
        return Column(
          children: [
            for (final (listing, miles) in shown)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                child: DirectoryListingCard(
                  key: ValueKey('near_${listing.id}'),
                  listing: listing,
                  showClaim: true,
                  milesAway: miles,
                ),
              ),
          ],
        );
      },
    );
  }
}
