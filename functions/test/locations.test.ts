import { strict as assert } from 'node:assert';
import { test } from 'node:test';

import { pickStockLocation } from '../src/locations.ts';

/**
 * Opening stock at the wrong location reads "sold out" at checkout while the
 * admin shows plenty. The pick must prefer a location that fulfils online
 * orders, and otherwise the one the store's stock already lives at.
 */

test('a location that fulfils online orders wins over the first one listed', () => {
  assert.equal(
    pickStockLocation([
      { id: 'L-vendor', fulfillsOnlineOrders: false },
      { id: 'L-main', fulfillsOnlineOrders: true },
    ]),
    'L-main',
  );
});

test('without that flag, the busiest location wins', () => {
  assert.equal(
    pickStockLocation([
      { id: 'L-vendor', weight: 5 },
      { id: 'L-main', weight: 19 },
      { id: 'L-3p', weight: 2 },
    ]),
    'L-main',
  );
});

test('nothing known means no location, never a guess', () => {
  assert.equal(pickStockLocation([]), null);
});
