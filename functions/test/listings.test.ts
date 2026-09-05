import { strict as assert } from 'node:assert';
import { test } from 'node:test';

import {
  draftTag,
  findExistingProduct,
  productSetInput,
  validateDraft,
} from '../src/listings.ts';

/**
 * The seller write path, tested where a mistake would reach a live store: the
 * vendor string, the price, the DRAFT status, and the idempotency tag.
 */

const draft = {
  sellerUid: 'kali',
  status: 'draft',
  title: '  Cocoa Mint Lip Balm ',
  description: 'Cocoa & mint.\nCompostable tube.',
  priceCents: 800,
  compareAtCents: 1000,
  quantity: 12,
  trackQuantity: true,
  continueSellingOOS: false,
  sku: 'BALM-01',
  weightGrams: 20,
  tags: ['feminist gift'],
  collectionHandles: ['bath-beauty-wellness'],
  imageUrls: ['https://firebasestorage/x.jpg'],
};

test('a draft must have a title, a positive whole-cent price and a photo', () => {
  assert.equal(validateDraft(draft), null);
  assert.equal(validateDraft({ ...draft, title: ' ' }), 'Give it a title.');
  assert.equal(validateDraft({ ...draft, priceCents: 0 }), 'Set a price above $0.');
  assert.equal(validateDraft({ ...draft, priceCents: 8.5 }), 'Set a price above $0.');
  assert.equal(validateDraft({ ...draft, priceCents: '800' }), 'Set a price above $0.');
  assert.equal(validateDraft({ ...draft, imageUrls: [] }), 'Add at least one photo.');
  assert.equal(validateDraft({ ...draft, quantity: -1 }), 'Quantity must be a whole number, zero or more.');
});

test('the productSet input is a DRAFT under the seller\'s vendor name, never the request\'s', () => {
  const input = productSetInput('L1', draft, 'Gwynstone', 'gid://shopify/Location/9') as any;
  assert.equal(input.status, 'DRAFT');
  assert.equal(input.vendor, 'Gwynstone');
  assert.equal(input.title, 'Cocoa Mint Lip Balm');
  assert.equal(input.descriptionHtml, 'Cocoa &amp; mint.<br>Compostable tube.');
  assert.deepEqual(input.tags, ['feminist gift', 'lbm:L1']);
  assert.deepEqual(input.collections, ['bath-beauty-wellness']);
  assert.deepEqual(input.files, [{ originalSource: 'https://firebasestorage/x.jpg', contentType: 'IMAGE' }]);
  assert.deepEqual(input.metafields, [
    { namespace: 'lbm', key: 'draft_id', type: 'single_line_text_field', value: 'L1' },
  ]);

  const [variant] = input.variants;
  assert.equal(variant.price, '8.00');
  assert.equal(variant.compareAtPrice, '10.00');
  assert.equal(variant.sku, 'BALM-01');
  assert.equal(variant.inventoryPolicy, 'DENY');
  assert.deepEqual(variant.inventoryQuantities, [{ locationId: 'gid://shopify/Location/9', quantity: 12 }]);
  assert.deepEqual(variant.inventoryItem.measurement, { weight: { unit: 'GRAMS', value: 20 } });
  assert.equal(variant.inventoryItem.tracked, true);
});

test('without a location the product is still created, just without opening stock', () => {
  const input = productSetInput('L1', draft, 'Gwynstone', null) as any;
  assert.equal('inventoryQuantities' in input.variants[0], false);
  assert.equal(input.status, 'DRAFT');
});

test('untracked stock never sends quantities', () => {
  const input = productSetInput('L1', { ...draft, trackQuantity: false }, 'Gwynstone', 'gid://shopify/Location/9') as any;
  assert.equal('inventoryQuantities' in input.variants[0], false);
  assert.equal(input.variants[0].inventoryItem.tracked, false);
});

test('a retry finds the product the first attempt made, by its tag', async () => {
  const seen: string[] = [];
  const graphql = async <T>(query: string, variables?: Record<string, unknown>): Promise<T> => {
    seen.push(String(variables?.q));
    return { products: { nodes: [{ id: 'gid://shopify/Product/777' }] } } as T;
  };
  assert.equal(await findExistingProduct(graphql, 'L1'), '777');
  assert.deepEqual(seen, [`tag:'${draftTag('L1')}'`]);

  const none = async <T>(): Promise<T> => ({ products: { nodes: [] } }) as T;
  assert.equal(await findExistingProduct(none, 'L1'), null);
});
