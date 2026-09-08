/// Which door someone came through on "Are you…".
///
/// Carried as `?intent=` from the door to `/signin`, `/verify` and `/setup`,
/// and consumed once, when the profile exists: it decides only where the
/// person lands first. Nothing about it is stored. A role is a grant the
/// backend decides from the verified email, never a choice made on a screen,
/// and every landing screen is one tap away in Edit profile, so a door
/// chosen wrongly costs nothing.
enum OnboardingIntent {
  newHere('new', '/market'),
  // littlebluecart.com has no customer accounts (WooCommerce checks people
  // out as guests), so this door is a friendly label that lands on the feed
  // like "new here". Their website orders still arrive: the silent link runs
  // for every confirmed account and matches guest orders by billing email.
  directoryCustomer('dircust', '/market'),
  marketplaceCustomer('mktcust', '/you?tab=bought'),
  directorySeller('dirseller', '/you/directory?auto=1'),
  marketplaceSeller('mktseller', '/you/sell?auto=1'),
  newDirectorySeller('newdir', '/you/directory?add=1'),
  newMarketplaceSeller('newmkt', '/you/sell?apply=1');

  const OnboardingIntent(this.query, this.landingRoute);

  /// The value in `?intent=`.
  final String query;

  /// Where the person goes once their profile exists.
  final String landingRoute;

  /// Anything unknown is the default door: an old link, a typo, a cold start
  /// that lost the query.
  static OnboardingIntent fromQuery(String? value) => values.firstWhere(
    (intent) => intent.query == value,
    orElse: () => OnboardingIntent.newHere,
  );

  /// `&intent=…` to append to a route that already has a query; nothing for
  /// the default door, so the plain routes stay plain.
  String get querySuffix => this == newHere ? '' : '&intent=$query';

  /// `?intent=…` for a route with no query yet.
  String get queryParam => this == newHere ? '' : '?intent=$query';
}
