import 'package:flutter_test/flutter_test.dart';
import 'package:little_blue_market/data/firebase/mappers.dart';
import 'package:little_blue_market/data/fixtures/fixture_data.dart';
import 'package:little_blue_market/data/fixtures/fixture_repositories.dart';
import 'package:little_blue_market/data/fixtures/fixture_store.dart';
import 'package:little_blue_market/data/repositories/repositories.dart';
import 'package:little_blue_market/models/models.dart';

/// Collections are the store's real taxonomy. These pin the contract every
/// backend keeps: the rail hides empty ones, a product knows its handles, and
/// an unknown handle is an error rather than a silent empty screen.
void main() {
  late FixtureBackend backend;
  late FixtureCollectionRepository repo;

  setUp(() {
    backend = FixtureBackend(store: FixtureStore());
    repo = FixtureCollectionRepository(backend);
  });

  tearDown(() => backend.store.dispose());

  test('the rail lists non-empty collections in title order', () async {
    final all = await repo.collections();
    expect(all.map((c) => c.handle), isNot(contains('gift-guide')));
    final titles = all.map((c) => c.title.toLowerCase()).toList();
    expect(titles, [...titles]..sort());
    expect(all.first.title, 'Ally Owned');
  });

  test('a collection page holds exactly the products filed under it', () async {
    final page = await repo.productsInCollection('ally-owned');
    expect(page.items.map((p) => p.id), containsAll(['p2', 'p5']));
    for (final product in page.items) {
      expect(product.collectionHandles, contains('ally-owned'));
    }
    final empty = await repo.productsInCollection('gift-guide');
    expect(empty.items, isEmpty);
  });

  test('an unknown handle throws instead of showing nothing', () {
    expect(
      () => repo.collection('does-not-exist'),
      throwsA(isA<NotFoundException>()),
    );
  });

  test('the fixture counts agree with the fixture products', () {
    for (final collection in Fx.collections) {
      final filed = Fx.products.values.where(
        (p) => p.collectionHandles.contains(collection.handle),
      );
      expect(
        filed.length,
        collection.productCount,
        reason: '${collection.handle} says ${collection.productCount}',
      );
    }
  });

  test('the mapper reads a mirrored collection and a product\'s handles', () {
    final collection = FirestoreMappers.collection('ally-owned', {
      'title': 'Ally Owned',
      'productCount': 12,
      'imageUrl': null,
    });
    expect(collection.handle, 'ally-owned');
    expect(collection.title, 'Ally Owned');
    expect(collection.countLabel, '12 products');
    expect(collection.imageUrl, isNull);

    final product = FirestoreMappers.product('1', {
      'title': 'Balm',
      'collectionHandles': ['bath-beauty-wellness', 'woman-owned'],
    });
    expect(product.collectionHandles, ['bath-beauty-wellness', 'woman-owned']);

    // A document mirrored before Stage 4 has no handles; that is an empty
    // list, not a crash.
    expect(
      FirestoreMappers.product('2', {'title': 'x'}).collectionHandles,
      isEmpty,
    );
  });

  test('one product reads as singular', () {
    const one = Collection(handle: 'h', title: 'T', productCount: 1);
    expect(one.countLabel, '1 product');
  });
}
