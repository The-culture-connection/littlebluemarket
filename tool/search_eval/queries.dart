/// One graded search.
///
/// [meanings] are what a relevant listing's name, type or collection must
/// say: any one of them, every word of it, in any singular or plural. The
/// query itself is the only meaning unless others are given.
class EvalQuery {
  const EvalQuery(this.query, this.group, {List<String>? meanings})
    : _meanings = meanings;

  final String query;
  final String group;
  final List<String>? _meanings;

  List<String> get meanings => _meanings ?? [query.toLowerCase()];
}

/// What shoppers type, drawn from what the Market actually sells
/// (2026-09-30 catalogue: stickers, jewellery, cards, books, apparel, home,
/// beauty, pets). "Tricky" are short words hidden inside longer ones, the
/// ring-spun kind of mistake.
const evalQueries = <EvalQuery>[
  // The incident, and words like it.
  EvalQuery('rings', 'tricky'),
  EvalQuery('ring', 'tricky'),
  EvalQuery('pin', 'tricky'),
  EvalQuery('pins', 'tricky'),
  EvalQuery('tea', 'tricky'),
  EvalQuery('art', 'tricky'),
  EvalQuery('hat', 'tricky'),
  EvalQuery('hats', 'tricky'),
  EvalQuery('cap', 'tricky'),
  EvalQuery('oil', 'tricky'),
  EvalQuery('bar', 'tricky'),
  EvalQuery('tag', 'tricky'),
  EvalQuery('box', 'tricky'),
  EvalQuery('cat', 'tricky'),
  EvalQuery('pen', 'tricky'),
  EvalQuery('tile', 'tricky'),
  EvalQuery('ice', 'tricky'),
  EvalQuery('bag', 'tricky'),
  EvalQuery('sock', 'tricky'),
  EvalQuery('scarf', 'tricky'),

  // Jewellery.
  EvalQuery('earrings', 'jewelry'),
  EvalQuery('earring', 'jewelry'),
  EvalQuery('necklace', 'jewelry'),
  EvalQuery('necklaces', 'jewelry'),
  EvalQuery('bracelet', 'jewelry'),
  EvalQuery('bracelets', 'jewelry'),
  EvalQuery('pendant', 'jewelry'),
  EvalQuery('hoop earrings', 'jewelry'),
  EvalQuery('dangle earrings', 'jewelry'),
  EvalQuery('sterling silver', 'jewelry'),
  EvalQuery('gold necklace', 'jewelry'),
  EvalQuery('pearl earrings', 'jewelry'),
  EvalQuery('charm', 'jewelry'),
  EvalQuery('keychain', 'jewelry'),
  EvalQuery('jewelry', 'jewelry', meanings: ['jewelry', 'jewellery']),

  // Apparel.
  EvalQuery('shirt', 'apparel'),
  EvalQuery('shirts', 'apparel'),
  EvalQuery('t-shirt', 'apparel', meanings: ['t shirt', 'tee', 'tshirt']),
  EvalQuery('tee', 'apparel', meanings: ['tee', 't shirt', 'tshirt']),
  EvalQuery('hoodie', 'apparel', meanings: ['hoodie', 'hooded']),
  EvalQuery('sweatshirt', 'apparel'),
  EvalQuery('socks', 'apparel'),
  EvalQuery('tote bag', 'apparel', meanings: ['tote']),
  EvalQuery('tote', 'apparel'),
  EvalQuery('purse', 'apparel', meanings: ['purse', 'handbag']),
  EvalQuery('handbag', 'apparel', meanings: ['handbag', 'purse']),
  EvalQuery('pride shirt', 'apparel', meanings: ['pride shirt', 'pride tee']),
  EvalQuery(
    'feminist shirt',
    'apparel',
    meanings: ['feminist shirt', 'feminist tee'],
  ),

  // Paper and books.
  EvalQuery('sticker', 'paper'),
  EvalQuery('stickers', 'paper'),
  EvalQuery('vinyl sticker', 'paper'),
  EvalQuery('holographic sticker', 'paper'),
  EvalQuery('decal', 'paper'),
  EvalQuery('greeting card', 'paper'),
  EvalQuery('birthday card', 'paper'),
  EvalQuery('thank you card', 'paper', meanings: ['thank card', 'thank note']),
  EvalQuery('card', 'paper'),
  EvalQuery('bookmark', 'paper'),
  EvalQuery('bookmarks', 'paper'),
  EvalQuery('notebook', 'paper'),
  EvalQuery('journal', 'paper'),
  EvalQuery('notepad', 'paper'),
  EvalQuery('art print', 'paper'),
  EvalQuery('print', 'paper'),
  EvalQuery('poster', 'paper'),
  EvalQuery('book', 'paper'),
  EvalQuery('books', 'paper'),
  EvalQuery(
    'romance book',
    'paper',
    meanings: ['romance book', 'romance novel'],
  ),
  EvalQuery('signed book', 'paper'),
  EvalQuery('magnet', 'paper'),
  EvalQuery('button', 'paper'),

  // Home.
  EvalQuery('candle', 'home'),
  EvalQuery('candles', 'home'),
  EvalQuery('soy candle', 'home'),
  EvalQuery('mug', 'home'),
  EvalQuery('mugs', 'home'),
  EvalQuery('coffee mug', 'home', meanings: ['coffee mug', 'mug']),
  EvalQuery('pillow', 'home'),
  EvalQuery('throw pillow', 'home', meanings: ['pillow']),
  EvalQuery('blanket', 'home'),
  EvalQuery('napkins', 'home'),
  EvalQuery('dishcloth', 'home'),
  EvalQuery('ornament', 'home'),
  EvalQuery('christmas ornament', 'home'),
  EvalQuery('coaster', 'home'),
  EvalQuery('home decor', 'home', meanings: ['decor']),
  EvalQuery('wall art', 'home', meanings: ['wall art', 'art print', 'wall']),
  EvalQuery('flag', 'home'),
  EvalQuery('yard sign', 'home'),
  EvalQuery('garden', 'home'),

  // Beauty and wellness.
  EvalQuery('soap', 'beauty'),
  EvalQuery('bar soap', 'beauty', meanings: ['soap']),
  EvalQuery('essential oil', 'beauty'),
  EvalQuery('body butter', 'beauty'),
  EvalQuery('lip balm', 'beauty'),
  EvalQuery('skincare', 'beauty', meanings: ['skincare', 'skin']),
  EvalQuery('press on nails', 'beauty', meanings: ['nail']),
  EvalQuery('nails', 'beauty', meanings: ['nail']),
  EvalQuery('lavender', 'beauty'),
  EvalQuery('hair extensions', 'beauty', meanings: ['hair extension', 'hair']),

  // Pets, kids, gifts.
  EvalQuery('dog', 'pets'),
  EvalQuery('dogs', 'pets'),
  EvalQuery('cat sticker', 'pets'),
  EvalQuery('pet portrait', 'pets', meanings: ['portrait']),
  EvalQuery('dog portrait', 'pets', meanings: ['portrait', 'pupart']),
  EvalQuery(
    'kids',
    'kids',
    meanings: ['kids', 'kid', 'children', 'child', 'baby'],
  ),
  EvalQuery('baby', 'kids'),
  EvalQuery('gift for mom', 'gifts', meanings: ['mom', 'mother', 'mama']),
  EvalQuery('mom', 'gifts', meanings: ['mom', 'mother', 'mama']),

  // Themes and causes.
  EvalQuery('pride', 'themes'),
  EvalQuery('rainbow', 'themes'),
  EvalQuery('halloween', 'themes'),
  EvalQuery('christmas', 'themes'),
  EvalQuery('feminist', 'themes'),
  EvalQuery('trans', 'themes'),
  EvalQuery('lgbtq', 'themes'),
  EvalQuery('resistance', 'themes'),
  EvalQuery('gothic', 'themes'),
  EvalQuery('witchy', 'themes', meanings: ['witchy', 'witch']),
  EvalQuery('zodiac', 'themes'),
  EvalQuery('floral', 'themes'),
  EvalQuery('ocean', 'themes'),
  EvalQuery('dragon', 'themes'),
  EvalQuery('mushroom', 'themes'),

  // Materials.
  EvalQuery('ceramic', 'materials'),
  EvalQuery('wooden', 'materials', meanings: ['wooden', 'wood']),
  EvalQuery('leather', 'materials'),
  EvalQuery(
    'embroidered',
    'materials',
    meanings: ['embroidered', 'embroidery'],
  ),
  EvalQuery('crochet', 'materials'),
  EvalQuery('handwoven', 'materials'),
  EvalQuery('glass', 'materials'),
  EvalQuery('concrete', 'materials'),
];
