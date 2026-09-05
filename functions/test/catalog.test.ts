import { strict as assert } from 'node:assert';
import { test } from 'node:test';

import {
  autoPostFor,
  catalogDocFor,
  listingIdFromTags,
  productFromGraphQL,
  titleWords,
  type GraphQLProduct,
  type RestProduct,
} from '../src/catalog.ts';

test('a title becomes its distinct lowercase words, in order', () => {
  // The search screen matches one word with array-contains, so "snowboard"
  // must be present for "The Complete Snowboard" or search finds nothing.
  assert.deepEqual(titleWords('The Complete Snowboard'), ['the', 'complete', 'snowboard']);
  assert.deepEqual(titleWords('The Collection Snowboard: Hydrogen'), [
    'the', 'collection', 'snowboard', 'hydrogen',
  ]);
});

test('punctuation and repeats do not become words', () => {
  assert.deepEqual(titleWords("Kali's Lip Balm — lip balm, 2-pack!"), [
    'kali', 's', 'lip', 'balm', '2', 'pack',
  ]);
  assert.deepEqual(titleWords(''), []);
  assert.deepEqual(titleWords('   '), []);
});

// The same product, as the webhook sends it and as the backfill reads it.
const rest: RestProduct = {
  id: 15858163777696,
  title: 'The Complete Snowboard',
  body_html: '<p>Sturdy.</p><p>Fast.</p>',
  vendor: 'Snowboard Vendor',
  product_type: 'snowboard',
  tags: 'feminist gift, #WomanOwned, New',
  status: 'active',
  created_at: '2026-01-02T03:04:05Z',
  published_at: null,
  images: [{ src: 'https://cdn/1.jpg' }, { src: 'https://cdn/2.jpg' }],
  variants: [
    { id: 1, title: 'Ice', price: '699.95', available: true, inventory_quantity: 3 },
    { id: 2, title: 'Dawn', price: '699.95', available: false, inventory_quantity: 0 },
  ],
};

const graphql: GraphQLProduct = {
  id: 'gid://shopify/Product/15858163777696',
  title: 'The Complete Snowboard',
  descriptionHtml: '<p>Sturdy.</p><p>Fast.</p>',
  vendor: 'Snowboard Vendor',
  productType: 'snowboard',
  tags: ['feminist gift', '#WomanOwned', 'New'],
  status: 'ACTIVE',
  createdAt: '2026-01-02T03:04:05Z',
  publishedAt: null,
  images: { nodes: [{ url: 'https://cdn/1.jpg' }, { url: 'https://cdn/2.jpg' }] },
  variants: {
    nodes: [
      { id: 'gid://shopify/ProductVariant/1', title: 'Ice', price: '699.95', availableForSale: true, inventoryQuantity: 3 },
      { id: 'gid://shopify/ProductVariant/2', title: 'Dawn', price: '699.95', availableForSale: false, inventoryQuantity: 0 },
    ],
  },
  collections: { nodes: [{ handle: 'snowboards' }, { handle: 'ally-owned' }] },
};

test('the REST webhook and the GraphQL backfill produce the same document', () => {
  // Two code paths writing one collection is exactly how half a catalog ends
  // up with a different field set. This is the highest-value test in the
  // phase.
  const seller = { uid: 'kali', cityState: 'Detroit, MI', handleLower: 'kalibalm', lat: 42.3, lng: -83.0 };
  const fromRest = catalogDocFor(rest, seller, ['snowboards', 'ally-owned']);
  const fromGraphQL = catalogDocFor(productFromGraphQL(graphql), seller, ['ally-owned', 'snowboards']);
  assert.deepEqual(fromGraphQL, fromRest);
});

test('the adapter carries collections, lowercases status and flattens tags', () => {
  const adapted = productFromGraphQL(graphql);
  assert.equal(adapted.status, 'active');
  assert.equal(adapted.tags, 'feminist gift, #WomanOwned, New');
  assert.deepEqual(adapted.collectionHandles, ['snowboards', 'ally-owned']);
  assert.equal(adapted.id, '15858163777696');
});

test('every tag survives; only hashtags are initiative tags', () => {
  const { doc } = catalogDocFor(rest, undefined, []);
  assert.deepEqual(doc.productTags, ['feminist gift', '#WomanOwned', 'New']);
  assert.deepEqual(doc.tags, ['#WomanOwned']);
  assert.equal(doc.sellerId, '');
  assert.equal(doc.vendorKey, 'snowboard-vendor');
  assert.equal(doc.active, true);
  assert.equal(doc.description, 'Sturdy.\n\nFast.');
});

test('the app\'s own tags are bookkeeping, not product tags', () => {
  const { doc } = catalogDocFor({ ...rest, tags: 'gift, lbm:L1, lbm-touch, #WomanOwned' }, undefined, []);
  assert.deepEqual(doc.productTags, ['gift', '#WomanOwned']);
  assert.equal(listingIdFromTags(['gift', 'lbm:L1']), 'L1');
  assert.equal(listingIdFromTags(['gift']), null);
});

test('the spec keeps every variant with availability and stock', () => {
  const { spec } = catalogDocFor(rest, undefined, []);
  assert.deepEqual(spec.variants, [
    { name: 'Ice', variantId: '1', priceCents: 69995, availableForSale: true, quantityAvailable: 3 },
    { name: 'Dawn', variantId: '2', priceCents: 69995, availableForSale: false, quantityAvailable: 0 },
  ]);
});

test('a live, attributed product posts itself as its seller, with its initiative tags', () => {
  const { doc } = catalogDocFor(rest, { uid: 'kali' }, []);
  const post = autoPostFor('15858163777696', 'kali', doc) as any;
  assert.equal(post.kind, 'listing');
  assert.equal(post.authorId, 'kali');
  assert.equal(post.productId, '15858163777696');
  assert.deepEqual(post.tags, ['#WomanOwned']);
  assert.equal(post.auto, true);
  assert.equal(post.createdAt instanceof Date, true);
});

test('search words cover the description, not only the title', () => {
  const { doc } = catalogDocFor(rest, undefined, []);
  const words = doc.searchWords as string[];
  assert.ok(words.includes('snowboard'));
  assert.ok(words.includes('sturdy'));
  assert.ok(words.includes('fast'));
});
