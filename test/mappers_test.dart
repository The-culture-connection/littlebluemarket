import 'package:flutter_test/flutter_test.dart';
import 'package:little_blue_market/data/firebase/mappers.dart';
import 'package:little_blue_market/data/shopify/commerce_mappers.dart';
import 'package:little_blue_market/models/models.dart';

/// Mappers are where a backend meets the app, and the failure mode that matters
/// is not "wrong value" but "crashed the screen". A document written by an
/// older build, a half-migrated field, a null where a number was expected — none
/// of those should take a card down, let alone a page.
void main() {
  group('defensive primitives', () {
    test('a missing field falls back rather than throwing', () {
      expect(FirestoreMappers.str(null), '');
      expect(FirestoreMappers.integer(null), 0);
      expect(FirestoreMappers.decimal(null), 0);
      expect(FirestoreMappers.boolean(null), isFalse);
      expect(FirestoreMappers.strings(null), isEmpty);
    });

    test('a number stored as the wrong type still reads', () {
      // Firestore hands back doubles for whole numbers often enough that this
      // is a real case, not a hypothetical.
      expect(FirestoreMappers.integer(1200.0), 1200);
      expect(FirestoreMappers.integer('1200'), 1200);
      expect(FirestoreMappers.decimal(42), 42.0);
    });

    test('a list with junk in it keeps only the strings', () {
      expect(
        FirestoreMappers.strings(['#a', 7, null, '#b']),
        ['#a', '#b'],
      );
    });

    test('an unresolved server timestamp does not throw', () {
      // The local echo of a write you just made has a null createdAt.
      expect(FirestoreMappers.time(null).millisecondsSinceEpoch, 0);
    });
  });

  group('person', () {
    test('an empty document still produces a renderable person', () {
      final person = FirestoreMappers.person('abc', const {});
      expect(person.id, 'abc');
      expect(person.name, isNotEmpty);
      expect(person.handle, isNotEmpty);
      expect(person.revenueCents, 0);
      expect(person.isSeller, isFalse);
    });

    test('the avatar tint is derived and stable', () {
      expect(FirestoreMappers.tintFor('maya'), FirestoreMappers.tintFor('maya'));
      expect(
        FirestoreMappers.tintFor('maya'),
        isNot(FirestoreMappers.tintFor('kali')),
      );
    });
  });

  group('rating', () {
    test('an average is recomputed, never read', () {
      // Storing an average alongside the bars invites the two disagreeing.
      final rating = FirestoreMappers.rating(const {
        'stars5': 3,
        'stars4': 1,
        'stars1': 0,
      });
      expect(rating.total, 4);
      expect(rating.average, closeTo((5 * 3 + 4) / 4, 0.001));
    });

    test('no reviews means zero, not a divide by zero', () {
      final rating = FirestoreMappers.rating(const {});
      expect(rating.total, 0);
      expect(rating.average, 0);
      expect(rating.isEmpty, isTrue);
    });
  });

  group('post', () {
    final base = {
      'authorId': 'maya',
      'tags': ['#PlasticFree'],
      'likeCount': 4,
      'commentCount': 1,
    };

    test('an unknown kind is skipped rather than guessed at', () {
      expect(
        FirestoreMappers.post('p', {...base, 'kind': 'something-new'},
            likedByMe: false),
        isNull,
      );
    });

    test('a listing without its product is skipped', () {
      // Better one missing card than a card claiming to be about nothing.
      expect(
        FirestoreMappers.post('p', {...base, 'kind': 'listing'},
            likedByMe: false),
        isNull,
      );
    });

    test('a review maps without needing a product', () {
      final post = FirestoreMappers.post(
        'p',
        {...base, 'kind': 'review', 'productId': 'p1', 'rating': 5, 'text': 'x'},
        likedByMe: true,
      );
      expect(post, isA<ReviewPost>());
      expect(post!.likedByMe, isTrue);
      expect(post.subjectProductId, 'p1');
    });

    test('an out-of-range rating is clamped', () {
      final post = FirestoreMappers.post(
        'p',
        {...base, 'kind': 'review', 'productId': 'p1', 'rating': 9, 'text': 'x'},
        likedByMe: false,
      );
      expect((post! as ReviewPost).rating, 5);
    });
  });

  group('conversation', () {
    test('unread is per participant, not shared', () {
      final data = {
        'participantIds': ['maya', 'kali'],
        'preview': 'hi',
        'unread': {'maya': 2, 'kali': 0},
      };
      expect(
        FirestoreMappers.conversation('c', data, uid: 'maya').unread,
        2,
      );
      expect(
        FirestoreMappers.conversation('c', data, uid: 'kali').unread,
        0,
      );
    });
  });

  group('commerce', () {
    test('an unquoted cart reports no total rather than zero', () {
      // Absent is different from zero, and showing zero shipping is a lie the
      // checkout then corrects.
      final cart = CommerceMappers.cart('c', const {
        'lines': [
          {
            'id': 'l1',
            'productId': 'p1',
            'variantId': 'v1',
            'title': 'Balm',
            'variantTitle': 'Mint',
            'unitPriceCents': 800,
            'quantity': 2,
            'sellerUid': 'kali',
          },
        ],
      });
      expect(cart.subtotalCents, 1600);
      expect(cart.totalCents, isNull);
    });

    test('a quoted cart totals', () {
      final cart = CommerceMappers.cart('c', const {
        'lines': <Map<String, dynamic>>[],
        'shippingCents': 560,
        'taxCents': 40,
      });
      expect(cart.totalCents, 600);
    });

    test('the provider status matrix flattens to something a screen can use', () {
      expect(CommerceMappers.orderStatus('paid'), OrderStatus.paid);
      expect(
        CommerceMappers.orderStatus('partially_fulfilled'),
        OrderStatus.partiallyFulfilled,
      );
      expect(CommerceMappers.orderStatus('canceled'), OrderStatus.cancelled);
      expect(
        CommerceMappers.orderStatus('partially_refunded'),
        OrderStatus.refunded,
      );
      // Anything unrecognised is pending, not a crash.
      expect(CommerceMappers.orderStatus('on_hold_pending_review'),
          OrderStatus.pending);
      expect(CommerceMappers.orderStatus(null), OrderStatus.pending);
    });

    test('an order credits each seller only for their own lines', () {
      final order = CommerceMappers.order('o1', const {
        'number': '#4471',
        'status': 'paid',
        'totalCents': 2800,
        'lines': [
          {
            'id': 'a',
            'productId': 'p1',
            'variantId': 'v1',
            'title': 'Balm',
            'variantTitle': 'Mint',
            'unitPriceCents': 800,
            'quantity': 2,
            'sellerUid': 'kali',
          },
          {
            'id': 'b',
            'productId': 'p2',
            'variantId': 'v2',
            'title': 'Stickers',
            'variantTitle': 'Pack',
            'unitPriceCents': 1200,
            'quantity': 1,
            'sellerUid': 'rae',
          },
        ],
      });
      expect(order.revenueForSeller('kali'), 1600);
      expect(order.revenueForSeller('rae'), 1200);
      expect(order.sellerIds, {'kali', 'rae'});
    });
  });
}
