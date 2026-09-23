import 'package:flutter_test/flutter_test.dart';
import 'package:little_blue_market/models/models.dart';

/// What a search matches, and in what order.
///
/// All of this came out of Grace's first round of outside testing on
/// 2026-09-23: a tester searched "caramels" and found nothing, another
/// searched a shop that is on the Market and saw two stray listings, and
/// there were no sorting options at all.
void main() {
  Product listing(
    String id, {
    String title = 'A thing',
    int priceCents = 1000,
    int soldCount = 0,
    int saveCount = 0,
    double rating = 0,
    int ratingCount = 0,
    DateTime? createdAt,
  }) => Product(
    id: id,
    title: title,
    priceCents: priceCents,
    sellerId: 'kali',
    tags: const [],
    rating: rating,
    ratingCount: ratingCount,
    type: 'Food',
    description: '',
    cityState: 'Detroit, MI',
    saveCount: saveCount,
    commentCount: 0,
    soldCount: soldCount,
    createdAt: createdAt,
  );

  group('the plural a shopper actually types', () {
    test('a plural finds the singular the shop wrote, and the other way', () {
      expect(wordVariants('caramels'), contains('caramel'));
      expect(wordVariants('caramel'), contains('caramels'));
      expect(wordVariants('candies'), contains('candy'));
      expect(wordVariants('jewelry'), contains('jewelries'));
    });

    test('"caramels" matches "Sea Salt Caramel"', () {
      expect(wordsMatched('Sea Salt Caramel', 'caramels'), 1);
    });

    test('a word the listing does not say costs relevance, not the hit', () {
      // "caramel candy" should still find the caramels rather than nothing:
      // two words matched beats one, and one beats zero.
      expect(wordsMatched('Sea Salt Caramel Candy', 'caramel candy'), 2);
      expect(wordsMatched('Sea Salt Caramel', 'caramel candy'), 1);
      expect(wordsMatched('Beeswax Candle', 'caramel candy'), 0);
    });

    test('one-letter noise is not a word', () {
      expect(queryWords('a caramel'), ['caramel']);
    });

    test('the variants of a whole query fit array-contains-any', () {
      final variants = queryVariants('sea salt caramel candy bar boxes');
      expect(variants.length, lessThanOrEqualTo(30));
      // The most distinctive word first, so a cap never drops it.
      expect(variants.first, 'caramel');
    });
  });

  group('sorting', () {
    final products = [
      listing('a', title: 'Alpha', priceCents: 300, soldCount: 1, saveCount: 9),
      listing('b', title: 'Beta', priceCents: 100, soldCount: 7, saveCount: 2),
      listing('c', title: 'Gamma', priceCents: 200, soldCount: 3, saveCount: 5),
    ];

    test('best sellers reads what has been bought, not what was saved', () {
      expect(
        sortProducts(products, SortOrder.bestSellers).map((p) => p.id),
        ['b', 'c', 'a'],
      );
    });

    test('most popular reads what people added to their cart', () {
      expect(
        sortProducts(products, SortOrder.mostPopular).map((p) => p.id),
        ['a', 'c', 'b'],
      );
    });

    test('price goes both ways', () {
      expect(
        sortProducts(products, SortOrder.priceLowToHigh).map((p) => p.id),
        ['b', 'c', 'a'],
      );
      expect(
        sortProducts(products, SortOrder.priceHighToLow).map((p) => p.id),
        ['a', 'c', 'b'],
      );
    });

    test('a five-star listing with one review is not the top rated', () {
      final rated = [
        listing('one', title: 'One', rating: 5, ratingCount: 1),
        listing('many', title: 'Many', rating: 5, ratingCount: 90),
      ];
      expect(
        sortProducts(rated, SortOrder.topRated).map((p) => p.id),
        ['many', 'one'],
      );
    });

    test('a listing with no date sorts last under Newest, not first', () {
      final dated = [
        listing('unknown', title: 'Unknown'),
        listing('old', title: 'Old', createdAt: DateTime(2025)),
        listing('new', title: 'New', createdAt: DateTime(2026)),
      ];
      expect(
        sortProducts(dated, SortOrder.newest).map((p) => p.id),
        ['new', 'old', 'unknown'],
      );
    });

    test('equal counts fall back to the title, so a list cannot reshuffle', () {
      final tied = [
        listing('z', title: 'Zebra', soldCount: 4),
        listing('a', title: 'Apple', soldCount: 4),
      ];
      expect(
        sortProducts(tied, SortOrder.bestSellers).map((p) => p.id),
        ['a', 'z'],
      );
    });

    test('relevance leaves the order the search produced alone', () {
      expect(
        sortProducts(products, SortOrder.relevance).map((p) => p.id),
        ['a', 'b', 'c'],
      );
    });

    test('Nearest is not offered in the sheet; Near me owns it', () {
      expect(SortOrder.offered, isNot(contains(SortOrder.nearest)));
      expect(SortOrder.offered, contains(SortOrder.bestSellers));
    });
  });

  group('the scope a linked query carries', () {
    test('a hashtag searches hashtags, whatever the chips were left on', () {
      expect(scopeFor('#PlasticFree'), SearchScope.hashtags);
      expect(scopeFor('caramels'), SearchScope.all);
    });
  });
}
