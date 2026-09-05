import { strict as assert } from 'node:assert';
import { test } from 'node:test';

import { markerChanges } from '../src/carted.ts';

/**
 * The cart-as-like signal. A product enters the public count when its first
 * line lands in a cart and leaves it when its last line goes; a second
 * variant of the same product is neither.
 */

test('a product is counted once however many of its variants are in the cart', () => {
  const before = [{ productId: 'p1' }];
  const after = [{ productId: 'p1' }, { productId: 'p1' }];
  assert.deepEqual(markerChanges(before, after), { added: [], removed: [] });
});

test('adding a new product marks it; removing its last line unmarks it', () => {
  assert.deepEqual(markerChanges([], [{ productId: 'p1' }]), { added: ['p1'], removed: [] });
  assert.deepEqual(markerChanges([{ productId: 'p1' }, { productId: 'p1' }], [{ productId: 'p1' }]), {
    added: [],
    removed: [],
  });
  assert.deepEqual(markerChanges([{ productId: 'p1' }], []), { added: [], removed: ['p1'] });
});

test('clearing a cart of three products removes all three', () => {
  const lines = [{ productId: 'a' }, { productId: 'b' }, { productId: 'c' }];
  assert.deepEqual(markerChanges(lines, []), { added: [], removed: ['a', 'b', 'c'] });
});
