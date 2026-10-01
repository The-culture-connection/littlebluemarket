import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_blue_market/data/fixtures/fixture_data.dart';
import 'package:little_blue_market/state/providers.dart';

/// A directory listing whose owner sells on the Market points at their shop
/// in the app, not at littlebluecart.com (Grace, 2026-09-30).
void main() {
  test('an owner who sells has a shop; nobody else does', () async {
    final container = ProviderContainer(
      overrides: [
        personProvider.overrideWith((ref, id) => Stream.value(Fx.people[id]!)),
      ],
    );
    addTearDown(container.dispose);
    final sellerId = Fx.people.values.firstWhere((p) => p.isSeller).id;
    final shopperId = Fx.people.values.firstWhere((p) => !p.isSeller).id;
    container.listen(marketShopForListingProvider(sellerId), (_, _) {});
    container.listen(marketShopForListingProvider(shopperId), (_, _) {});
    await container.read(personProvider(sellerId).future);
    await container.read(personProvider(shopperId).future);

    expect(container.read(marketShopForListingProvider(sellerId)), sellerId);
    expect(container.read(marketShopForListingProvider(shopperId)), isNull);
    expect(container.read(marketShopForListingProvider('')), isNull);
    expect(container.read(marketShopForListingProvider('unclaimed')), isNull);
  });
}
