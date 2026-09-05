import 'package:flutter_test/flutter_test.dart';
import 'package:little_blue_market/data/firebase/mappers.dart';
import 'package:little_blue_market/data/fixtures/fixture_repositories.dart';
import 'package:little_blue_market/data/fixtures/fixture_store.dart';
import 'package:little_blue_market/data/repositories/repositories.dart';
import 'package:little_blue_market/models/models.dart';

/// Stage 7: the cart is the like, and a cart can be posted.
void main() {
  late FixtureBackend backend;

  setUp(() {
    backend = FixtureBackend(store: FixtureStore());
  });

  tearDown(() => backend.store.dispose());

  CartPostItem item(String id) => CartPostItem(
    productId: id,
    title: 'Thing $id',
    sellerId: 'kali',
    priceCents: 100,
  );

  group('a cart post is a frozen copy', () {
    test('posts with its items and appears in the feed', () async {
      final social = FixtureSocialRepository(backend);
      final id = await social.createPost(
        NewPost.cart(items: [item('p1'), item('p2')], caption: 'Gifts'),
      );
      final post = await social.post(id);
      expect(post, isA<CartPost>());
      final cart = post as CartPost;
      expect(cart.itemCount, 2);
      expect(cart.caption, 'Gifts');
      expect(cart.subjectProductId, isNull);
      expect(cart.kind, PostKind.cart);
    });

    test('more than 24 items is refused, and so is an empty one', () async {
      final social = FixtureSocialRepository(backend);
      await expectLater(
        social.createPost(
          NewPost.cart(items: [for (var i = 0; i < 25; i++) item('p$i')]),
        ),
        throwsA(isA<ValidationException>()),
      );
      await expectLater(
        social.createPost(const NewPost.cart(items: [])),
        throwsA(isA<ValidationException>()),
      );
    });

    test('the mapper reads a stored cart post', () {
      final post = FirestoreMappers.post('c1', {
        'kind': 'cart',
        'authorId': 'dee',
        'tags': ['#PlasticFree'],
        'commentCount': 3,
        'caption': 'hello',
        'items': [
          {
            'productId': 'p1',
            'title': 'Balm',
            'sellerId': 'kali',
            'priceCents': 800,
            'imageUrl': null,
          },
          {
            'productId': 'p2',
            'title': 'Stickers',
            'sellerId': 'rae',
            'priceCents': 1200,
            'imageUrl': 'https://x/y.jpg',
          },
        ],
        'itemCount': 2,
      }, likedByMe: false);
      expect(post, isA<CartPost>());
      final cart = post! as CartPost;
      expect(cart.items.map((i) => i.productId), ['p1', 'p2']);
      expect(cart.items.last.imageUrl, 'https://x/y.jpg');
      expect(cart.items.first.price, r'$8');
    });
  });

  group('add all', () {
    test('adds every product it can and reports the rest', () async {
      final commerce = FixtureCommerceRepository(backend);
      final result = await commerce.addManyLines(['p1', 'p2', 'nope', 'p1']);
      expect(result.added, ['p1', 'p2']);
      expect(result.skipped, {'nope': 'no longer listed'});
      expect(result.cart.lines.map((l) => l.productId), ['p1', 'p2']);
    });
  });

  test('a product carries its save count, under the old name too', () {
    expect(FirestoreMappers.product('1', {'saveCount': 7}).saveCount, 7);
    expect(FirestoreMappers.product('2', {'likeCount': 4}).saveCount, 4);
    expect(FirestoreMappers.product('3', {'inCartsCount': 2}).inCartsCount, 2);
    expect(FirestoreMappers.product('4', {}).saveCount, 0);
  });
}
