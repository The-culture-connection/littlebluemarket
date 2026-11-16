import { strict as assert } from 'node:assert';
import { test } from 'node:test';

import { CURATED_COLLECTIONS, membershipDiff } from '../src/collections.ts';

// Grace, 2026-11-16: the Holiday Gift Guide in the app, product for product.
// Adding a product to a collection sends no webhook, so the mirror re-reads
// the curated ones and corrects itself.

test('a product put into a collection on the store gains the handle', () => {
  const diff = membershipDiff(['1', '2', '3'], ['1'], () => true);
  assert.deepEqual(diff.add, ['2', '3']);
  assert.deepEqual(diff.remove, []);
});

test('a product taken out on the store loses the handle', () => {
  const diff = membershipDiff(['1'], ['1', '9'], () => true);
  assert.deepEqual(diff.add, []);
  assert.deepEqual(diff.remove, ['9']);
});

test('a product the mirror has never seen is not invented', () => {
  const diff = membershipDiff(['1', '2'], [], (id) => id === '1');
  assert.deepEqual(diff.add, ['1']);
});

test('the curated list has no repeats', () => {
  assert.equal(new Set(CURATED_COLLECTIONS).size, CURATED_COLLECTIONS.length);
});
