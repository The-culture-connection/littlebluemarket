import 'package:flutter_test/flutter_test.dart';
import 'package:little_blue_market/data/auth/auth_service.dart';
import 'package:little_blue_market/data/fixtures/fixture_repositories.dart';
import 'package:little_blue_market/data/fixtures/fixture_store.dart';
import 'package:little_blue_market/data/repositories/repositories.dart';
import 'package:little_blue_market/models/models.dart';

/// Journey B on the demo backend: the contract the live one keeps.
void main() {
  group('money is cents from the first keystroke', () {
    test('dollars parse to cents, forgivingly', () {
      expect(parseDollars('8'), 800);
      expect(parseDollars('8.5'), 850);
      expect(parseDollars('12.50'), 1250);
      expect(parseDollars(r'$1,200.00'), 120000);
      expect(parseDollars(' 0.99 '), 99);
      expect(parseDollars('0'), 0);
    });

    test('anything that is not a price is null, never a guess', () {
      expect(parseDollars(''), isNull);
      expect(parseDollars('abc'), isNull);
      expect(parseDollars('-5'), isNull);
      expect(parseDollars('1.234'), isNull);
      expect(parseDollars('1..2'), isNull);
    });
  });

  group('the seller path', () {
    late FixtureBackend backend;
    late FixtureSellerRepository repo;

    setUp(() {
      // maya is a seller in the fixtures.
      backend = FixtureBackend(store: FixtureStore(currentUid: 'maya'));
      repo = FixtureSellerRepository(backend);
    });

    tearDown(() => backend.store.dispose());

    const good = ListingDraft(
      title: 'Cocoa Mint Lip Balm',
      priceCents: 800,
      quantity: 12,
      imageUrls: ['asset://x.png'],
      collectionHandles: ['bath-beauty-wellness'],
    );

    test(
      'draft → submitted, and the draft stays visible with a chip',
      () async {
        final id = await repo.saveDraft(good);
        final before = await repo.watchListings().first;
        expect(before.single.status, ListingStatus.draft);

        final result = await repo.publishListing(id);
        expect(result.shopifyProductId, isNotEmpty);
        expect(result.adopted, isFalse);

        final after = await repo.watchListings().first;
        expect(after.single.status, ListingStatus.submitted);
        expect(after.single.status.label, 'Under review');
        expect(after.single.shopifyProductId, result.shopifyProductId);
      },
    );

    test('a retry adopts the product the first attempt made', () async {
      final id = await repo.saveDraft(good);
      final first = await repo.publishListing(id);
      // Submitted is final until the store answers; the demo says so the
      // same way the function does.
      await expectLater(
        repo.publishListing(id),
        throwsA(isA<ValidationException>()),
      );
      final listing = (await repo.watchListings().first).single;
      expect(listing.shopifyProductId, first.shopifyProductId);
    });

    test('bad input is refused with a message naming the field', () async {
      final id = await repo.saveDraft(
        const ListingDraft(title: 'Hat', priceCents: 0, imageUrls: ['a']),
      );
      await expectLater(
        repo.publishListing(id),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.message,
            'message',
            r'Set a price above $0.',
          ),
        ),
      );
      final listing = (await repo.watchListings().first).single;
      expect(listing.status, ListingStatus.failed);
      expect(listing.error, r'Set a price above $0.');
      expect(listing.status.editable, isTrue);

      final noPhoto = await repo.saveDraft(
        const ListingDraft(title: 'Hat', priceCents: 500),
      );
      await expectLater(
        repo.publishListing(noPhoto),
        throwsA(isA<ValidationException>()),
      );
    });

    test('a non-seller is refused before anything is saved', () async {
      final buyer = FixtureBackend(store: FixtureStore(currentUid: 'dee'));
      addTearDown(buyer.store.dispose);
      final refused = FixtureSellerRepository(buyer);
      await expectLater(
        refused.saveDraft(good),
        throwsA(isA<PermissionException>()),
      );
      await expectLater(
        refused.publishListing('anything'),
        throwsA(isA<PermissionException>()),
      );
      expect(await refused.watchListings().first, isEmpty);
    });

    test('the seller flag follows the identity when one is wired', () async {
      final auth = FixtureAuthService();
      addTearDown(auth.dispose);
      await auth.continueAsGuest();
      final guest = FixtureBackend(store: FixtureStore(), auth: auth);
      addTearDown(guest.store.dispose);
      await expectLater(
        FixtureSellerRepository(guest).saveDraft(good),
        throwsA(isA<PermissionException>()),
      );
    });

    test('the draft map uses the backend\'s field names', () {
      final map = good.toMap();
      expect(map['title'], 'Cocoa Mint Lip Balm');
      expect(map['priceCents'], 800);
      expect(map['quantity'], 12);
      expect(map['trackQuantity'], true);
      expect(map['productType'], 'physical');
      expect(map['collectionHandles'], ['bath-beauty-wellness']);
      expect(map.containsKey('sku'), isFalse);
      expect(map.containsKey('status'), isFalse);
      expect(map.containsKey('sellerUid'), isFalse);
    });
  });
}
