import 'package:flutter_test/flutter_test.dart';
import 'package:little_blue_market/models/models.dart';

/// What a search matches, and in what order.
///
/// All of this came out of Grace's first round of outside testing on
/// 2026-09-23: a tester searched "caramels" and found nothing, another
/// searched a shop that is on the Market and saw two stray listings, and
/// there were no sorting options at all.
void main() {
  directorySearchTests();

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

  group('where a listing says the word', () {
    const shirtCopy =
        'A soft tee in combed and ring-spun cotton. Brings out your colours.';

    test('a shirt of ring-spun cotton is not a ring', () {
      expect(
        searchScore('rings', title: 'Butterfly Tee', description: shirtCopy),
        0,
      );
      expect(saysWord('spring collection', 'ring'), isFalse);
      expect(saysWord(shirtCopy, 'ring'), isFalse);
    });

    test('the name beats the type, and the type beats the description', () {
      final name = searchScore('rings', title: 'Gold Ring');
      final type = searchScore('rings', title: 'Gold Band', type: 'Rings');
      final said = searchScore(
        'rings',
        title: 'Gift Box',
        description: 'Holds two rings.',
      );
      expect(name, greaterThan(type));
      expect(type, greaterThan(said));
      expect(said, greaterThan(0));
    });

    test('singular and plural find each other', () {
      expect(searchScore('ring', title: 'x', type: 'Rings'), greaterThan(0));
      expect(searchScore('rings', title: 'Silver Ring'), greaterThan(0));
    });

    test('a ring filed under Rings beats a ring holder that is only named', () {
      expect(
        searchScore('rings', title: 'Gold Stacking Ring', type: 'Rings'),
        greaterThan(searchScore('rings', title: 'Concrete Ring Holder')),
      );
    });

    test('filler words neither match nor cost a lookup', () {
      expect(queryWords('gift for mom'), ['gift', 'mom']);
      expect(nameQueryWords('hair extensions for the weekend'), [
        'extensions',
        'weekend',
        'hair',
      ]);
      expect(typeSlugsFor('ring'), containsAll(['ring', 'rings']));
      expect(typeSlugsFor('Rings'), containsAll(['rings', 'ring']));
    });

    test('a collection handle counts as the words in it', () {
      expect(
        searchScore('rings', title: 'Band', tags: ['rings-and-bands']),
        greaterThan(0),
      );
    });
  });

  group('sorting', () {
    final products = [
      listing('a', title: 'Alpha', priceCents: 300, soldCount: 1, saveCount: 9),
      listing('b', title: 'Beta', priceCents: 100, soldCount: 7, saveCount: 2),
      listing('c', title: 'Gamma', priceCents: 200, soldCount: 3, saveCount: 5),
    ];

    test('best sellers reads what has been bought, not what was saved', () {
      expect(sortProducts(products, SortOrder.bestSellers).map((p) => p.id), [
        'b',
        'c',
        'a',
      ]);
    });

    test('most popular reads what people added to their cart', () {
      expect(sortProducts(products, SortOrder.mostPopular).map((p) => p.id), [
        'a',
        'c',
        'b',
      ]);
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
      expect(sortProducts(rated, SortOrder.topRated).map((p) => p.id), [
        'many',
        'one',
      ]);
    });

    test('a listing with no date sorts last under Newest, not first', () {
      final dated = [
        listing('unknown', title: 'Unknown'),
        listing('old', title: 'Old', createdAt: DateTime(2025)),
        listing('new', title: 'New', createdAt: DateTime(2026)),
      ];
      expect(sortProducts(dated, SortOrder.newest).map((p) => p.id), [
        'new',
        'old',
        'unknown',
      ]);
    });

    test('equal counts fall back to the title, so a list cannot reshuffle', () {
      final tied = [
        listing('z', title: 'Zebra', soldCount: 4),
        listing('a', title: 'Apple', soldCount: 4),
      ];
      expect(sortProducts(tied, SortOrder.bestSellers).map((p) => p.id), [
        'a',
        'z',
      ]);
    });

    test('relevance leaves the order the search produced alone', () {
      expect(sortProducts(products, SortOrder.relevance).map((p) => p.id), [
        'a',
        'b',
        'c',
      ]);
    });

    test('Nearest is not offered in the sheet; Near me owns it', () {
      expect(SortOrder.offered, isNot(contains(SortOrder.nearest)));
      expect(SortOrder.offered, contains(SortOrder.bestSellers));
    });
  });

  group('what a shopper is shown', () {
    test('a store product with no price is a leftover, and is hidden', () {
      expect(isShoppable(listing('priced', priceCents: 3200)), isTrue);
      expect(isShoppable(listing('stale', priceCents: 0)), isFalse);
    });
  });

  group('the scope a linked query carries', () {
    test('a hashtag searches hashtags, whatever the chips were left on', () {
      expect(scopeFor('#PlasticFree'), SearchScope.hashtags);
      expect(scopeFor('caramels'), SearchScope.all);
    });
  });
}

DirectoryListing _biz(
  String id,
  String title, {
  List<String> categories = const [],
}) => DirectoryListing(
  id: id,
  ownerUid: '',
  title: title,
  status: 'publish',
  link: '',
  categories: categories,
);

void directorySearchTests() {
  group('directory businesses in search (Grace, 2026-10-01)', () {
    test('a plural finds the singular, and a hidden word does not count', () {
      final hits = rankDirectoryHits([
        _biz('1', 'Golden Ring Jewelers'),
        _biz('2', 'Spring Garden Florist'),
      ], 'rings');
      expect(hits.map((l) => l.id), ['1']);
    });

    test('the name beats the category', () {
      final hits = rankDirectoryHits([
        _biz('cat', 'Maple Studio', categories: ['Candles']),
        _biz('name', 'Candle Corner'),
      ], 'candles');
      expect(hits.map((l) => l.id), ['name', 'cat']);
    });
  });
}
