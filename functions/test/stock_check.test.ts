import { strict as assert } from 'node:assert';
import { test } from 'node:test';

import { Timestamp } from 'firebase-admin/firestore';

import { correctedVariants, passDue, WEEK_MS } from '../src/stock_check.ts';

const store = (variantId: string, availableForSale: boolean, quantityAvailable: number | null) => ({
  variantId,
  productId: '1',
  availableForSale,
  quantityAvailable,
});

test('a variant whose stock the store changed is corrected, and counted', () => {
  const stored = [
    { name: 'Small', variantId: '11', priceCents: 1200, availableForSale: true, quantityAvailable: 3 },
    { name: 'Large', variantId: '12', priceCents: 1400, availableForSale: true, quantityAvailable: 2 },
  ];
  const { variants, changed } = correctedVariants(stored, [store('11', false, 0), store('12', true, 2)]);
  assert.equal(changed, 1);
  assert.deepEqual(variants[0], {
    name: 'Small', variantId: '11', priceCents: 1200, availableForSale: false, quantityAvailable: 0,
  });
  // Untouched, the very same object.
  assert.equal(variants[1], stored[1]);
});

test('a variant the store did not mention is left alone', () => {
  const stored = [{ variantId: '11', availableForSale: true, quantityAvailable: 3 }];
  assert.deepEqual(correctedVariants(stored, [store('99', false, 0)]), { variants: stored, changed: 0 });
});

test('an untracked quantity (null) matches a missing one', () => {
  const stored = [{ variantId: '11', availableForSale: true }];
  assert.equal(correctedVariants(stored, [store('11', true, null)]).changed, 0);
});

test('a pass starts a week after the last one started, never during one', () => {
  const now = Date.UTC(2026, 9, 5);
  assert.equal(passDue(undefined, now), true);
  assert.equal(passDue({ lastStartedAt: Timestamp.fromMillis(now - WEEK_MS) }, now), true);
  assert.equal(passDue({ lastStartedAt: Timestamp.fromMillis(now - WEEK_MS + 60_000) }, now), false);
  assert.equal(passDue({ active: true, lastStartedAt: Timestamp.fromMillis(0) }, now), false);
});
