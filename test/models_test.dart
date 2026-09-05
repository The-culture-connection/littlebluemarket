import 'package:flutter_test/flutter_test.dart';
import 'package:little_blue_market/models/models.dart';

CartLine _line({
  String id = 'l1',
  String variantId = 'v1',
  int unitPriceCents = 800,
  int quantity = 1,
  String sellerId = 'kali',
}) => CartLine(
  id: id,
  productId: 'p1',
  variantId: variantId,
  title: 'Cocoa Mint Lip Balm',
  variantTitle: 'Cocoa Mint',
  unitPriceCents: unitPriceCents,
  quantity: quantity,
  sellerId: sellerId,
);

void main() {
  group('Cart', () {
    test('sums lines by quantity', () {
      const cart = Cart(id: 'c', lines: []);
      expect(cart.subtotalCents, 0);
      expect(cart.isEmpty, isTrue);

      final full = cart.copyWith(
        lines: [
          _line(quantity: 2),
          _line(id: 'l2', variantId: 'v2', unitPriceCents: 1200),
        ],
      );
      expect(full.subtotalCents, 800 * 2 + 1200);
      expect(full.itemCount, 3);
    });

    test('withholds a total until shipping and tax are quoted', () {
      final quoteless = const Cart(
        id: 'c',
        lines: [],
      ).copyWith(lines: [_line()]);
      expect(
        quoteless.totalCents,
        isNull,
        reason:
            'inventing a total that checkout then contradicts loses the sale',
      );

      final quoted = quoteless.copyWith(shippingCents: 560, taxCents: 48);
      expect(quoted.totalCents, 800 + 560 + 48);
    });

    test('tracks the distinct sellers a multi-vendor cart splits across', () {
      final cart = const Cart(id: 'c', lines: []).copyWith(
        lines: [
          _line(sellerId: 'kali'),
          _line(id: 'l2', variantId: 'v2', sellerId: 'rae'),
          _line(id: 'l3', variantId: 'v3', sellerId: 'kali'),
        ],
      );
      expect(cart.sellerIds, {'kali', 'rae'});
    });

    test('finds a line by variant, not by product', () {
      final cart = const Cart(id: 'c', lines: []).copyWith(
        lines: [
          _line(variantId: 'v1'),
          _line(id: 'l2', variantId: 'v2'),
        ],
      );
      expect(cart.lineFor('v2')?.id, 'l2');
      expect(cart.lineFor('nope'), isNull);
    });
  });

  group('SearchFilters', () {
    test('two identical filters are equal', () {
      // This is what stops a provider family refetching on every rebuild.
      const a = SearchFilters(query: 'balm', scope: SearchScope.keywords);
      const b = SearchFilters(query: 'balm', scope: SearchScope.keywords);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('a changed field is a different search', () {
      const a = SearchFilters(query: 'balm');
      expect(a, isNot(a.copyWith(query: 'hat')));
      expect(a, isNot(a.copyWith(nearMe: true)));
      expect(a, isNot(a.copyWith(radiusMiles: 50)));
    });

    test('defaults to a 20 mile vicinity', () {
      expect(const SearchFilters().radiusMiles, 20);
    });

    test('is only geo-constrained once an origin is known', () {
      const near = SearchFilters(nearMe: true);
      expect(
        near.isGeoConstrained,
        isFalse,
        reason:
            'near me with nowhere to measure from would filter everything out',
      );
      expect(
        near
            .copyWith(
              origin: const SearchOrigin(
                lat: 42.3,
                lng: -83.0,
                label: 'Current location',
              ),
            )
            .isGeoConstrained,
        isTrue,
      );
    });

    test('clearOrigin actually clears', () {
      const withOrigin = SearchFilters(
        origin: SearchOrigin(lat: 1, lng: 2, label: 'x'),
      );
      expect(withOrigin.copyWith(clearOrigin: true).origin, isNull);
    });
  });

  group('SearchResults', () {
    test('is empty only when every facet is empty', () {
      expect(const SearchResults.empty().isEmpty, isTrue);
      const withSeller = SearchResults(
        sellers: [
          Person(
            id: 'a',
            name: 'A',
            handle: '@a',
            tint: 0,
            bio: '',
            tags: [],
            revenueCents: 0,
            purchases: 0,
            posts: 0,
          ),
        ],
      );
      expect(withSeller.isEmpty, isFalse);
    });
  });

  group('Conversation', () {
    test('derives the same id whichever way round the pair is given', () {
      expect(
        Conversation.idFor('maya', 'kali'),
        Conversation.idFor('kali', 'maya'),
      );
    });

    test('names the other participant', () {
      final c = Conversation(
        id: 'kali_maya',
        participantIds: const ['kali', 'maya'],
        lastMessageAt: DateTime(2026, 1, 1),
        preview: '',
      );
      expect(c.otherThan('maya'), 'kali');
    });
  });

  group('Order', () {
    test('credits a seller only for their own lines', () {
      final order = Order(
        id: '1',
        number: '#4471',
        placedAt: DateTime(2026, 1, 1),
        status: OrderStatus.paid,
        totalCents: 4600,
        lines: [
          const OrderLine(
            id: 'a',
            productId: 'p1',
            variantId: 'v1',
            title: 'Balm',
            variantTitle: 'Mint',
            unitPriceCents: 800,
            quantity: 2,
            sellerId: 'kali',
          ),
          const OrderLine(
            id: 'b',
            productId: 'p2',
            variantId: 'v2',
            title: 'Stickers',
            variantTitle: 'Pack',
            unitPriceCents: 1200,
            quantity: 1,
            sellerId: 'rae',
          ),
        ],
      );
      expect(order.revenueForSeller('kali'), 1600);
      expect(order.revenueForSeller('rae'), 1200);
      expect(order.revenueForSeller('nobody'), 0);
      expect(order.itemCount, 3);
    });
  });

  group('Post', () {
    test('only a listing or a review has a subject product', () {
      final shoutout = ShoutoutPost(
        id: 's',
        authorId: 'maya',
        createdAt: DateTime(2026, 1, 1),
        tags: const [],
        likeCount: 0,
        commentCount: 0,
        likedByMe: false,
        text: 'go buy from @kalibalm',
      );
      expect(shoutout.subjectProductId, isNull);
      expect(shoutout.kind, PostKind.shoutout);
    });
  });

  group('Page', () {
    test('concatenating carries the later cursor', () {
      const first = Page<int>(items: [1, 2], cursor: 'a');
      const second = Page<int>(items: [3], cursor: null);
      final joined = first + second;
      expect(joined.items, [1, 2, 3]);
      expect(joined.hasMore, isFalse);
    });
  });
}
