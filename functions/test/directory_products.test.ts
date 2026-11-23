import { strict as assert } from 'node:assert';
import { test } from 'node:test';

import { isApprovedBusiness, validateProduct } from '../src/directory_products.ts';

test('a clean product passes through, with the listing website as the default buy link', () => {
  const p = validateProduct(
    { title: '  Itinerary planning ', description: 'A custom trip plan.', priceCents: 15000, imageUrls: ['https://cdn.test/a.jpg'], tags: ['#Travel', '#Travel', ''] },
    'www.example.test/advisor',
  );
  assert.equal(p.title, 'Itinerary planning');
  assert.equal(p.priceCents, 15000);
  assert.equal(p.buyUrl, 'https://www.example.test/advisor');
  assert.deepEqual(p.tags, ['#Travel']);
  assert.deepEqual(p.imageUrls, ['https://cdn.test/a.jpg']);
});

test('what is refused: no name, a bad price, an http photo, and no buy link anywhere', () => {
  assert.throws(() => validateProduct({ title: '' }, 'https://x.test'), /Give the product a name/);
  assert.throws(() => validateProduct({ title: 'A', priceCents: -5 }, 'https://x.test'), /price does not look right/);
  assert.throws(() => validateProduct({ title: 'A', priceCents: 12.5 }, 'https://x.test'), /price does not look right/);
  assert.throws(() => validateProduct({ title: 'A', imageUrls: ['http://insecure.test/a.jpg'] }, 'https://x.test'), /https:\/\//);
  assert.throws(() => validateProduct({ title: 'A' }, ''), /web address/);
  assert.throws(() => validateProduct({ title: 'A', buyUrl: 'not a url at all' }, ''), /web address/);
});

test('a price of zero means "see the website", and is allowed', () => {
  const p = validateProduct({ title: 'Consultation', priceCents: 0, buyUrl: 'https://x.test/book' }, '');
  assert.equal(p.priceCents, 0);
  assert.equal(p.buyUrl, 'https://x.test/book');
});

test('only an approved business may add products: linked, owning, and with a published listing', () => {
  const linked = { status: 'linked', ownsListings: true };
  assert.equal(isApprovedBusiness(linked, ['publish']), true);
  assert.equal(isApprovedBusiness(linked, ['pending', 'publish']), true);
  // Grace, 2026-11-23: listings from businesses that are not approved.
  assert.equal(isApprovedBusiness(linked, ['pending']), false, 'a listing awaiting approval');
  assert.equal(isApprovedBusiness(linked, ['draft']), false);
  assert.equal(isApprovedBusiness(linked, []), false, 'a shopper the website knows, with no listing');
  assert.equal(isApprovedBusiness({ status: 'linked', ownsListings: false }, ['publish']), false, 'the staff account');
  assert.equal(isApprovedBusiness({ status: 'linked', ownershipLocked: true }, ['publish']), false, 'released by an admin');
  assert.equal(isApprovedBusiness({ status: 'notFound' }, ['publish']), false);
  assert.equal(isApprovedBusiness(undefined, ['publish']), false);
});
