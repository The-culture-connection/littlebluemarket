/// The Holiday Gift Guide, as the app's own screen, and the shelves the
/// Market screen is built from.
///
/// Grace, 2026-11-16: "Make the cover photo (Holiday Gift Guide) link to the
/// Holiday Gift Guide on the app. It should bring up products and work like
/// they are within the app and not on a webpage." The guide on the website
/// (littlebluemarket.com/pages/holiday-gift-guide) is a page of collection
/// tiles in sections, so here it is the same sections and the same
/// collections, each opening the app's own collection screen: add to cart,
/// the seller, reviews, all of it.
///
/// By handle, like `market_taxonomy.dart`, and for the same reason: the
/// handle is the address and the title is whatever Shopify says today. The
/// titles here are only a fallback for a collection the mirror has not
/// caught up with. What is *in* each collection is the store's, and changes
/// without an app update: `syncCollectionMembership` in
/// functions/src/collections.ts re-reads these from the store every three
/// hours, because adding a product to a collection sends no webhook. Every
/// handle here must be in its `CURATED_COLLECTIONS`;
/// test/gift_guide_test.dart checks.
///
/// Every handle was checked against the live store on 2026-11-16.
library;

/// One tile in the guide.
class GiftGuideEntry {
  const GiftGuideEntry(
    this.id,
    this.title,
    this.handles, {
    this.imageUrl,
    this.blurb = '',
  });

  /// Its address under the guide, for an entry of several collections.
  final String id;

  /// The tile's name, used when the mirror has no title for the collection.
  final String title;

  /// One collection, or several for a person's picks: Sandee's picks on the
  /// website are a page of three collections (Home, Self Care, Wear), and
  /// here they are those three on one screen.
  final List<String> handles;

  /// A picture for an entry of several collections, from the website's own
  /// tile. A single collection uses the collection's picture.
  final String? imageUrl;

  final String blurb;

  bool get isSingle => handles.length == 1;
}

/// One heading on the guide, with its tiles.
class GiftGuideSection {
  const GiftGuideSection(this.title, this.entries, {this.blurb = ''});

  final String title;
  final String blurb;
  final List<GiftGuideEntry> entries;
}

/// The guide as a whole.
class GiftGuide {
  const GiftGuide({
    required this.kicker,
    required this.title,
    required this.tagline,
    required this.heroImageUrl,
    required this.sections,
    required this.closingTitle,
    required this.closingBody,
  });

  final String kicker;
  final String title;
  final String tagline;
  final String heroImageUrl;
  final List<GiftGuideSection> sections;
  final String closingTitle;
  final String closingBody;

  /// Every collection the guide opens, in order, once each.
  List<String> get handles => {
    for (final section in sections)
      for (final entry in section.entries) ...entry.handles,
  }.toList();

  GiftGuideEntry? entry(String id) {
    for (final section in sections) {
      for (final entry in section.entries) {
        if (entry.id == id) return entry;
      }
    }
    return null;
  }
}

/// The website's address for the guide. A link to it anywhere in the app,
/// an advert's button above all, opens the guide's own screen instead.
const kGiftGuidePath = '/pages/holiday-gift-guide';

const _cdn = 'https://littlebluemarket.com/cdn/shop/files';

const kGiftGuide = GiftGuide(
  kicker: 'Holiday 2026',
  title: 'The Little Blue Market Gift Guide',
  tagline: 'New gift ideas added every week.',
  heroImageUrl: '$_cdn/Holiday_2026.png?width=1200',
  sections: [
    GiftGuideSection('Gifts for everyone on your list', [
      GiftGuideEntry('book-lover', 'For the Book Lover', [
        'for-the-book-lover',
      ]),
      GiftGuideEntry('doomscroll-detox', 'For a Doomscroll Detox', [
        'doomscroll-detox',
      ]),
      GiftGuideEntry('group-chat', 'For the Friend Who Runs the Group Chat', [
        'for-the-friend-who-runs-the-group-chat',
      ]),
      GiftGuideEntry('optimist', 'For the Garden Variety Optimist', [
        'for-the-garden-variety-optimist',
      ]),
      GiftGuideEntry('hopescroll', 'Hopescroll! Feel Good Products', [
        'gifts-hopescrolling',
      ]),
      GiftGuideEntry('host', 'For the Host', ['for-the-host']),
      GiftGuideEntry(
        'custom',
        'Custom & Just for Them',
        ['custom-personalized-gifts'],
        blurb:
            'One-of-a-kind gifts, made by hand and just for them. Order '
            'early for holiday delivery.',
      ),
      GiftGuideEntry(
        'good-troublemakers',
        'For the Next Generation of Good Troublemakers',
        ['gifts-kids-and-baby'],
      ),
      GiftGuideEntry('play', 'For the Ones Who Love to Play', [
        'gifts-toys-and-games',
      ]),
      GiftGuideEntry('pet-parents', 'For the Pet Parents (and Their Pets)', [
        'for-the-pet-parents',
      ]),
      GiftGuideEntry('small-biz', 'For Your Favorite Small Business Owner', [
        'gift-small-biz-besties',
      ]),
      GiftGuideEntry('teachers', 'For the Teacher Who Deserves a Raise', [
        'gifts-for-teachers',
      ]),
      GiftGuideEntry('teens', 'For the Teen Girls, Picked by a Teen Girl', [
        'for-a-teen-picked-by-a-teen',
      ]),
      GiftGuideEntry(
        'wear-it-loud',
        'Wear Values Loudly',
        ['wear-it-loud'],
        blurb:
            'For the friend who is basically a walking bumper sticker, and '
            'we mean that as a compliment.',
      ),
    ]),
    GiftGuideSection('Picked by people we love', [
      GiftGuideEntry("sellers-picks", "Sellers' Picks", [
        'market-sellers-picks',
      ]),
      GiftGuideEntry(
        'sandee',
        "Sandee's Market Picks",
        ['sandees-picks-home', 'sandees-picks-self-care', 'sandees-picks-wear'],
        imageUrl: '$_cdn/Sandee_s_Market_Picks.png?width=800',
      ),
      GiftGuideEntry(
        'sara',
        "Sara's Half Hopeful Haul",
        [
          'saras-half-hopeful-haul-wear',
          'saras-half-helpful-haul-do',
          'saras-half-hopeful-haul-dogs',
        ],
        imageUrl: '$_cdn/sara_caphill_02102026_235_2_1.jpg?width=800',
      ),
    ]),
    GiftGuideSection('Shop by budget', [
      GiftGuideEntry('under-25', 'Gifts Under \$25', ['gifts-under-25']),
      GiftGuideEntry('under-50', 'Gifts Under \$50', ['gifts-under-50']),
      GiftGuideEntry('under-100', 'Gifts Under \$100', ['gifts-under-100']),
      GiftGuideEntry('splurge', 'Splurge with Purpose', [
        'splurge-with-purpose',
      ]),
    ]),
    GiftGuideSection('Celebrate the season', [
      GiftGuideEntry('thanksgiving', 'Thanksgiving', ['thanksgiving-decor']),
      GiftGuideEntry('hanukkah', 'Hanukkah', ['hanukkah-cards-decor']),
      GiftGuideEntry('christmas', 'Christmas', ['christmas-decor']),
    ]),
    GiftGuideSection("Editor's picks", [
      GiftGuideEntry(
        'erin',
        "Erin's Cozy Next Chapter Picks",
        ['erins-holiday-picks'],
        imageUrl: '$_cdn/Erin_s_Cozy_Next_Chapter.png?width=800',
      ),
      GiftGuideEntry(
        'kate',
        "Kate's Holiday Wish List",
        ['kates-holiday-wishlist'],
        imageUrl: '$_cdn/LittleBlueCart-19.jpg?width=800',
      ),
    ]),
  ],
  closingTitle: 'Every gift is a vote.',
  closingBody:
      'When you shop here this holiday season, your gifts go to real people: '
      'small businesses that share your values. Every candle, tee and '
      'handmade treasure given this season proves that a values-driven '
      'economy is something we are building together, one gift at a time.',
);

/// The collections the Market screen opens by name, beyond the seven
/// headings and the gift guide. Kept here so the store sync has one list to
/// agree with.
const kMarketShelves = ['new-arrivals'];

/// "Shop by values": the ownership collections, in Grace's order, with the
/// words on the chip.
///
/// Grace, 2026-11-16: "add in the woman owned, black owned, veteran owned
/// etc. to the market search", and on the Market "those are probably good
/// to have on there all the time". The store files Black-owned shops under
/// BIPOC Owned, so that is the chip; the search for "black owned" finds it
/// too (see [ownershipMatch]).
const kOwnershipCollections = <(String handle, String label)>[
  ('woman-owned', 'Woman Owned'),
  ('bipoc-owned', 'BIPOC Owned'),
  ('lgbtq-owned', 'LGBTQ+ Owned'),
  ('veteran-military-spouse-owned', 'Veteran Owned'),
  ('disabled-owned-employer', 'Disabled Owned'),
  ('ally-owned', 'Ally Owned'),
];

/// The ownership collection a typed search means, or null.
///
/// "woman owned", "women-owned", "#WomanOwned", "black owned", "veteran":
/// someone searching for one of these wants that shelf, and the product
/// search, which reads titles and descriptions, finds whatever happens to
/// say the words. So the results screen offers the shelf first. Pure.
String? ownershipMatch(String query) {
  final q = query.toLowerCase().replaceAll(RegExp('[^a-z+]'), '');
  if (q.isEmpty) return null;
  const words = <String, String>{
    'woman': 'woman-owned',
    'women': 'woman-owned',
    'female': 'woman-owned',
    'bipoc': 'bipoc-owned',
    'black': 'bipoc-owned',
    'poc': 'bipoc-owned',
    'lgbtq': 'lgbtq-owned',
    'lgbtq+': 'lgbtq-owned',
    'queer': 'lgbtq-owned',
    'veteran': 'veteran-military-spouse-owned',
    'military': 'veteran-military-spouse-owned',
    'militaryspouse': 'veteran-military-spouse-owned',
    'disabled': 'disabled-owned-employer',
    'disability': 'disabled-owned-employer',
    'ally': 'ally-owned',
  };
  final stem = q.endsWith('owned') ? q.substring(0, q.length - 5) : null;
  if (stem != null && words.containsKey(stem)) return words[stem];
  // "veteran" alone, or "veteranowned", but not every word that happens to
  // contain "ally" (really, totally): the bare word has to be the whole
  // query unless it is followed by "owned".
  if (words.containsKey(q) && q.length >= 5) return words[q];
  return null;
}
