import { strict as assert } from 'node:assert';
import { test } from 'node:test';

import { statusFromStore, updateMutations, type StoreProduct } from '../src/listing_updates.ts';

/**
 * Editing an existing product. The assertion that matters: `productSet` is
 * never used on an existing product, because it deletes every variant and
 * option the input omits.
 */

const product: StoreProduct = {
  id: 'gid://shopify/Product/777',
  variants: {
    nodes: [
      { id: 'gid://shopify/ProductVariant/1', inventoryItem: { id: 'gid://shopify/InventoryItem/11' } },
    ],
  },
  collections: { nodes: [{ id: 'gid://shopify/Collection/old' }, { id: 'gid://shopify/Collection/keep' }] },
};

const draft = {
  title: 'Fall Crewneck',
  description: 'Warm & soft',
  priceCents: 3200,
  compareAtCents: 4000,
  quantity: 40,
  trackQuantity: true,
  sku: 'FALL-01',
  tags: ['fall'],
  categoryId: 'gid://shopify/TaxonomyCategory/aa-1-13-14',
};

test('an edit never calls productSet, and touches only what it names', () => {
  const mutations = updateMutations('L1', draft, product, 'gid://shopify/Location/9', [
    'gid://shopify/Collection/keep',
    'gid://shopify/Collection/new',
  ]);
  const names = mutations.map((m) => m.name);
  assert.equal(names.includes('productSet'), false);
  assert.equal(mutations.some((m) => m.query.includes('productSet')), false);
  assert.deepEqual(names, [
    'productUpdate',
    'productVariantsBulkUpdate',
    'inventorySetQuantities',
    'collectionAddProducts',
    'collectionRemoveProducts',
  ]);

  const update = mutations[0].variables.product as any;
  assert.equal(update.title, 'Fall Crewneck');
  assert.equal(update.descriptionHtml, 'Warm &amp; soft');
  assert.deepEqual(update.tags, ['fall', 'lbm:L1']);
  assert.equal(update.category, 'gid://shopify/TaxonomyCategory/aa-1-13-14');

  const variants = mutations[1].variables.variants as any[];
  assert.deepEqual(variants, [
    { id: 'gid://shopify/ProductVariant/1', price: '32.00', compareAtPrice: '40.00', inventoryItem: { sku: 'FALL-01' } },
  ]);

  const stock = mutations[2].variables.input as any;
  assert.equal(stock.name, 'available');
  assert.equal(stock.reason, 'correction');
  assert.deepEqual(stock.quantities, [
    { inventoryItemId: 'gid://shopify/InventoryItem/11', locationId: 'gid://shopify/Location/9', quantity: 40 },
  ]);

  assert.deepEqual(mutations[3].variables, { id: 'gid://shopify/Collection/new', productIds: ['gid://shopify/Product/777'] });
  assert.deepEqual(mutations[4].variables, { id: 'gid://shopify/Collection/old', productIds: ['gid://shopify/Product/777'] });
});

test('no location means no stock write, and untracked stock is left alone', () => {
  const noLocation = updateMutations('L1', draft, product, null, []).map((m) => m.name);
  assert.equal(noLocation.includes('inventorySetQuantities'), false);
  const untracked = updateMutations('L1', { ...draft, trackQuantity: false }, product, 'gid://shopify/Location/9', []).map((m) => m.name);
  assert.equal(untracked.includes('inventorySetQuantities'), false);
});

test('the store\'s status maps onto the chip', () => {
  assert.equal(statusFromStore('ACTIVE'), 'live');
  assert.equal(statusFromStore('DRAFT'), 'submitted');
  assert.equal(statusFromStore('ARCHIVED'), 'rejected');
  assert.equal(statusFromStore(null), 'rejected');
});
