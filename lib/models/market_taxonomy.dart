/// The seven headings the Market is browsed by, and what sits under each.
///
/// The store has a hundred collections: seasonal ones, seller spotlights,
/// "Gifts Under $50", ownership initiatives. All of them were on the rail,
/// which made it a hundred chips long and no kind of front door. Grace
/// picked these seven and their subcategories (2026-09-14), so the rail is
/// the seven and each one offers its own inside.
///
/// Handles, not titles, because a title is edited in Shopify whenever
/// somebody feels like it and the handle is the address. Every handle here
/// was checked against the live mirror on 2026-09-14; one that stops
/// existing is simply left off the rail rather than drawn as a dead chip, so
/// a collection renamed in Shopify costs a missing chip, never a crash.
library;

/// One heading, by handle, with its subcategories in the order they are
/// shown.
class MarketCategory {
  const MarketCategory(this.handle, this.children);

  /// The collection handle, which is also its address in the app.
  final String handle;

  /// Subcategory handles, offered inside the heading's own screen.
  final List<String> children;
}

/// Grace's seven, in her order.
const kMarketCategories = <MarketCategory>[
  MarketCategory('apparel-accessories', [
    'accessories',
    'bags',
    'clothing-1',
    'jewelry',
    'kids-baby',
  ]),
  MarketCategory('art-creative-goods', [
    'bookish-gifts',
    'greeting-note-cards',
    'journals-notebooks',
    'party-supplies',
    'prints-originals',
    'stationery',
    'stickers',
  ]),
  MarketCategory('bath-beauty-wellness', [
    'haircare',
    // The store also carries a duplicate `skincare-body-1`, left out on
    // purpose: two identical chips read as a mistake, which it is, but it is
    // a mistake to fix in Shopify rather than to mirror here.
    'skincare-body',
    'supplements-vitamins',
  ]),
  MarketCategory('food-drink', [
    'baked-goods',
    'beverage-specialty-items',
    // Really. The handle and the title both carry a Cyrillic small ie
    // (U+0435) where the second "e" should be, a typo made in Shopify long
    // before this list existed. Written as an escape so nobody "tidies" it
    // into an ASCII e and quietly loses the chip. If it is ever corrected in
    // Shopify, this becomes 'coffee'.
    'coffeе',
    'pantry-snacks',
  ]),
  MarketCategory('home-living', [
    'books',
    'candles-home-fragrance',
    'cleaning-essentials',
    'decor-furniture',
    'garden-outdoors',
    'kitchen-dining',
  ]),
  MarketCategory('kids-babies', [
    'books-learning',
    'kids-baby',
    'nursery-decor',
    'toys',
  ]),
  MarketCategory('pet-goods-services', ['pet-accessories', 'treats-food']),
];

/// The heading handles, in order.
const kMarketCategoryHandles = [
  'apparel-accessories',
  'art-creative-goods',
  'bath-beauty-wellness',
  'food-drink',
  'home-living',
  'kids-babies',
  'pet-goods-services',
];

/// The subcategories under [handle], or empty when it is not a heading.
List<String> marketChildrenOf(String handle) {
  for (final category in kMarketCategories) {
    if (category.handle == handle) return category.children;
  }
  return const [];
}
