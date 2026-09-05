/**
 * Seeds the Firestore emulator with the app's fixture content.
 *
 * The point is equivalence: with this loaded, the live build renders the same
 * screens as the fixture build. That is the whole test strategy for the
 * Firestore repositories — anything that looks different is a mapping bug, and
 * it is visible by flipping one flag rather than by reading code.
 *
 *   firebase emulators:start --only firestore,auth
 *   node functions/scripts/seed.mjs
 *   cd little_blue_market && flutter run \
 *     --dart-define=LBM_BACKEND=live --dart-define=LBM_EMULATORS=true
 *
 * Refuses to run against a real project. Seeding production with demo content
 * would be a genuinely bad afternoon.
 */
import { initializeApp } from 'firebase-admin/app';
import { getFirestore, Timestamp } from 'firebase-admin/firestore';

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  console.error(
    'FIRESTORE_EMULATOR_HOST is not set.\n' +
      'This script only ever runs against the emulator. Start it with:\n' +
      '  firebase emulators:start --only firestore,auth\n' +
      'and run this in the same shell.',
  );
  process.exit(1);
}

initializeApp({ projectId: process.env.GCLOUD_PROJECT ?? 'little-blue-610e5' });
const db = getFirestore();

const now = Date.now();
const ago = (days = 0, hours = 0) =>
  Timestamp.fromMillis(now - days * 86400000 - hours * 3600000);

const PEOPLE = [
  ['maya', 'Maya Ellison', '@mayamakes', 0xff5c8fcb, true, 482000, 37, 24,
    'Small-batch skincare · Detroit. Every tube hand-filled, every label recycled.',
    ['#WomanOwned', '#BIPOCOwned'], 'Detroit, MI', 42.3314, -83.0458],
  ['kali', 'Kali Brooks', '@kalibalm', 0xffa78bc9, true, 1140500, 52, 61,
    'Lip balms and salves in compostable paper tubes.',
    ['#WomanOwned', '#BIPOCOwned', '#PlasticFree'], 'Detroit, MI', 42.3314, -83.0458],
  ['rae', 'Rae Ortiz', '@raedrawsflowers', 0xffdb93a8, true, 391000, 63, 44,
    'One-line botanical stickers and prints.',
    ['#LGBTQOwned', '#DisabledOwned'], 'Hamtramck, MI', 42.3928, -83.0496],
  ['holler', 'Holler Goods', '@hollergoods', 0xffd96e9b, true, 1426000, 21, 33,
    'Embroidered caps and tees for people who love a legend.',
    ['#WomanOwned', '#VoteCollection'], 'Nashville, TN', 36.1627, -86.7816],
  ['ama', 'Ama Mensah', '@amashoots', 0xff6fb5a6, true, 1620000, 9, 27,
    'Brand photography for small makers.',
    ['#BIPOCOwned', '#WomanOwned', '#Services'], 'Detroit, MI', 42.3314, -83.0458],
  // The only buyer, and the reason the seller/buyer split is testable.
  ['dee', 'Dee Wells', '@deewells', 0xff93a9c4, false, 0, 88, 3,
    'Buyer. Mostly stickers.', [], 'Ferndale, MI', 42.4606, -83.1346],
];

const PRODUCTS = [
  ['p1', 'Cocoa Mint Lip Balm', 800, 'kali', 'Bath, Beauty & Wellness',
    ['#WomanOwned', '#BIPOCOwned', '#PlasticFree'], 4.9, 38,
    'Cocoa butter and peppermint in a compostable paper tube.'],
  ['p2', 'Wildflower Sticker Pack — 5 designs', 1200, 'rae', 'Art & Creative Goods',
    ['#LGBTQOwned', '#DisabledOwned'], 5.0, 26,
    'Five one-line botanicals. Vinyl, waterproof, dishwasher safe.'],
  ['p3', '“What Would Dolly Do?” Dad Hat', 2800, 'holler', 'Apparel & Accessories',
    ['#WomanOwned', '#VoteCollection'], 4.8, 52,
    'Unstructured six-panel in blush, embroidered in raspberry.'],
  ['p6', 'Brand photography — half day', 45000, 'ama', 'Services',
    ['#BIPOCOwned', '#WomanOwned', '#Services'], 4.9, 8,
    'Four hours, one location, 40 edited images.'],
];

const TAGS = [
  ['WomanOwned', '#WomanOwned', 2412],
  ['BIPOCOwned', '#BIPOCOwned', 1908],
  ['LGBTQOwned', '#LGBTQOwned', 1341],
  ['VoteCollection', '#VoteCollection', 1102],
  ['PlasticFree', '#PlasticFree', 984],
  ['DisabledOwned', '#DisabledOwned', 613],
];

/** Matches the geohash in both the app and the functions. */
function geohash(lat, lng, precision = 9) {
  const base32 = '0123456789bcdefghjkmnpqrstuvwxyz';
  let latMin = -90, latMax = 90, lngMin = -180, lngMax = 180;
  let hash = '', bit = 0, index = 0, even = true;

  while (hash.length < precision) {
    if (even) {
      const mid = (lngMin + lngMax) / 2;
      if (lng > mid) { index = index * 2 + 1; lngMin = mid; }
      else { index *= 2; lngMax = mid; }
    } else {
      const mid = (latMin + latMax) / 2;
      if (lat > mid) { index = index * 2 + 1; latMin = mid; }
      else { index *= 2; latMax = mid; }
    }
    even = !even;
    if (++bit === 5) { hash += base32[index]; bit = 0; index = 0; }
  }
  return hash;
}

async function seed() {
  const batch = db.batch();
  const peopleById = new Map();

  for (const [id, name, handle, tint, isSeller, revenueCents, purchaseCount,
    postCount, bio, tags, cityState, lat, lng] of PEOPLE) {
    peopleById.set(id, { handle, cityState, lat, lng });
    batch.set(db.collection('users').doc(id), {
      name, handle,
      handleLower: handle.replace('@', '').toLowerCase(),
      emailLower: `${id}@example.com`,
      tint, bio, tags, isSeller,
      revenueCents, purchaseCount, postCount,
      cityState, lat, lng,
      recentSearches: ['soy candle', '#PlasticFree'],
      createdAt: ago(90),
    });
  }

  for (const [id, title, priceCents, sellerId, type, tags, rating, ratingCount,
    description] of PRODUCTS) {
    const seller = peopleById.get(sellerId);
    batch.set(db.collection('catalog').doc(id), {
      title, titleLower: title.toLowerCase(),
      titleWords: [...new Set(title.toLowerCase().split(/[^a-z0-9]+/).filter(Boolean))],
      // The join key, as mirrorProduct writes it: the seller's display name
      // stands in for the Shopify vendor string on the demo backend.
      vendorName: seller.name,
      vendorKey: seller.name.trim().toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, ''),
      description, priceCents, sellerId, type,
      typeSlug: type.toLowerCase().replace(/[^a-z0-9]+/g, '-'),
      tags, rating, ratingCount,
      likeCount: 120, commentCount: 8,
      imageUrls: [],
      cityState: seller.cityState,
      lat: seller.lat, lng: seller.lng,
      geohash: geohash(seller.lat, seller.lng),
      sellerHandleLower: seller.handle.replace('@', '').toLowerCase(),
      active: true,
      createdAt: ago(30),
    });

    batch.set(db.collection('catalog').doc(id).collection('spec').doc('detail'), {
      subtitle: type,
      lead: 'Ships in 1–2 business days',
      rows: [{ label: 'Made in', value: seller.cityState }],
      shipping: [{ label: 'Processing', value: '1–2 business days' }],
      returns: '30-day returns.',
      variants: [
        { name: 'Default', variantId: `${id}-v1`, priceCents,
          availableForSale: true, quantityAvailable: 22 },
      ],
    });

    batch.set(
      db.collection('catalog').doc(id).collection('rating').doc('summary'),
      { stars5: 20, stars4: 4, stars3: 1, stars2: 0, stars1: 0 },
    );

    // The feed entry for this listing.
    batch.set(db.collection('posts').doc(`post_${id}`), {
      kind: 'listing',
      authorId: sellerId,
      productId: id,
      tags,
      likeCount: 120,
      commentCount: 8,
      createdAt: ago(0, PRODUCTS.indexOf(PRODUCTS.find((p) => p[0] === id)) * 3 + 1),
    });
  }

  // One of each other post kind, so the sealed Post switch is exercised live.
  batch.set(db.collection('posts').doc('post_review_1'), {
    kind: 'review',
    authorId: 'dee',
    productId: 'p1',
    rating: 5,
    text: 'Fourth tube. It survives a Michigan February.',
    tags: ['#PlasticFree'],
    likeCount: 46, commentCount: 3,
    createdAt: ago(0, 5),
  });

  batch.set(db.collection('posts').doc('post_shoutout_1'), {
    kind: 'shoutout',
    authorId: 'kali',
    text: 'Book @amashoots before the holiday push. She shot my whole line.',
    aboutSellerId: 'ama',
    tags: ['#BIPOCOwned', '#Services'],
    likeCount: 88, commentCount: 7,
    createdAt: ago(0, 14),
  });

  for (const [id, tag, postCount] of TAGS) {
    batch.set(db.collection('hashtags').doc(id), { tag, postCount });
  }

  batch.set(db.collection('forums').doc('f1'), {
    title: 'Vendor Corner',
    description: 'The catch-all for people who sell here.',
    memberCount: 312, threadCount: 1,
    createdBy: 'kali', createdAt: ago(60),
  });

  batch.set(db.collection('threads').doc('t1'), {
    forumId: 'f1',
    authorId: 'kali',
    title: 'How do you price handmade when materials cost 4x what they did?',
    body: 'Shea butter went from $9/lb to $34/lb in two years.',
    commentCount: 1,
    createdAt: ago(0, 6),
  });

  batch.set(
    db.collection('threads').doc('t1').collection('comments').doc('tc1'),
    {
      threadId: 't1',
      authorId: 'torres',
      text: 'Posted about it. One paragraph, no apology.',
      createdAt: ago(0, 5),
    },
  );

  for (const [i, text] of [
    'Anyone tabling at Eastern Market Sunday?',
    'I am in for Sunday. Bringing the seconds bin.',
    'Cocoa Mint restock is live.',
  ].entries()) {
    batch.set(db.collection('chatroom').doc(`chat${i}`), {
      conversationId: 'chatroom',
      authorId: ['rae', 'holler', 'kali'][i],
      text,
      createdAt: ago(0, 3 - i),
    });
  }

  // What dee bought, so the profile grid and the review composer have data.
  for (const [i, productId] of ['p1', 'p2', 'p3'].entries()) {
    batch.set(
      db.collection('users').doc('dee').collection('purchases')
        .doc(`order_1_${i}`),
      {
        orderId: 'order_1',
        productId,
        title: PRODUCTS.find((p) => p[0] === productId)?.[1] ?? productId,
        sellerId: PRODUCTS.find((p) => p[0] === productId)?.[3] ?? '',
        purchasedAt: ago(4 * (i + 1)),
        delivered: i > 0,
        reviewed: i === 0,
      },
    );
  }

  await batch.commit();
  console.log('Seeded the emulator. Run the app with:');
  console.log(
    '  flutter run --dart-define=LBM_BACKEND=live --dart-define=LBM_EMULATORS=true',
  );
}

seed().catch((error) => {
  console.error(error);
  process.exit(1);
});
