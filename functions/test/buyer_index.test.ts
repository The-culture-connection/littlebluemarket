import { strict as assert } from 'node:assert';
import { test } from 'node:test';

import { Timestamp } from 'firebase-admin/firestore';

import { FRESH_MS, buyersFromPurchases, shouldAnnounce } from '../src/buyer_index.ts';

const NOW = Date.parse('2026-09-08T12:00:00Z');

test('a product is announced on its first transition to active, and only then', () => {
  const live = { active: true, sellerId: 'kali', title: 'Balm' };
  // Draft -> active: yes.
  assert.equal(shouldAnnounce({ active: false }, live, NOW), true);
  // Active -> active (a re-mirror, a price edit): no.
  assert.equal(shouldAnnounce({ active: true }, live, NOW), false);
  // Already stamped: no, whatever happened.
  assert.equal(shouldAnnounce({ active: false }, { ...live, announcedAt: Timestamp.fromMillis(NOW) }, NOW), false);
  // Not live, or nobody to credit: no.
  assert.equal(shouldAnnounce({ active: false }, { ...live, active: false }, NOW), false);
  assert.equal(shouldAnnounce({ active: false }, { ...live, sellerId: '' }, NOW), false);
  assert.equal(shouldAnnounce({ active: false }, undefined, NOW), false);
});

test('a brand-new mirror document is announced only when the product itself is minutes old', () => {
  const fresh = { active: true, sellerId: 'kali', createdAt: Timestamp.fromMillis(NOW - 60_000) };
  const old = { active: true, sellerId: 'kali', createdAt: Timestamp.fromMillis(NOW - FRESH_MS - 1) };
  assert.equal(shouldAnnounce(undefined, fresh, NOW), true);
  // The first deploy or a catalog backfill: nothing is announced.
  assert.equal(shouldAnnounce(undefined, old, NOW), false);
  assert.equal(shouldAnnounce(undefined, { active: true, sellerId: 'kali' }, NOW), false);
  // A string date from the webhook path counts the same way.
  assert.equal(shouldAnnounce(undefined, { active: true, sellerId: 'kali', createdAt: new Date(NOW - 5_000).toISOString() }, NOW), true);
});

test('buyersFromPurchases folds one person\'s purchases into per-seller entries, newest order kept', () => {
  const t = (ms: number) => Timestamp.fromMillis(NOW - ms);
  const entries = buyersFromPurchases([
    { sellerId: 'kali', orderId: '1001', purchasedAt: t(30_000) },
    { sellerId: 'kali', orderId: '1002', purchasedAt: t(10_000) },
    { sellerId: 'ama', orderId: '1003', purchasedAt: t(20_000) },
    { sellerId: '', orderId: '1004', purchasedAt: t(1_000) },
  ]);
  assert.deepEqual([...entries.keys()].sort(), ['ama', 'kali']);
  assert.equal(entries.get('kali')!.count, 2);
  assert.equal(entries.get('kali')!.lastOrderId, '1002');
  assert.equal(entries.get('ama')!.count, 1);
});
