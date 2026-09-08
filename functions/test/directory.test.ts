import { strict as assert } from 'node:assert';
import { test } from 'node:test';

import { Timestamp } from 'firebase-admin/firestore';

import {
  AUTO_MIN_AGE_MS,
  MANUAL_MIN_AGE_MS,
  NOT_FOUND_RECHECK_MS,
  mergeOrders,
  reuseStored,
  wcTimestamp,
} from '../src/directory.ts';
import type { WcOrderRecord } from '../src/wordpress.ts';

const NOW = Date.parse('2026-09-08T12:00:00Z');
const at = (msAgo: number) => Timestamp.fromMillis(NOW - msAgo);

function order(id: number, createdAt: string, billingEmail: string): WcOrderRecord {
  return {
    id, number: String(1000 + id), status: 'completed', createdAt, totalCents: 100, currency: 'USD',
    billingEmail, customerId: 0, items: [], viewUrl: '',
  };
}

test('a fresh linked answer is reused: ten minutes for a tap, six hours for the silent call', () => {
  const doc = { status: 'linked', wpLogin: 'grace', orderCount: 3, listingCount: 1, refreshedAt: at(60_000) };
  const tapped = reuseStored(doc, { auto: false, now: NOW });
  assert.equal(tapped?.status, 'alreadyLinked');
  assert.equal(tapped?.orders, 3);
  assert.match(tapped?.note ?? '', /few minutes/);
  const silent = reuseStored(doc, { auto: true, now: NOW });
  assert.equal(silent?.status, 'alreadyLinked');
  assert.equal(silent?.note, undefined);

  const older = { ...doc, refreshedAt: at(MANUAL_MIN_AGE_MS + 1) };
  assert.equal(reuseStored(older, { auto: false, now: NOW }), null);
  assert.equal(reuseStored(older, { auto: true, now: NOW })?.status, 'alreadyLinked');
  assert.equal(reuseStored({ ...doc, refreshedAt: at(AUTO_MIN_AGE_MS + 1) }, { auto: true, now: NOW }), null);
});

test('a stored "not found" is reused by the silent call for a week, never by a tap', () => {
  const doc = { status: 'notFound', checkedAt: at(86_400_000) };
  assert.equal(reuseStored(doc, { auto: true, now: NOW })?.status, 'notFound');
  assert.equal(reuseStored(doc, { auto: false, now: NOW }), null);
  assert.equal(reuseStored({ status: 'notFound', checkedAt: at(NOT_FOUND_RECHECK_MS + 1) }, { auto: true, now: NOW }), null);
  assert.equal(reuseStored(undefined, { auto: true, now: NOW }), null);
  assert.equal(reuseStored({}, { auto: true, now: NOW }), null);
});

test('mergeOrders keeps the customer\'s orders, adds exact-email guest orders, dedupes, newest first', () => {
  const byCustomer = [order(1, '2026-01-01T00:00:00', 'grace@example.test'), order(2, '2026-03-01T00:00:00', 'other@example.test')];
  const byEmail = [
    order(2, '2026-03-01T00:00:00', 'grace@example.test'),
    order(3, '2026-02-01T00:00:00', 'grace@example.test'),
    // A loose search hit on a note or a name, not this person's order.
    order(4, '2026-04-01T00:00:00', 'someone.else@example.test'),
  ];
  const merged = mergeOrders(byCustomer, byEmail, 'grace@example.test');
  assert.deepEqual(merged.map((o) => o.id), [2, 3, 1]);
});

test('WooCommerce GMT dates without a zone marker are read as UTC', () => {
  assert.equal(wcTimestamp('2026-09-01T12:00:00')?.toDate().toISOString(), '2026-09-01T12:00:00.000Z');
  assert.equal(wcTimestamp('2026-09-01T12:00:00Z')?.toDate().toISOString(), '2026-09-01T12:00:00.000Z');
  assert.equal(wcTimestamp(''), null);
  assert.equal(wcTimestamp('not a date'), null);
});
