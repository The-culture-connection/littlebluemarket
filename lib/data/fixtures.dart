import '../models/models.dart';

/// Mock content for the demo build, ported from the prototype's JS consts.
///
/// The copy is deliberate and reads as a real marketplace, so it is kept
/// verbatim. Swap this file for a repository backed by the real API; nothing
/// outside it knows where the data came from.
abstract final class Fx {
  // ---------------------------------------------------------------- images

  static const gif = 'assets/images/welcome-intro.gif';
  static const still = 'assets/images/welcome-still.png';
  static const cart = 'assets/images/logo-cart.png';

  static const photos = <String, String>{
    'stickers': 'assets/images/product-stickers.jpg',
    'hat': 'assets/images/product-hat.jpg',
    'balm': 'assets/images/product-lipbalm.jpg',
  };

  /// The signed-in user.
  static const meId = 'maya';
  static Person get me => people[meId]!;

  // ---------------------------------------------------------------- people

  static const people = <String, Person>{
    'maya': Person(
      id: 'maya',
      name: 'Maya Ellison',
      handle: '@mayamakes',
      tint: 0xFF5C8FCB,
      bio:
          'Small-batch skincare · Detroit. Every tube hand-filled, every label '
          'recycled.',
      tags: ['#WomanOwned', '#BIPOCOwned'],
      revenue: '\$4,820',
      purchases: 37,
      posts: 24,
    ),
    'kali': Person(
      id: 'kali',
      name: 'Kali Brooks',
      handle: '@kalibalm',
      tint: 0xFFA78BC9,
      bio:
          'Lip balms and salves in compostable paper tubes. Slow made, small '
          'batch.',
      tags: ['#WomanOwned', '#BIPOCOwned', '#PlasticFree'],
      revenue: '\$11,405',
      purchases: 52,
      posts: 61,
    ),
    'rae': Person(
      id: 'rae',
      name: 'Rae Ortiz',
      handle: '@raedrawsflowers',
      tint: 0xFFDB93A8,
      bio:
          'One-line botanical stickers and prints. Drawn on an iPad, cut at my '
          'kitchen table.',
      tags: ['#LGBTQOwned', '#DisabledOwned'],
      revenue: '\$3,910',
      purchases: 63,
      posts: 44,
    ),
    'holler': Person(
      id: 'holler',
      name: 'Holler Goods',
      handle: '@hollergoods',
      tint: 0xFFD96E9B,
      bio:
          'Embroidered caps and tees for people who love a legend. Nashville, '
          'TN.',
      tags: ['#WomanOwned', '#VoteCollection'],
      revenue: '\$14,260',
      purchases: 21,
      posts: 33,
    ),
    'ama': Person(
      id: 'ama',
      name: 'Ama Mensah',
      handle: '@amashoots',
      tint: 0xFF6FB5A6,
      bio: 'Brand photography for small makers. Half-days and full-days.',
      tags: ['#BIPOCOwned', '#WomanOwned', '#Services'],
      revenue: '\$16,200',
      purchases: 9,
      posts: 27,
    ),
    'torres': Person(
      id: 'torres',
      name: 'Torres Woodshop',
      handle: '@torreswood',
      tint: 0xFFD69B62,
      bio: 'Hand-turned bowls and boards. Veteran owned, Michigan hardwood.',
      tags: ['#VeteranOwned', '#MadeToOrder'],
      revenue: '\$8,960',
      purchases: 14,
      posts: 38,
    ),
    'juniper': Person(
      id: 'juniper',
      name: 'Juniper & Ash',
      handle: '@juniperash',
      tint: 0xFF86B98C,
      bio: 'Soy candles poured in Ypsilanti. Queer owned, refill program.',
      tags: ['#LGBTQOwned', '#PlasticFree'],
      revenue: '\$6,340',
      purchases: 41,
      posts: 52,
    ),
    'dee': Person(
      id: 'dee',
      name: 'Dee Wells',
      handle: '@deewells',
      tint: 0xFF93A9C4,
      bio: 'Buyer. Mostly stickers.',
      tags: [],
      revenue: '\$0',
      purchases: 88,
      posts: 3,
    ),
  };

  static Person person(String id) => people[id] ?? people[meId]!;

  // -------------------------------------------------------------- products

  static const products = <String, Product>{
    'p1': Product(
      id: 'p1',
      title: 'Cocoa Mint Lip Balm',
      priceCents: 800,
      sellerId: 'kali',
      photo: 'balm',
      tags: ['#WomanOwned', '#BIPOCOwned', '#PlasticFree'],
      rating: 4.9,
      ratingCount: 38,
      type: 'Bath, Beauty & Wellness',
      description:
          'Cocoa butter and peppermint in a compostable paper tube. No plastic '
          'anywhere in the package, including the seal.',
      location: 'Detroit, MI · 4 mi',
      likes: 214,
      commentCount: 18,
    ),
    'p2': Product(
      id: 'p2',
      title: 'Wildflower Sticker Pack — 5 designs',
      priceCents: 1200,
      sellerId: 'rae',
      photo: 'stickers',
      tags: ['#LGBTQOwned', '#DisabledOwned'],
      rating: 5.0,
      ratingCount: 26,
      type: 'Art & Creative Goods',
      description:
          'Five one-line botanicals — foxglove, daisy, delphinium, black-eyed '
          'susan, and the rainbow bouquet on black. Vinyl, waterproof, '
          'dishwasher safe.',
      location: 'Hamtramck, MI · 7 mi',
      likes: 341,
      commentCount: 29,
    ),
    'p3': Product(
      id: 'p3',
      title: '“What Would Dolly Do?” Dad Hat',
      priceCents: 2800,
      sellerId: 'holler',
      photo: 'hat',
      tags: ['#WomanOwned', '#VoteCollection'],
      rating: 4.8,
      ratingCount: 52,
      type: 'Apparel & Accessories',
      description:
          'Unstructured six-panel in blush, embroidered in raspberry. Brass '
          'slide buckle, one size, soft from the first wear.',
      location: 'Nashville, TN · ships free',
      likes: 508,
      commentCount: 61,
    ),
    'p4': Product(
      id: 'p4',
      title: 'Lip Balm Flight — all five flavors',
      priceCents: 3400,
      sellerId: 'kali',
      photo: 'balm',
      tags: ['#WomanOwned', '#BIPOCOwned', '#PlasticFree'],
      rating: 4.9,
      ratingCount: 19,
      type: 'Bath, Beauty & Wellness',
      description:
          'Plain, Cocoa Mint, Vanilla Latte, Strawberry Sorbet, Cocoa Orange. '
          'The whole lineup, boxed, \$6 off buying them apart.',
      location: 'Detroit, MI · 4 mi',
      likes: 187,
      commentCount: 22,
    ),
    'p5': Product(
      id: 'p5',
      title: 'Rainbow Bouquet Sticker — single',
      priceCents: 500,
      sellerId: 'rae',
      photo: 'stickers',
      tags: ['#LGBTQOwned', '#VoteCollection'],
      rating: 5.0,
      ratingCount: 14,
      type: 'Art & Creative Goods',
      description:
          'The rainbow-on-black one, on its own. \$1 from every sticker goes to '
          'the Ruth Ellis Center.',
      location: 'Hamtramck, MI · 7 mi',
      likes: 296,
      commentCount: 33,
    ),
    'p6': Product(
      id: 'p6',
      title: 'Brand photography — half day',
      priceCents: 45000,
      sellerId: 'ama',
      // A service listing keeps the illustrated tile on purpose.
      glyph: ProductGlyph.camera,
      tileFrom: 0xFFD5F0E8,
      tileTo: 0xFFA2D4C8,
      tags: ['#BIPOCOwned', '#WomanOwned', '#Services'],
      rating: 4.9,
      ratingCount: 8,
      type: 'Services',
      description:
          'Four hours, one location, 40 edited images licensed for web and '
          'social. Built for makers who need a real catalog.',
      location: 'Detroit, MI · 2 mi',
      likes: 141,
      commentCount: 22,
    ),
  };

  static Product product(String id) => products[id] ?? products['p1']!;

  /// The order the feed shows listings in.
  static const feedOrder = ['p3', 'p2', 'p1', 'p6', 'p5'];

  // --------------------------------------------------------------- reviews

  static const reviews = <String, List<Review>>{
    'p1': [
      Review(
        authorId: 'dee',
        rating: 5,
        age: '3d',
        text:
            "Fourth tube. It's the only balm that survives a Michigan February, "
            'and the paper tube composts with my coffee grounds.',
        tags: ['#PlasticFree'],
      ),
      Review(
        authorId: 'juniper',
        rating: 5,
        age: '1w',
        text:
            'Bought one at the Eastern Market pop-up and immediately ordered '
            'four more for gifts.',
        tags: [],
      ),
      Review(
        authorId: 'rae',
        rating: 4,
        age: '2w',
        text:
            'Lovely balm, my tube arrived with the label a bit crooked. Kali '
            'sent a replacement the same week, no argument.',
        tags: [],
      ),
    ],
    'p2': [
      Review(
        authorId: 'maya',
        rating: 5,
        age: '5d',
        text:
            "Put the delphinium on my water bottle in March, it's been through "
            "the dishwasher maybe forty times and hasn't lifted a corner.",
        tags: [],
      ),
      Review(
        authorId: 'dee',
        rating: 5,
        age: '3w',
        text:
            'The rainbow one is the reason I bought the pack, but the foxglove '
            'is quietly the best drawing of the five.',
        tags: ['#DisabledOwned'],
      ),
    ],
    'p3': [
      Review(
        authorId: 'maya',
        rating: 5,
        age: '1w',
        text:
            'Wore it to the farmers market and got stopped three times. The '
            'blush is softer in person than the photo.',
        tags: ['#VoteCollection'],
      ),
      Review(
        authorId: 'kali',
        rating: 4,
        age: '2w',
        text:
            'Runs a touch big — I ran the buckle almost all the way in. Still '
            'wearing it every day.',
        tags: [],
      ),
    ],
    'p4': [
      Review(
        authorId: 'dee',
        rating: 5,
        age: '6d',
        text:
            'Bought the flight so I could stop guessing. Vanilla Latte won, '
            'Cocoa Orange was the surprise.',
        tags: ['#PlasticFree'],
      ),
    ],
    'p5': [
      Review(
        authorId: 'juniper',
        rating: 5,
        age: '4d',
        text:
            "On my laptop, on my case, on the shop window. Also: the donation "
            "isn't a marketing line, Rae posts the receipts.",
        tags: ['#VoteCollection'],
      ),
    ],
    'p6': [
      Review(
        authorId: 'kali',
        rating: 5,
        age: '2w',
        text:
            'Ama shot my whole spring line in an afternoon. My conversion rate '
            'went up 30% on the new photos.',
        tags: [],
      ),
    ],
  };

  static List<Review> reviewsFor(String productId) =>
      reviews[productId] ?? const [];

  // ----------------------------------------------------------------- specs

  static const specs = <String, ProductSpec>{
    'p1': ProductSpec(
      subtitle: 'Lip balm · 0.15 oz',
      lead: 'Ships in 1–2 business days',
      rows: [
        SpecRow('Size', '0.15 oz / 4.25 g paper tube'),
        SpecRow(
          'Ingredients',
          'Cocoa butter, sunflower oil, beeswax, peppermint oil, vitamin E',
        ),
        SpecRow('Flavour', 'Cocoa and cool peppermint, lightly sweet'),
        SpecRow('Batch', 'Poured 60 at a time, Detroit MI'),
        SpecRow(
          'Packaging',
          'Paper tube and paper seal — no plastic, composts whole',
        ),
        SpecRow('Shelf life', '12 months from purchase'),
      ],
      variants: [
        Variant('Cocoa Mint', '\$8', '22 in stock', selected: true),
        Variant('Vanilla Latte', '\$8', '9 in stock'),
        Variant('Strawberry Sorbet', '\$8', '3 left'),
        Variant('Plain (unflavoured)', '\$7', 'In stock'),
      ],
      shipping: [
        SpecRow('Processing', '1–2 business days'),
        SpecRow('Carrier', 'USPS Ground Advantage · \$4.20'),
        SpecRow('Free shipping', 'Orders over \$35'),
        SpecRow('Local pickup', 'Eastern Market, Sundays'),
      ],
      returns:
          '30-day returns on unopened tubes. If it arrives melted — it happens '
          'in July — message a photo and a fresh one goes out, no need to send '
          'anything back.',
      histogram: [
        (stars: 5, count: 33),
        (stars: 4, count: 4),
        (stars: 3, count: 1),
        (stars: 2, count: 0),
        (stars: 1, count: 0),
      ],
    ),
    'p2': ProductSpec(
      subtitle: 'Sticker pack · 5 designs',
      lead: 'Ships in 2–3 business days',
      rows: [
        SpecRow(
          'Contents',
          'Foxglove, daisy, delphinium, black-eyed susan, rainbow bouquet',
        ),
        SpecRow('Size', '2.5–3 in on the long edge'),
        SpecRow('Material', 'Matte vinyl, laminated, waterproof'),
        SpecRow('Durability', 'Dishwasher safe, 3–5 years outdoors'),
        SpecRow('Drawing', 'One continuous line, drawn by hand on an iPad'),
        SpecRow('Cut', 'Kiss-cut with a white border'),
      ],
      variants: [
        Variant('Pack of 5', '\$12', 'In stock', selected: true),
        Variant('Pack of 5 — matte black set', '\$12', '6 left'),
        Variant('Two packs', '\$20', 'In stock'),
      ],
      shipping: [
        SpecRow('Processing', '2–3 business days'),
        SpecRow('Carrier', 'USPS First Class · \$2.60'),
        SpecRow('Free shipping', 'Orders over \$25'),
        SpecRow('Local pickup', 'Hamtramck, by message'),
      ],
      returns:
          'Returns accepted unopened within 30 days. Bent in the mail? Send a '
          'photo — replacements go out same day and you keep the bent one.',
      histogram: [
        (stars: 5, count: 25),
        (stars: 4, count: 1),
        (stars: 3, count: 0),
        (stars: 2, count: 0),
        (stars: 1, count: 0),
      ],
    ),
    'p3': ProductSpec(
      subtitle: 'Dad hat · one size',
      lead: 'Ships in 2–4 business days',
      rows: [
        SpecRow('Fit', 'Unstructured six-panel, low profile, one size'),
        SpecRow('Closure', 'Brass slide buckle, adjustable 21–23 in'),
        SpecRow('Fabric', '100% cotton twill, pre-washed'),
        SpecRow('Embroidery', 'Raspberry thread, 3-D puff on “Dolly”'),
        SpecRow('Colour', 'Blush pink'),
        SpecRow('Care', 'Spot clean, air dry — the embroidery hates a dryer'),
      ],
      variants: [
        Variant('Blush', '\$28', 'In stock', selected: true),
        Variant('Butter yellow', '\$28', '11 in stock'),
        Variant('Denim', '\$28', 'Back Oct 4'),
      ],
      shipping: [
        SpecRow('Processing', '2–4 business days'),
        SpecRow('Carrier', 'USPS Ground · free'),
        SpecRow('Free shipping', 'On every hat'),
        SpecRow('Local pickup', 'Nashville, by arrangement'),
      ],
      returns:
          '30-day returns, worn or not — hats are hard to judge on a screen. '
          'Return shipping is on us within the US.',
      histogram: [
        (stars: 5, count: 44),
        (stars: 4, count: 6),
        (stars: 3, count: 2),
        (stars: 2, count: 0),
        (stars: 1, count: 0),
      ],
    ),
    'p4': ProductSpec(
      subtitle: 'Gift box · 5 tubes',
      lead: 'Ships in 2–3 business days',
      rows: [
        SpecRow(
          'Contents',
          'Plain, Cocoa Mint, Vanilla Latte, Strawberry Sorbet, Cocoa Orange',
        ),
        SpecRow('Size', '5 × 0.15 oz paper tubes'),
        SpecRow('Box', 'Kraft board, no cellophane, no ribbon glue'),
        SpecRow('Saving', '\$6 against buying the five apart'),
        SpecRow('Gift note', 'Free, handwritten — add it at checkout'),
        SpecRow('Shelf life', '12 months from purchase'),
      ],
      variants: [
        Variant('Full flight (5)', '\$34', 'In stock', selected: true),
        Variant('Sampler (3, your pick)', '\$21', 'In stock'),
        Variant('Flight + tin', '\$39', '4 left'),
      ],
      shipping: [
        SpecRow('Processing', '2–3 business days'),
        SpecRow('Carrier', 'USPS Ground Advantage · \$5.10'),
        SpecRow('Free shipping', 'Orders over \$35'),
        SpecRow('Local pickup', 'Eastern Market, Sundays'),
      ],
      returns:
          '30-day returns if the box is unopened. Opened one flavour and hated '
          "it? Message me — I'll swap that tube.",
      histogram: [
        (stars: 5, count: 17),
        (stars: 4, count: 2),
        (stars: 3, count: 0),
        (stars: 2, count: 0),
        (stars: 1, count: 0),
      ],
    ),
    'p5': ProductSpec(
      subtitle: 'Sticker · single',
      lead: 'Ships in 2–3 business days',
      rows: [
        SpecRow('Size', '3 in on the long edge'),
        SpecRow('Material', 'Matte vinyl on black, laminated'),
        SpecRow('Durability', 'Dishwasher safe, 3–5 years outdoors'),
        SpecRow('Giving', '\$1 per sticker to the Ruth Ellis Center'),
        SpecRow('Drawing', 'One continuous line, six colours'),
        SpecRow('Cut', 'Kiss-cut with a white border'),
      ],
      variants: [
        Variant('Rainbow on black', '\$5', 'In stock', selected: true),
        Variant('Rainbow on white', '\$5', 'In stock'),
        Variant('Ten-pack for your shop', '\$38', 'For stockists'),
      ],
      shipping: [
        SpecRow('Processing', '2–3 business days'),
        SpecRow('Carrier', 'USPS First Class · \$2.60'),
        SpecRow('Free shipping', 'Orders over \$25'),
        SpecRow('Local pickup', 'Hamtramck, by message'),
      ],
      returns:
          'Returns accepted unopened within 30 days. Bent in the mail? Send a '
          'photo, keep the bent one, a new one goes out.',
      histogram: [
        (stars: 5, count: 14),
        (stars: 4, count: 0),
        (stars: 3, count: 0),
        (stars: 2, count: 0),
        (stars: 1, count: 0),
      ],
    ),
    'p6': ProductSpec(
      subtitle: 'Service · half day',
      lead: 'Booking, not checkout',
      rows: [
        SpecRow('Duration', '4 hours on location'),
        SpecRow('Deliverable', '40 edited images, web + social licence'),
        SpecRow('Turnaround', '7 business days'),
        SpecRow('Location', 'Your space, or the Corktown studio'),
        SpecRow('Included', 'Basic styling, one product setup change'),
        SpecRow('Add-ons', 'Extra hour \$95 · rush edit \$150'),
      ],
      variants: [
        Variant('Half day (4 hr)', '\$450', 'Sept 18, 24 open', selected: true),
        Variant('Full day (8 hr)', '\$820', 'Oct 2 open'),
        Variant('Studio add-on', '\$120', 'Any date'),
      ],
      shipping: [
        SpecRow('Scheduling', 'Confirmed by message within 24 hr'),
        SpecRow('Deposit', '50% to hold the date'),
        SpecRow('Travel', 'Free within 25 mi of Detroit'),
        SpecRow('Cancellation', 'Full refund up to 7 days out'),
      ],
      returns:
          'Services are booked, not shipped. Buy opens a message with your '
          'requested dates — nothing is charged until Ama confirms.',
      histogram: [
        (stars: 5, count: 7),
        (stars: 4, count: 1),
        (stars: 3, count: 0),
        (stars: 2, count: 0),
        (stars: 1, count: 0),
      ],
    ),
  };

  static ProductSpec spec(String id) => specs[id] ?? specs['p1']!;

  // ------------------------------------------------------------ search etc.

  static const tags = <TagCount>[
    TagCount('#WomanOwned', '2,412 posts'),
    TagCount('#BIPOCOwned', '1,908 posts'),
    TagCount('#LGBTQOwned', '1,341 posts'),
    TagCount('#VoteCollection', '1,102 posts'),
    TagCount('#PlasticFree', '984 posts'),
    TagCount('#VeteranOwned', '761 posts'),
    TagCount('#DisabledOwned', '613 posts'),
    TagCount('#MadeInDetroit', '542 posts'),
  ];

  static const recentSearches = <String>[
    'soy candle',
    '#PlasticFree',
    'ceramics near me',
    'Torres Woodshop',
    'half day photography',
  ];

  // --------------------------------------------------------------- community

  static const forums = <Forum>[
    Forum(
      id: 'f1',
      title: 'Vendor Corner',
      description: 'The catch-all for people who sell here.',
      members: '312 members',
      threadCount: 48,
      tint: 0xFF5C8FCB,
    ),
    Forum(
      id: 'f2',
      title: 'Pricing Your Work',
      description: 'Cost of goods, margins, and saying the number out loud.',
      members: '244 members',
      threadCount: 33,
      tint: 0xFFD69B62,
    ),
    Forum(
      id: 'f3',
      title: 'Packaging & Shipping Hacks',
      description: 'Plastic-free mailers, label printers, dim weight.',
      members: '189 members',
      threadCount: 27,
      tint: 0xFF86B98C,
    ),
    Forum(
      id: 'f4',
      title: 'Wholesale 101',
      description: 'Line sheets, terms, and your first stockist.',
      members: '140 members',
      threadCount: 19,
      tint: 0xFFA78BC9,
    ),
    Forum(
      id: 'f5',
      title: 'Detroit Pickup Swaps',
      description: 'Local handoffs, market days, table shares.',
      members: '96 members',
      threadCount: 12,
      tint: 0xFFDB93A8,
    ),
  ];

  static Forum forum(String id) =>
      forums.firstWhere((f) => f.id == id, orElse: () => forums.first);

  static const threads = <ForumThread>[
    ForumThread(
      id: 't1',
      forumId: 'f1',
      authorId: 'kali',
      title: 'How do you price handmade when materials cost 4x what they did?',
      body:
          'Shea butter went from \$9/lb to \$34/lb in two years and I have not '
          'moved my price since 2023. I know the answer is raise it. What I '
          'want to know is how you told your regulars — did you post about it, '
          'quietly change the number, or bundle it into a bigger relaunch?',
      upvotes: 128,
      commentCount: 47,
      age: '6h',
    ),
    ForumThread(
      id: 't2',
      forumId: 'f1',
      authorId: 'torres',
      title: "Anyone else's Q4 shipping costs basically double?",
      body:
          'Bowls are heavy and dimensional weight is eating me alive. '
          'Considering a flat local pickup option through #DetroitPickupSwaps.',
      upvotes: 64,
      commentCount: 22,
      age: '1d',
    ),
    ForumThread(
      id: 't3',
      forumId: 'f1',
      authorId: 'juniper',
      title: 'Best label printer under \$200?',
      body:
          'Currently hand-writing 40 labels a week and my wrist has opinions.',
      upvotes: 41,
      commentCount: 31,
      age: '2d',
    ),
  ];

  static ForumThread thread(String id) =>
      threads.firstWhere((t) => t.id == id, orElse: () => threads.first);

  static List<ForumThread> threadsIn(String forumId) =>
      threads.where((t) => t.forumId == forumId).toList();

  static const comments = <ThreadComment>[
    ThreadComment(
      authorId: 'torres',
      upvotes: 34,
      age: '5h',
      text:
          'Posted about it. One paragraph, no apology, named the actual input '
          'cost. Lost two customers, kept ninety.',
      depth: 0,
    ),
    ThreadComment(
      authorId: 'juniper',
      upvotes: 22,
      age: '4h',
      text:
          'Bundled mine into a relaunch with new labels so it read as a new '
          'product, not a price hike. Felt sneakier than it was.',
      depth: 0,
    ),
    ThreadComment(
      authorId: 'kali',
      upvotes: 11,
      age: '3h',
      text:
          "That's the version I keep circling. Did anyone push back on the new "
          'labels?',
      depth: 1,
    ),
    ThreadComment(
      authorId: 'rae',
      upvotes: 18,
      age: '2h',
      text:
          'Wrote a whole zine page on this. Short version: people forgive a '
          'raise they understand and resent one they discover.',
      depth: 0,
    ),
    ThreadComment(
      authorId: 'ama',
      upvotes: 9,
      age: '1h',
      text:
          'If you reshoot before you raise, the new price lands on new photos '
          'and nobody does the side-by-side.',
      depth: 0,
    ),
  ];

  static const chatroom = <ChatMessage>[
    ChatMessage(
      authorId: 'rae',
      time: '9:02',
      text:
          'Anyone tabling at Eastern Market Sunday? I have a half table and too '
          'much space.',
    ),
    ChatMessage(
      authorId: 'torres',
      time: '9:06',
      text:
          "I'm in for Sunday. Bringing the seconds bin, everything under \$40.",
    ),
    ChatMessage(
      authorId: 'juniper',
      time: '9:11',
      text:
          'Reminder that the #VoteCollection deadline for October is Friday — '
          "tag your posts or they won't pull into the shelf.",
    ),
    ChatMessage(
      authorId: 'kali',
      time: '9:14',
      text:
          'Cocoa Mint restock is live. First 20 tubes have the old hand-stamped '
          'label, which apparently people collect now?',
    ),
    ChatMessage(
      authorId: 'maya',
      time: '9:15',
      text:
          "Claiming one. Also Rae — yes to the half table, I'll bring the "
          'second folding chair.',
      mine: true,
    ),
    ChatMessage(
      authorId: 'ama',
      time: '9:19',
      text:
          'If anyone needs product shots before the holiday push, I have two '
          'half-days left in September.',
    ),
  ];

  // --------------------------------------------------------------- messages

  static const dms = <DmSummary>[
    DmSummary(
      personId: 'kali',
      age: '2m',
      preview: 'Tubes ship today — I tucked in a Cocoa Orange to try',
      unread: 2,
    ),
    DmSummary(
      personId: 'ama',
      age: '1h',
      preview: 'Sept 18 works. Want the studio or your kitchen?',
      unread: 0,
    ),
    DmSummary(
      personId: 'juniper',
      age: 'Yesterday',
      preview: "Got the vessel back, credit's on your account",
      unread: 0,
    ),
    DmSummary(
      personId: 'rae',
      age: 'Mon',
      preview: 'New delphinium design is cut. Want a stockist price for the table?',
      unread: 0,
    ),
  ];

  static const dmThread = <DmMessage>[
    DmMessage(
      mine: false,
      time: '9:41 AM',
      text: 'Hey! Saw your order come through — the Cocoa Mint.',
    ),
    DmMessage(
      mine: true,
      time: '9:44 AM',
      text: 'Yes! Fourth one. Any chance you still have the hand-stamped labels?',
    ),
    DmMessage(mine: false, time: '9:46 AM', text: 'I have four left. Saving you one.'),
    DmMessage(
      mine: false,
      time: '9:46 AM',
      text: 'Tubes ship today — I tucked in a Cocoa Orange to try.',
    ),
    DmMessage(
      mine: true,
      time: '9:48 AM',
      text: "You're the best. I'll leave a review once it lands.",
    ),
  ];

  // --------------------------------------------------------------- shipping

  static const sending = <Shipment>[
    Shipment(
      productId: 'p1',
      party: 'J. Alvarez · Chicago, IL',
      state: ShipmentState.inTransit,
      tracking: '9405 5118 9956 2231 4408 71',
      step: 2,
      note: 'Arriving Thursday',
    ),
    Shipment(
      productId: 'p5',
      party: 'M. Nguyen · Portland, OR',
      state: ShipmentState.labelCreated,
      tracking: '9405 5118 9956 2231 5107 03',
      step: 1,
      note: 'Drop off by Wed',
    ),
    Shipment(
      productId: 'p4',
      party: 'D. Wells · Ferndale, MI',
      state: ShipmentState.delivered,
      tracking: '9405 5118 9956 2230 8842 19',
      step: 4,
      note: 'Left at front door',
    ),
  ];

  static const receiving = <Shipment>[
    Shipment(
      productId: 'p3',
      party: 'from Holler Goods',
      state: ShipmentState.outForDelivery,
      tracking: '9261 2902 4536 1177 3320 96',
      step: 3,
      note: 'By 8:00 PM today',
    ),
    Shipment(
      productId: 'p2',
      party: 'from Rae Ortiz',
      state: ShipmentState.inTransit,
      tracking: '9261 2902 4536 1177 2214 55',
      step: 2,
      note: 'Arriving Sep 6',
    ),
  ];

  // ---------------------------------------------------------------- profile

  static const myPosts = ['p1', 'p4', 'p2', 'p3', 'p5', 'p6'];
  static const myPurchases = ['p3', 'p2', 'p5', 'p1', 'p4', 'p6'];

  /// Flat shipping used by the buy sheet, in cents.
  static const shippingCents = 560;

  // ----------------------------------------------------------------- search

  /// Products matching a query by hashtag, title, or product type.
  static List<String> search(String query) {
    final q = query.toLowerCase();
    final hits = products.values
        .where(
          (p) =>
              p.tags.contains(query) ||
              p.title.toLowerCase().contains(q) ||
              p.type.toLowerCase().contains(q),
        )
        .map((p) => p.id)
        .toList();
    return hits.isEmpty ? const ['p1', 'p4'] : hits;
  }

  /// Reviews carrying [query], with the product each is attached to. A review
  /// is indexed under its parent product, never under its author.
  static List<({String productId, Review review})> reviewsTagged(
    String query,
    List<String> productIds,
  ) {
    return [
      for (final id in productIds)
        for (final r in reviewsFor(id))
          if (r.tags.contains(query)) (productId: id, review: r),
    ];
  }
}
