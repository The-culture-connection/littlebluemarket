import 'package:flutter_test/flutter_test.dart';
import 'package:little_blue_market/models/models.dart';

void main() {
  test('every door round-trips through its query value', () {
    for (final intent in OnboardingIntent.values) {
      expect(OnboardingIntent.fromQuery(intent.query), intent);
    }
  });

  test('anything unknown is the default door', () {
    expect(OnboardingIntent.fromQuery(null), OnboardingIntent.newHere);
    expect(OnboardingIntent.fromQuery(''), OnboardingIntent.newHere);
    expect(OnboardingIntent.fromQuery('seller'), OnboardingIntent.newHere);
  });

  test('the default door adds nothing to a route; the others add ?intent=', () {
    expect(OnboardingIntent.newHere.querySuffix, '');
    expect(OnboardingIntent.newHere.queryParam, '');
    expect(OnboardingIntent.directorySeller.querySuffix, '&intent=dirseller');
    expect(OnboardingIntent.directorySeller.queryParam, '?intent=dirseller');
  });

  test('each door lands somewhere that exists', () {
    expect(OnboardingIntent.newHere.landingRoute, '/market');
    // No accounts on littlebluecart.com: this door lands like "new here".
    expect(OnboardingIntent.directoryCustomer.landingRoute, '/market');
    expect(OnboardingIntent.marketplaceCustomer.landingRoute, '/you?tab=bought');
    expect(OnboardingIntent.directorySeller.landingRoute, '/you/directory?auto=1');
    expect(OnboardingIntent.marketplaceSeller.landingRoute, '/you/sell?auto=1');
    expect(OnboardingIntent.newDirectorySeller.landingRoute, '/you/directory?add=1');
    expect(OnboardingIntent.newMarketplaceSeller.landingRoute, '/you/sell?apply=1');
  });
}
