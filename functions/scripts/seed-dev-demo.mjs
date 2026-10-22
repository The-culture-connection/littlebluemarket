#!/usr/bin/env node
//
// Fills the DEV project with clearly-test community content, so testers in
// the QA suite have people, posts, forums, threads and chat to look at.
//
//   npm run seed:dev-demo -- --dry-run   # prints every document it would write, writes nothing
//   npm run seed:dev-demo                # writes (or refreshes) the demo content on dev
//   npm run seed:dev-demo -- --remove    # deletes only what this script created
//   npm run seed:dev-demo -- --remove --dry-run   # lists what --remove would delete
//   npm run seed:dev-demo -- --verify    # reads back the counts the triggers moved
//
// DEV ONLY. The target must be exactly little-blue-610e5 or the script stops
// before it reads or writes anything. There is no flag to point it anywhere
// else, on purpose.
//
// Credentials: Application Default Credentials, the same as any Admin SDK
// tool (`gcloud auth application-default login` once, as an account that can
// edit the dev project). No service account key, ever (CLAUDE.md). The
// dry-run needs no credentials at all: without them it reads the public
// catalog and forums as a throwaway anonymous account, exactly as peek.mjs
// does, and says which safety checks it could not make.
//
// How it stays safe and repeatable:
//
//  * Every document it writes has an id starting `qa_seed_` and carries
//    `qaSeed: true`. --remove deletes a document only when both are true, and
//    takes its subcollections with it (comments, likes, members, the bell),
//    including anything a tester added underneath.
//  * Re-running updates in place. Counters the triggers own (postCount,
//    commentCount, likeCount, memberCount, threadCount) are written as zero
//    only when a document is first created and never touched again, so a
//    second run cannot reset a count the triggers have since moved.
//  * Documents are written the way the app writes them and the deployed
//    triggers do the counting, in dependency order: people, follows, forums,
//    memberships, posts, comments, threads, replies, chat.
//  * It only ever names seeded people. Mentions, shoutouts, forum members and
//    followers are all `qa_seed_` accounts with no phones, so the triggers'
//    notifications land in seeded bells and push to nobody. Hashtags that a
//    real account has asked to be told about are dropped before writing, and
//    threads are never put in a forum a real account belongs to.
//  * Products are never created. Listing, cart and review posts point at real
//    `catalog` documents (the mirror of the dev Shopify shop), so cards are
//    buyable. Review posts are written straight to `posts`, not under
//    `catalog/{id}/reviews`: a review there would move a real product's
//    rating and notify its real seller.
//
// Timestamps are spread over the last three weeks, relative to the moment of
// the run, so re-running also freshens the feed.

import { existsSync, readFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

import { arg, hasFlag, identityDelete, identitySignUp, resolveProject } from './lib/shopify-admin.mjs';

const DEV = 'little-blue-610e5';
const PREFIX = 'qa_seed_';
const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');

const DRY = hasFlag('dry-run');
const REMOVE = hasFlag('remove');
const VERIFY = hasFlag('verify');
const VERBOSE = hasFlag('verbose');

// ------------------------------------------------------------ the guard

const projectId = resolveProject(arg('project', 'dev'));
if (projectId !== DEV) {
  console.error(
    `REFUSED: this script only ever runs against ${DEV} (the dev project).\n` +
      `It was asked to run against "${projectId}". Nothing was read or written.`,
  );
  process.exit(2);
}
if (process.env.FIRESTORE_EMULATOR_HOST) {
  console.error(
    'REFUSED: FIRESTORE_EMULATOR_HOST is set, so the Admin SDK would write to the emulator, not dev.\n' +
      'For the emulator use `npm run seed`. To seed dev, open a fresh terminal without that variable.',
  );
  process.exit(2);
}
process.env.GCLOUD_PROJECT = DEV;
process.env.GOOGLE_CLOUD_PROJECT = DEV;

// ------------------------------------------------------- deterministic dice

/** A small seeded generator, so the same run plans the same content. */
function mulberry32(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
const rand = mulberry32(20261022);
const pick = (list) => list[Math.floor(rand() * list.length)];
const pickSome = (list, n) => {
  const copy = [...list];
  const out = [];
  while (out.length < n && copy.length) out.push(copy.splice(Math.floor(rand() * copy.length), 1)[0]);
  return out;
};

const NOW = Date.now();
const HOUR = 3600_000;
const DAY = 24 * HOUR;
/** A moment `hoursAgo` before the run, never in the future. */
const ago = (hoursAgo) => new Date(NOW - Math.max(0.05, hoursAgo) * HOUR);

// ------------------------------------------------------------ the people

// The avatar palette from FirestoreMappers.tintFor, so seeded avatars sit in
// the same family as everyone else's.
const TINTS = [0xff5c8fcb, 0xffa78bc9, 0xffdb93a8, 0xffd96e9b, 0xff6fb5a6, 0xffd69b62, 0xff86b98c, 0xff93a9c4];

const PEOPLE = [
  { slug: 'maya', name: 'Maya Brooks', city: 'Detroit, MI', tags: ['#candles', '#selfcare'], bio: 'Candle collector and Sunday market regular. Always hunting for the next great small shop.' },
  { slug: 'jordan', name: 'Jordan Ellis', city: 'Ann Arbor, MI', tags: ['#books', '#coffee'], bio: 'Grad student, bookstore wanderer, will travel for a good pour over.' },
  { slug: 'tasha', name: 'Tasha Greene', city: 'Cincinnati, OH', tags: ['#natural hair', '#skincare'], bio: 'Natural hair, clean skincare and honest reviews. If it works, I will tell you.' },
  { slug: 'marcus', name: 'Marcus Webb', city: 'Columbus, OH', tags: ['#menswear', '#grooming'], bio: 'Dad of two. Beard oil snob. Buying local whenever I can.' },
  { slug: 'priya', name: 'Priya Raman', city: 'Chicago, IL', tags: ['#homedecor', '#plants'], bio: 'Apartment plant jungle and too many throw pillows. Gift guide maker for my friends.' },
  { slug: 'dee', name: 'Deandra Hill', city: 'Atlanta, GA', tags: ['#jewelry', '#giftideas'], bio: 'Jewelry lover and the friend who always finds the perfect gift.' },
  { slug: 'luis', name: 'Luis Ortega', city: 'Houston, TX', tags: ['#hotsauce', '#kitchen'], bio: 'Home cook. Hot sauce shelf is getting out of hand. Send recommendations.' },
  { slug: 'kim', name: 'Kimberly Nguyen', city: 'Austin, TX', tags: ['#stationery', '#art'], bio: 'Illustrator and stationery hoarder. Small batch everything.' },
  { slug: 'andre', name: 'Andre Thompson', city: 'Charlotte, NC', tags: ['#fitness', '#wellness'], bio: 'Personal trainer. Supporting Black owned wellness brands one order at a time.' },
  { slug: 'sofia', name: 'Sofia Russo', city: 'Brooklyn, NY', tags: ['#vintage', '#fashion'], bio: 'Thrifter, vintage reseller in my spare time, forever chasing a good fabric.' },
  { slug: 'nia', name: 'Nia Coleman', city: 'Baltimore, MD', tags: ['#community', '#shopsmall'], bio: 'Community host for the forums. Ask me anything about getting started.' },
  { slug: 'ben', name: 'Ben Carter', city: 'Grand Rapids, MI', tags: ['#woodworking', '#outdoors'], bio: 'Weekend woodworker and camping gear tester. Grand Rapids born and raised.' },
].map((p, i) => ({
  ...p,
  uid: `${PREFIX}u_${p.slug}`,
  handle: `@qa_${p.slug}`,
  tint: TINTS[i % TINTS.length],
}));
const person = Object.fromEntries(PEOPLE.map((p) => [p.slug, p]));
const HOST = person.nia;

const QA_NOTE = ' (QA test profile on the dev project.)';
const lowerTags = (tags) => tags.map((t) => t.replace(/^#/, '').toLowerCase().replace(/\s+/g, ''));
// Tags in the app are single words: `#(\w+)`. Collapse any spaces.
const cleanTags = (tags) => tags.map((t) => `#${t.replace(/^#/, '').replace(/\s+/g, '')}`);

// --------------------------------------------------------- what to write

// Hashtags the posts may carry. Any a real account follows with notify on is
// dropped before writing, so no tester's phone buzzes for seeded content.
const POST_TAGS = ['#shopsmall', '#giftideas', '#handmade', '#selfcare', '#homedecor', '#blackowned', '#holidaygifts', '#smallbatch', '#treatyourself', '#qatest'];

const LISTING_CAPTIONS = [
  'Could not stop thinking about this one: {title}. Adding it to my holiday list.',
  'Saw {title} at a pop up last month and finally found it here.',
  'If you need a gift for the person who has everything, {title} is it.',
  'Restocked! {title} is back and I already ordered two.',
  'My sister asked where I got this. {title}, right here on Little Blue Market.',
  'Quality is unreal for the price. {title}.',
  'Treat yourself Tuesday: {title}.',
  'This is the one I keep recommending to everybody. {title}.',
  'Bought {title} as a gift and kept it for myself. No regrets.',
  'Small batch, made with care, and it shows. {title}.',
];

const CART_CAPTIONS = [
  'Holiday shopping, round one. Tell me what I missed.',
  'My cart right now. Self care weekend loading.',
  'Building a gift box for my mom. Thoughts?',
  'Everything in here is from a small shop. Proud of this one.',
  'Birthday wish list, in case anyone is wondering.',
  'Stocking stuffers, sorted.',
];

const SHOUTOUTS = [
  { by: 'maya', about: ['dee'], text: 'Huge shoutout to {0} for the gift recommendation. My aunt cried happy tears.' },
  { by: 'jordan', about: ['kim'], text: '{0} hand lettered the card that came with my order and I am keeping it forever.' },
  { by: 'tasha', about: ['andre', 'marcus'], text: 'Thank you {0} and {1} for the wellness shop list. Every single one was a winner.' },
  { by: 'priya', about: ['sofia'], text: '{0} has the best eye for vintage on this whole app. Follow her finds.' },
  { by: 'luis', about: ['ben'], text: 'Shoutout to {0} for the camping gear tips. The trip was a success.' },
  { by: 'nia', about: ['maya', 'jordan', 'tasha'], text: 'Welcome to the forums {0}, {1} and {2}. So glad you are here.' },
  { by: 'dee', about: ['priya'], text: '{0} put together a holiday gift guide that saved my whole December.' },
  { by: 'ben', about: ['luis'], text: 'Tried the hot sauce {0} recommended. My eyes are still watering. Ten out of ten.' },
  { by: 'sofia', about: ['nia'], text: 'Big love to {0} for keeping the community so kind and welcoming.' },
];

const REVIEW_TEXTS = [
  { rating: 5, text: 'Arrived fast, packed beautifully, and it is even better in person.' },
  { rating: 4, text: 'Really happy with it. Took a few extra days to ship but worth the wait.' },
  { rating: 5, text: 'Third time ordering. Consistent quality every time.' },
  { rating: 3, text: 'Nice, but smaller than I expected. Check the measurements before you buy.' },
  { rating: 5, text: 'Bought it as a gift and they loved it. The note from the maker was a lovely touch.' },
  { rating: 4, text: 'Great value. I would buy again.' },
];

const POST_COMMENTS = [
  'Ooh adding this to my list.',
  'Where has this been all my life?',
  'I have this one and it is so good.',
  'How is the sizing?',
  'This would make a great gift.',
  'Okay you sold me.',
  'Love this!',
  'Did it ship quickly?',
  'Need this in every colour.',
  'Supporting small shops is the way.',
];
const POST_REPLIES = [
  'Shipped in about three days for me.',
  'True to size, I think.',
  'Right?! I keep going back for more.',
  'Same here, ordering another one today.',
];

const EXTRA_THREADS = {
  'Getting Started Selling': { title: 'How many products did you launch with?', body: 'Ten? Fifty? One perfect one? Curious how everyone started.' },
  'Photos and Listings': { title: 'White background or lifestyle shots?', body: 'Which one gets you more clicks? Show an example if you can.' },
  'Small Business Finds': { title: 'Best stocking stuffer you found this year', body: 'Under $15 if possible. Tag the product.' },
  'Marketing and the Holiday Season': { title: 'Does anyone do local pop up markets?', body: 'Worth the table fee? How do you get people from the market to your shop online?' },
  'Shipping and Packaging': { title: 'Flat rate or calculated shipping?', body: 'What made you pick one over the other?' },
  'Wins and Shoutouts': { title: 'Your favourite review so far', body: 'Share the one that made your day.' },
};

const THREAD_REPLIES = [
  'Great question. For me it was word of mouth at first, then this app.',
  'I started small and added a few things every month.',
  'Following this one, so many good ideas in here.',
  'Honestly I wish I had started sooner.',
  'This thread is so helpful, thank you all.',
  'Totally agree with this.',
  'Saving this for later.',
  'I found this one last week and it is perfect for this.',
  'Tagging someone who will know the answer.',
  'Same experience here.',
];
const THREAD_SUBREPLIES = ['Yes! Exactly this.', 'Good tip, trying it this weekend.', 'Thanks, that helps a lot.', 'Ha, same.'];

const CHAT_LINES = [
  { by: 'nia', text: 'Good morning everyone! What are you shopping for this week?' },
  { by: 'maya', text: 'Candles, always candles.' },
  { by: 'jordan', text: 'Looking for a gift for my advisor. Something nice but not too much.' },
  { by: 'dee', text: 'Jordan check the stationery shops, a nice notebook never misses.', product: true },
  { by: 'kim', text: 'Seconding Dee. Also hand lettered cards.' },
  { by: 'luis', text: 'Anyone tried a hot sauce on here they would recommend?' },
  { by: 'ben', text: 'Luis I have a list. Messaging you after work.' },
  { by: 'tasha', text: 'Just left my first review, so nervous lol.' },
  { by: 'andre', text: 'Proud of you Tasha. Reviews help the shops so much.' },
  { by: 'priya', text: 'Working on a gift guide, drop your favourite find of the month.', product: true },
  { by: 'sofia', text: 'Found a vintage style piece I love, posting it later today.' },
  { by: 'marcus', text: 'Any beard oil recommendations from you all?' },
  { by: 'andre', text: 'Marcus I will send you mine, it is from a small shop in Charlotte.' },
  { by: 'nia', text: 'Reminder: the Wins and Shoutouts forum is a great place to celebrate each other.' },
  { by: 'maya', text: 'Have a great weekend everyone!' },
];

// ---------------------------------------------------------- the reader

/**
 * How the script reads and writes dev. With Application Default Credentials
 * it is the Admin SDK. Without them, only the dry-run can go on, reading
 * public collections as a throwaway anonymous account the way peek.mjs does.
 */
async function connect({ needWrite }) {
  const adcFiles = [
    process.env.APPDATA && join(process.env.APPDATA, 'gcloud', 'application_default_credentials.json'),
    join(homedir(), '.config', 'gcloud', 'application_default_credentials.json'),
  ].filter(Boolean);
  const haveAdc = Boolean(process.env.GOOGLE_APPLICATION_CREDENTIALS) || adcFiles.some((f) => existsSync(f));

  if (haveAdc) {
    const { initializeApp, applicationDefault } = await import('firebase-admin/app');
    const { getFirestore, Timestamp, FieldValue } = await import('firebase-admin/firestore');
    const app = initializeApp({ credential: applicationDefault(), projectId: DEV });
    const db = getFirestore(app);
    if (db.app.options.projectId !== DEV) {
      console.error(`REFUSED: the Admin SDK resolved project "${db.app.options.projectId}", not ${DEV}.`);
      process.exit(2);
    }
    return { kind: 'admin', db, Timestamp, FieldValue };
  }

  if (needWrite) {
    console.error(
      'CANNOT WRITE: no Application Default Credentials on this machine.\n' +
        'Run this once, signed in as an account that can edit the dev project, then try again:\n\n' +
        '    gcloud auth application-default login\n\n' +
        '(gcloud is the Google Cloud CLI: https://cloud.google.com/sdk/docs/install)\n' +
        'Never create a service account key for this. A dry-run works without any of it.',
    );
    process.exit(3);
  }
  return publicReader();
}

/** The dev web API key from firebase/config/dev, never from lib/ (run-live swaps that file). */
function devApiKey() {
  const src = readFileSync(join(REPO, 'firebase', 'config', 'dev', 'firebase_options.dart'), 'utf8');
  const web = src.slice(src.indexOf('FirebaseOptions web'));
  const key = web.match(/apiKey:\s*'([^']+)'/)?.[1];
  const project = web.match(/projectId:\s*'([^']+)'/)?.[1];
  if (project !== DEV || !key) {
    console.error(`REFUSED: firebase/config/dev does not describe ${DEV}.`);
    process.exit(2);
  }
  return key;
}

async function publicReader() {
  const apiKey = devApiKey();
  const who = await identitySignUp(apiKey, {});
  if (!who.idToken) {
    console.error(`Could not sign in anonymously to read dev: ${who.error}`);
    process.exit(1);
  }
  const base = `https://firestore.googleapis.com/v1/projects/${DEV}/databases/(default)/documents`;
  const headers = { Authorization: `Bearer ${who.idToken}` };
  const unwrap = (value) => {
    if (value == null) return null;
    const [kind, inner] = Object.entries(value)[0];
    switch (kind) {
      case 'integerValue': return Number(inner);
      case 'arrayValue': return (inner.values ?? []).map(unwrap);
      case 'mapValue': return Object.fromEntries(Object.entries(inner.fields ?? {}).map(([k, v]) => [k, unwrap(v)]));
      case 'nullValue': return null;
      default: return inner;
    }
  };
  const fields = (doc) => Object.fromEntries(Object.entries(doc.fields ?? {}).map(([k, v]) => [k, unwrap(v)]));
  async function list(path, max = 5000) {
    const out = [];
    let token = '';
    do {
      const url = `${base}/${path}?pageSize=300${token ? `&pageToken=${encodeURIComponent(token)}` : ''}`;
      const json = await (await fetch(url, { headers })).json();
      if (json.error) throw new Error(`${path}: ${json.error.message}`);
      for (const d of json.documents ?? []) out.push({ id: d.name.split('/').pop(), data: fields(d) });
      token = json.nextPageToken ?? '';
    } while (token && out.length < max);
    return out;
  }
  return {
    kind: 'public',
    list,
    close: () => identityDelete(apiKey, who.idToken),
  };
}

/** Every document in a collection as { id, data }, through whichever reader. */
async function listAll(conn, path) {
  if (conn.kind === 'public') return conn.list(path);
  const snap = await conn.db.collection(path).get();
  return snap.docs.map((d) => ({ id: d.id, data: d.data() }));
}

// ------------------------------------------------------------- planning

/** Real catalog products a seeded card can point at and a tester can buy. */
function usableProducts(rows) {
  return rows
    .filter(({ data }) =>
      data.active !== false &&
      (data.status ?? 'active') === 'active' &&
      !data.deletedAt &&
      Number(data.priceCents) > 0 &&
      Array.isArray(data.imageUrls) && data.imageUrls.length > 0 &&
      !/donat|chip in|membership|gift card|test product/i.test(String(data.title ?? '')))
    .sort((a, b) => a.id.localeCompare(b.id))
    .map(({ id, data }) => ({
      id,
      title: String(data.title ?? 'Untitled'),
      priceCents: Number(data.priceCents),
      sellerId: String(data.sellerId ?? ''),
      imageUrl: String(data.imageUrls[0]),
    }));
}

/**
 * The whole plan: a list of { path, data, counters, phase, label }. `counters`
 * are trigger-owned fields, written only if the document does not exist yet.
 */
function buildPlan({ products, starterForums, blockedTags, busyForums }) {
  const writes = [];
  const add = (phase, path, data, counters = {}, label = '') =>
    writes.push({ phase, path, data: { ...data, qaSeed: true }, counters, label });

  const tags = POST_TAGS.filter((t) => !blockedTags.has(t.replace(/^#/, '').toLowerCase()));
  const tagPair = () => pickSome(tags, 1 + Math.floor(rand() * 2));
  const product = () => pick(products);

  // 1. People. Created a few weeks back so they predate their posts.
  PEOPLE.forEach((p, i) => {
    const t = cleanTags(p.tags);
    add('1 people', `users/${p.uid}`, {
      name: p.name,
      nameLower: p.name.toLowerCase(),
      handle: p.handle,
      handleLower: p.handle.replace(/^@/, '').toLowerCase(),
      bio: p.bio + QA_NOTE,
      cityState: p.city,
      tags: t,
      tagsLower: lowerTags(t),
      tint: p.tint,
      createdAt: ago(24 * (24 + (i % 4))),
      updatedAt: ago(24 * (21 - (i % 5))),
    }, { revenueCents: 0, grossSalesCents: 0, purchaseCount: 0, postCount: 0 }, `${p.name} ${p.handle}, ${p.city}`);
  });

  // 2. Follows: each person follows three to five others.
  for (const p of PEOPLE) {
    const others = PEOPLE.filter((o) => o.slug !== p.slug);
    for (const o of pickSome(others, 3 + Math.floor(rand() * 3))) {
      add('2 follows', `users/${p.uid}/following/${o.uid}`, {
        personId: o.uid,
        createdAt: ago(24 * (14 + rand() * 6)),
      }, {}, `${p.handle} follows ${o.handle}`);
    }
  }

  // 3. Forums: the six starters, by title, only where dev does not already
  // have that title. Created by the community host, as the admin button would.
  const forums = []; // { id, title, starter }
  const existingByTitle = new Map(starterForums.existing.map((f) => [f.title.trim().toLowerCase(), f]));
  for (const f of starterForums.starters) {
    const there = existingByTitle.get(f.title.trim().toLowerCase());
    if (there) {
      forums.push({ id: there.id, title: f.title, ours: false, starter: f });
      continue;
    }
    const id = `${PREFIX}f_${f.title.toLowerCase().replace(/[^a-z0-9]+/g, '_').replace(/^_|_$/g, '')}`;
    forums.push({ id, title: f.title, ours: true, starter: f });
    add('3 forums', `forums/${id}`, {
      title: f.title,
      description: f.description,
      tags: f.tags,
      createdBy: HOST.uid,
      createdAt: ago(24 * 21),
    }, { memberCount: 0, threadCount: 0 }, f.title);
  }

  // 4. Memberships. A forum that already exists and has a real member gets
  // no seeded threads (each new thread would notify that member).
  const threadForums = forums.filter((f) => f.ours || !busyForums.has(f.id));
  for (const f of forums) {
    const members = f.ours ? [HOST, ...pickSome(PEOPLE.filter((p) => p !== HOST), 4 + Math.floor(rand() * 5))] : [];
    for (const m of members) {
      add('4 members', `forums/${f.id}/members/${m.uid}`, { joinedAt: ago(24 * (20 - rand() * 3)) }, {}, `${m.handle} joins ${f.title}`);
    }
  }

  // 5. Posts, spread over three weeks.
  const posts = [];
  const postAt = () => 2 + rand() * 24 * 20;
  let n = 0;
  const postId = (kind) => `${PREFIX}p_${String(++n).padStart(2, '0')}_${kind}`;

  for (let i = 0; i < 10; i++) {
    const author = PEOPLE[i % PEOPLE.length];
    const pr = product();
    const id = postId('listing');
    const at = postAt();
    posts.push({ id, at, author });
    add('5 posts', `posts/${id}`, {
      kind: 'listing',
      authorId: author.uid,
      productId: pr.id,
      caption: LISTING_CAPTIONS[i].replace('{title}', pr.title),
      tags: tagPair(),
      createdAt: ago(at),
    }, { likeCount: 0, commentCount: 0 }, `listing by ${author.handle} on "${pr.title}"`);
  }
  for (let i = 0; i < CART_CAPTIONS.length; i++) {
    const author = PEOPLE[(i * 5 + 2) % PEOPLE.length];
    const items = pickSome(products, 2 + Math.floor(rand() * 3));
    const id = postId('cart');
    const at = postAt();
    posts.push({ id, at, author });
    add('5 posts', `posts/${id}`, {
      kind: 'cart',
      authorId: author.uid,
      caption: CART_CAPTIONS[i],
      items: items.map((it) => ({
        productId: it.id,
        title: it.title,
        imageUrl: it.imageUrl,
        sellerId: it.sellerId,
        priceCents: it.priceCents,
      })),
      itemCount: items.length,
      tags: tagPair(),
      createdAt: ago(at),
    }, { likeCount: 0, commentCount: 0 }, `cart by ${author.handle}, ${items.length} items`);
  }
  for (const s of SHOUTOUTS) {
    const author = person[s.by];
    const named = s.about.map((slug) => person[slug]);
    let text = s.text;
    named.forEach((p, k) => { text = text.replace(`{${k}}`, p.handle); });
    const id = postId('shoutout');
    const at = postAt();
    const allowed = ['#shopsmall', '#community', '#wins'].filter((tag) => !blockedTags.has(tag.slice(1)));
    const tag = allowed.length ? pick(allowed) : '';
    posts.push({ id, at, author });
    add('5 posts', `posts/${id}`, {
      kind: 'shoutout',
      authorId: author.uid,
      text: tag ? `${text} ${tag}` : text,
      mentionedUids: named.map((p) => p.uid),
      tags: tag ? [tag] : [],
      createdAt: ago(at),
    }, { likeCount: 0, commentCount: 0 }, `shoutout by ${author.handle} naming ${named.map((p) => p.handle).join(', ')}`);
  }
  REVIEW_TEXTS.forEach((r, i) => {
    const author = PEOPLE[(i * 7 + 3) % PEOPLE.length];
    const pr = products[(i * 3 + 1) % products.length];
    const id = postId('review');
    const at = postAt();
    posts.push({ id, at, author });
    add('5 posts', `posts/${id}`, {
      kind: 'review',
      authorId: author.uid,
      productId: pr.id,
      rating: r.rating,
      text: r.text,
      purchaseId: null,
      imageUrls: [],
      tags: tagPair().slice(0, 1),
      createdAt: ago(at),
    }, { likeCount: 0, commentCount: 0 }, `${r.rating} star review by ${author.handle} of "${pr.title}"`);
  });

  // 6. Comments on about two thirds of the posts, some threaded.
  posts.forEach((post, i) => {
    if (i % 3 === 2) return;
    const count = 1 + Math.floor(rand() * 4);
    const commenters = pickSome(PEOPLE.filter((p) => p !== post.author), count);
    let first = null;
    commenters.forEach((c, k) => {
      const id = `${PREFIX}c_${post.id.slice(PREFIX.length)}_${k + 1}`;
      const at = Math.max(0.1, post.at - (k + 1) * (1 + rand() * 6));
      add('6 comments', `posts/${post.id}/comments/${id}`, {
        postId: post.id,
        authorId: c.uid,
        text: POST_COMMENTS[(i + k) % POST_COMMENTS.length],
        createdAt: ago(at),
      }, { likeCount: 0 }, `${c.handle} on ${post.id}`);
      if (k === 0) first = { id, at };
    });
    if (first && i % 2 === 0) {
      const id = `${PREFIX}c_${post.id.slice(PREFIX.length)}_r`;
      add('6 comments', `posts/${post.id}/comments/${id}`, {
        postId: post.id,
        authorId: post.author.uid,
        text: POST_REPLIES[i % POST_REPLIES.length],
        parentId: first.id,
        createdAt: ago(Math.max(0.05, first.at - 1 - rand() * 3)),
      }, { likeCount: 0 }, `${post.author.handle} replies on ${post.id}`);
    }
  });

  // 7. Threads: the starter threads (in forums this script creates) plus one
  // conversation starter per forum, each with replies.
  const threads = [];
  let t = 0;
  for (const f of threadForums) {
    const list = [
      ...(f.ours ? f.starter.threads.map((th) => ({ ...th, author: HOST })) : []),
      { ...EXTRA_THREADS[f.title], author: pick(PEOPLE.filter((p) => p !== HOST)) },
    ].filter((th) => th.title);
    for (const th of list) {
      const id = `${PREFIX}t_${String(++t).padStart(2, '0')}`;
      const at = 24 * (3 + rand() * 17);
      const tagged = rand() < 0.4 ? pickSome(products, 1 + Math.floor(rand() * 2)) : [];
      threads.push({ id, at, author: th.author, forumId: f.id });
      add('7 threads', `threads/${id}`, {
        forumId: f.id,
        authorId: th.author.uid,
        title: th.title,
        body: th.body,
        createdAt: ago(at),
        ...(tagged.length ? { productIds: tagged.map((p) => p.id) } : {}),
      }, { commentCount: 0 }, `"${th.title}" in ${f.title}`);
    }
  }

  // 8. Replies, some nested, some tagging a product or a seeded person.
  threads.forEach((th, i) => {
    const count = 2 + Math.floor(rand() * 4);
    const repliers = pickSome(PEOPLE.filter((p) => p !== th.author), count);
    repliers.forEach((r, k) => {
      const id = `${PREFIX}tc_${th.id.slice(PREFIX.length + 2)}_${k + 1}`;
      const at = Math.max(0.1, th.at - (k + 1) * (2 + rand() * 10));
      const tagProduct = k === 1 && rand() < 0.6;
      const tagPerson = k === 2 ? pick(PEOPLE.filter((p) => p !== r && p !== th.author)) : null;
      const pr = tagProduct ? product() : null;
      let text = THREAD_REPLIES[(i + k) % THREAD_REPLIES.length];
      if (tagPerson) text = `${tagPerson.handle} ${text}`;
      add('8 replies', `threads/${th.id}/comments/${id}`, {
        threadId: th.id,
        authorId: r.uid,
        text,
        createdAt: ago(at),
        ...(pr ? { productIds: [pr.id] } : {}),
        ...(tagPerson ? { mentionedUids: [tagPerson.uid] } : {}),
      }, {}, `${r.handle} in ${th.id}${pr ? ' tagging a product' : ''}${tagPerson ? ` naming ${tagPerson.handle}` : ''}`);
      if (k === 0 && i % 2 === 0) {
        add('8 replies', `threads/${th.id}/comments/${id}_r`, {
          threadId: th.id,
          authorId: th.author.uid,
          text: THREAD_SUBREPLIES[i % THREAD_SUBREPLIES.length],
          parentId: id,
          createdAt: ago(Math.max(0.05, at - 1 - rand() * 4)),
        }, {}, `${th.author.handle} answers in ${th.id}`);
      }
    });
  });

  // 9. The open chat room, over the last few days.
  CHAT_LINES.forEach((line, i) => {
    const at = 24 * 4 - i * (4 + rand() * 2);
    const pr = line.product ? product() : null;
    add('9 chatroom', `chatroom/${PREFIX}m_${String(i + 1).padStart(2, '0')}`, {
      conversationId: 'chatroom',
      authorId: person[line.by].uid,
      text: line.text,
      createdAt: ago(at),
      ...(pr ? { attachedProductId: pr.id } : {}),
    }, {}, `${person[line.by].handle}: ${line.text.slice(0, 40)}`);
  });

  return { writes, forums, threadForums, tags };
}

// ------------------------------------------------------------ safety reads

/** Tags with a non-seeded subscriber asking to be told. Admin only. */
async function tagsWithRealSubscribers(conn) {
  const blocked = new Set();
  if (conn.kind !== 'admin') return { blocked, checked: false };
  const keys = new Set([...POST_TAGS, '#shopsmall', '#community', '#wins'].map((t) => t.slice(1).toLowerCase()));
  for (const key of keys) {
    const subs = await conn.db.collection('hashtags').doc(key).collection('subscribers').select().limit(50).get();
    if (subs.docs.some((d) => !d.id.startsWith(PREFIX))) blocked.add(key);
  }
  return { blocked, checked: true };
}

/** Existing forums that have at least one non-seeded member. */
async function forumsWithRealMembers(conn, forumIds) {
  const busy = new Set();
  for (const id of forumIds) {
    const members = await listAll(conn, `forums/${id}/members`);
    if (members.some((m) => !m.id.startsWith(PREFIX))) busy.add(id);
  }
  return busy;
}

async function starterForumList() {
  // The compiled list is the source of truth when it is there; otherwise read
  // the titles straight out of the TypeScript, so a dry-run needs no build.
  try {
    const mod = await import('../lib/forum_seed.js');
    if (Array.isArray(mod.STARTER_FORUMS)) return mod.STARTER_FORUMS;
  } catch {
    // fall through
  }
  const src = readFileSync(join(REPO, 'functions', 'src', 'forum_seed.ts'), 'utf8');
  const body = src.slice(src.indexOf('STARTER_FORUMS'), src.indexOf('];', src.indexOf('STARTER_FORUMS')) + 1);
  const json = body
    .slice(body.indexOf('['))
    .replace(/\/\/.*$/gm, '')
    .replace(/([{,]\s*)([A-Za-z]+):/g, '$1"$2":')
    .replace(/'((?:[^'\\]|\\.)*)'/g, (_, s) => JSON.stringify(s.replace(/\\'/g, "'")))
    .replace(/,(\s*[}\]])/g, '$1');
  return JSON.parse(json);
}

// --------------------------------------------------------------- writing

async function writePlan(conn, writes) {
  const { db, Timestamp } = conn;
  const toFs = (value) => {
    if (value instanceof Date) return Timestamp.fromDate(value);
    if (Array.isArray(value)) return value.map(toFs);
    if (value && typeof value === 'object') return Object.fromEntries(Object.entries(value).map(([k, v]) => [k, toFs(v)]));
    return value;
  };

  const phases = [...new Set(writes.map((w) => w.phase))].sort();
  const tally = { created: 0, updated: 0 };
  for (const phase of phases) {
    const group = writes.filter((w) => w.phase === phase);
    // Which already exist decides whether the counters are written.
    const refs = group.map((w) => db.doc(w.path));
    const exists = new Map();
    for (let i = 0; i < refs.length; i += 300) {
      const snaps = await db.getAll(...refs.slice(i, i + 300));
      for (const s of snaps) exists.set(s.ref.path, s.exists);
    }
    for (let i = 0; i < group.length; i += 400) {
      const batch = db.batch();
      for (const w of group.slice(i, i + 400)) {
        const isNew = !exists.get(w.path);
        const data = toFs(isNew ? { ...w.data, ...w.counters } : w.data);
        batch.set(db.doc(w.path), data, { merge: true });
        if (isNew) tally.created++; else tally.updated++;
      }
      await batch.commit();
    }
    console.log(`  ${phase.padEnd(12)} ${String(group.length).padStart(4)} written`);
    // Parents are committed before their children, so a trigger counting a
    // child always finds the parent. A short pause lets the counting
    // triggers keep up rather than queueing all at once.
    await new Promise((r) => setTimeout(r, 1500));
  }
  return tally;
}

// --------------------------------------------------------------- removing

/** Every seeded top-level document: id prefix AND the qaSeed flag. */
async function findSeeded(conn) {
  const found = [];
  for (const col of ['chatroom', 'threads', 'posts', 'forums', 'users']) {
    const rows = await listAll(conn, col).catch(() => []);
    // listAll on users/posts reads everything once; dev is small enough.
    for (const r of rows) {
      if (r.id.startsWith(PREFIX) && r.data.qaSeed === true) found.push(`${col}/${r.id}`);
    }
  }
  return found;
}

async function removeSeeded(conn) {
  const paths = await findSeeded(conn);
  const byCol = {};
  for (const p of paths) byCol[p.split('/')[0]] = (byCol[p.split('/')[0]] ?? 0) + 1;
  console.log('Seeded documents found (with everything under them):');
  for (const [col, count] of Object.entries(byCol)) console.log(`  ${col.padEnd(10)} ${count}`);
  if (!paths.length) {
    console.log('  nothing to remove');
    return;
  }
  if (DRY || conn.kind !== 'admin') {
    for (const p of paths) console.log(`  would delete ${p}`);
    console.log('\nDry run: nothing deleted.');
    return;
  }
  // Children before parents, so the counting triggers find nothing to bump
  // rather than resurrecting a parent: chat, then replies with their
  // threads, then comments with their posts, then forums, then people.
  for (const p of paths) {
    await conn.db.recursiveDelete(conn.db.doc(p));
  }
  console.log(`\nRemoved ${paths.length} seeded documents and everything under them.`);
}

// --------------------------------------------------------------- verifying

async function verify(conn) {
  const users = (await listAll(conn, 'users')).filter((r) => r.id.startsWith(PREFIX));
  const posts = (await listAll(conn, 'posts')).filter((r) => r.id.startsWith(PREFIX));
  const forums = await listAll(conn, 'forums');
  const threads = (await listAll(conn, 'threads')).filter((r) => r.id.startsWith(PREFIX));
  const chat = (await listAll(conn, 'chatroom')).filter((r) => r.id.startsWith(PREFIX));

  let postComments = 0;
  let postCommentCounts = 0;
  for (const p of posts) {
    postComments += (await listAll(conn, `posts/${p.id}/comments`)).length;
    postCommentCounts += Number(p.data.commentCount ?? 0);
  }
  let replies = 0;
  let replyCounts = 0;
  for (const t of threads) {
    replies += (await listAll(conn, `threads/${t.id}/comments`)).length;
    replyCounts += Number(t.data.commentCount ?? 0);
  }
  const kinds = {};
  for (const p of posts) kinds[p.data.kind] = (kinds[p.data.kind] ?? 0) + 1;
  const postCountSum = users.reduce((s, u) => s + Number(u.data.postCount ?? 0), 0);
  const touched = new Set(threads.map((t) => t.data.forumId));

  console.log('Read back from dev:');
  console.log(`  people             ${users.length}  (postCount across them: ${postCountSum})`);
  console.log(`  posts              ${posts.length}  ${JSON.stringify(kinds)}`);
  console.log(`  post comments      ${postComments}  (commentCount on the posts: ${postCommentCounts})`);
  console.log(`  forums with seeded threads ${touched.size}`);
  for (const f of forums.filter((f) => touched.has(f.id) || f.id.startsWith(PREFIX))) {
    const seededThreads = threads.filter((t) => t.data.forumId === f.id).length;
    console.log(`    ${String(f.data.title).padEnd(36)} members ${f.data.memberCount ?? 0}, threads ${f.data.threadCount ?? 0} (${seededThreads} seeded)`);
  }
  console.log(`  threads            ${threads.length}`);
  console.log(`  thread replies     ${replies}  (commentCount on the threads: ${replyCounts})`);
  console.log(`  chatroom messages  ${chat.length}`);
  if (postComments !== postCommentCounts || replies !== replyCounts) {
    console.log('  note: a count differs from what is there. Triggers can take a minute; run --verify again.');
  }
}

// ------------------------------------------------------------------- main

const conn = await connect({ needWrite: !DRY && (REMOVE || !VERIFY) });
console.log(`Project ${DEV} (dev). Reading as: ${conn.kind === 'admin' ? 'Admin SDK, application default credentials' : 'a throwaway anonymous account (public reads only)'}.`);
try {
  if (VERIFY) {
    await verify(conn);
  } else if (REMOVE) {
    await removeSeeded(conn);
  } else {
    const products = usableProducts(await listAll(conn, 'catalog'));
    if (products.length < 4) {
      console.error(`Only ${products.length} usable catalog products on dev (active, priced, with a photo). Need at least 4.`);
      process.exit(1);
    }
    const starters = await starterForumList();
    const existingForums = (await listAll(conn, 'forums')).map((f) => ({ id: f.id, title: String(f.data.title ?? '') }));
    const starterTitles = new Set(starters.map((s) => s.title.trim().toLowerCase()));
    const existingStarters = existingForums.filter((f) => starterTitles.has(f.title.trim().toLowerCase()) && !f.id.startsWith(PREFIX));
    const busy = await forumsWithRealMembers(conn, existingStarters.map((f) => f.id));
    const { blocked, checked } = await tagsWithRealSubscribers(conn);

    const plan = buildPlan({
      products,
      starterForums: { starters, existing: existingStarters },
      blockedTags: blocked,
      busyForums: busy,
    });

    console.log(`\n${products.length} usable catalog products on dev; seeded cards point at real ones.`);
    console.log(`Starter forums already on dev (left alone): ${existingStarters.map((f) => f.title).join(', ') || 'none'}`);
    if (busy.size) {
      console.log(`  with real members, so no seeded threads go there: ${existingStarters.filter((f) => busy.has(f.id)).map((f) => f.title).join(', ')}`);
    }
    console.log(`Hashtags used: ${plan.tags.join(' ')}`);
    if (checked) {
      console.log(`  dropped because a real account follows them: ${[...blocked].map((k) => `#${k}`).join(' ') || 'none'}`);
    } else {
      console.log('  NOT CHECKED for real followers (needs Admin credentials). The real run checks before writing.');
    }

    const byPhase = {};
    for (const w of plan.writes) byPhase[w.phase] = (byPhase[w.phase] ?? 0) + 1;
    console.log('\nDocuments, in write order:');
    for (const [phase, count] of Object.entries(byPhase).sort()) console.log(`  ${phase.padEnd(12)} ${String(count).padStart(4)}`);
    console.log(`  ${'total'.padEnd(12)} ${String(plan.writes.length).padStart(4)}`);

    if (DRY) {
      console.log('\nEvery document (path: what it is):');
      for (const w of plan.writes) {
        console.log(`  ${w.path}: ${w.label}`);
        if (VERBOSE) console.log(`      ${JSON.stringify({ ...w.data, ...w.counters })}`);
      }
      console.log('\nDry run: nothing written. Add --verbose to see every field.');
    } else {
      console.log('\nWriting...');
      const tally = await writePlan(conn, plan.writes);
      console.log(`\nDone: ${tally.created} created, ${tally.updated} refreshed. Triggers are counting now; run with --verify in a minute.`);
    }
  }
} finally {
  if (conn.kind === 'public') await conn.close();
}
