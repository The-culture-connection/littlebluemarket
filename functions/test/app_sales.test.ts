import { strict as assert } from 'node:assert';
import { test } from 'node:test';

import {
  monthKey,
  orderFigures,
  sourcesFromNodes,
  summariseSales,
  type SalesOrder,
} from '../src/app_sales.ts';

/**
 * The admin page's App sales card. What must hold: an app sale is never
 * counted from a website order, a gift is never counted as a sale, and an
 * order nobody could sort is counted on neither side.
 */

const now = new Date('2026-10-21T12:00:00Z');

const balm = { unitPriceCents: 800, quantity: 2 };
const stickers = { unitPriceCents: 1200, quantity: 1 };
const roundUp = { unitPriceCents: 42, quantity: 1, donation: true };

function order(over: Partial<SalesOrder>): SalesOrder {
  return {
    source: 'app',
    placedAt: new Date('2026-10-10T09:00:00Z'),
    status: 'paid',
    lines: [balm],
    ...over,
  };
}

test('an order with a gift adds goods and gifts separately', () => {
  assert.deepEqual(orderFigures([balm, stickers, roundUp]), {
    orders: 1,
    itemsSold: 3,
    goodsCents: 2800,
    giftsCents: 42,
  });
});

test('a gift on its own is not a purchase', () => {
  assert.deepEqual(orderFigures([{ unitPriceCents: 500, quantity: 1, donation: true }]), {
    orders: 0,
    itemsSold: 0,
    goodsCents: 0,
    giftsCents: 500,
  });
});

test('app and website orders are counted apart', () => {
  const summary = summariseSales(
    [
      order({ lines: [balm, roundUp] }),
      order({ lines: [stickers] }),
      order({ source: 'website', lines: [balm, stickers] }),
    ],
    now,
  );
  assert.deepEqual(summary.app, { orders: 2, itemsSold: 3, goodsCents: 2800, giftsCents: 42 });
  assert.deepEqual(summary.website, { orders: 1, itemsSold: 3, goodsCents: 2800 });
});

test('unknown and unsorted orders count on neither side', () => {
  const summary = summariseSales(
    [order({ source: 'unknown' }), order({ source: undefined }), order({})],
    now,
  );
  assert.equal(summary.app.orders, 1);
  assert.equal(summary.website.orders, 0);
  assert.equal(summary.unknownOrders, 1);
  assert.equal(summary.unsorted, 1);
});

test('a refunded, voided or cancelled order is left out', () => {
  const summary = summariseSales(
    [
      order({ status: 'refunded' }),
      order({ status: 'voided' }),
      order({ status: 'cancelled' }),
      order({ status: 'fulfilled' }),
    ],
    now,
  );
  assert.equal(summary.app.orders, 1);
  assert.equal(summary.excluded, 3);
});

test('this month, the last 30 days and the six months are split by date', () => {
  const summary = summariseSales(
    [
      order({ placedAt: new Date('2026-10-01T00:00:00Z') }), // this month, within 30 days
      order({ placedAt: new Date('2026-09-25T00:00:00Z') }), // last month, within 30 days
      order({ placedAt: new Date('2026-09-01T00:00:00Z') }), // last month, outside 30 days
      order({ placedAt: new Date('2026-04-30T23:59:00Z') }), // seven months back
    ],
    now,
  );
  assert.equal(summary.app.orders, 4);
  assert.equal(summary.thisMonth.month, '2026-10');
  assert.equal(summary.thisMonth.orders, 1);
  assert.equal(summary.last30Days.orders, 2);
  assert.deepEqual(
    summary.months.map((m) => [m.month, m.orders]),
    [
      ['2026-10', 1],
      ['2026-09', 2],
      ['2026-08', 0],
      ['2026-07', 0],
      ['2026-06', 0],
      ['2026-05', 0],
    ],
  );
});

test('the six months cross a year boundary', () => {
  const summary = summariseSales([], new Date('2026-02-03T00:00:00Z'));
  assert.deepEqual(
    summary.months.map((m) => m.month),
    ['2026-02', '2026-01', '2025-12', '2025-11', '2025-10', '2025-09'],
  );
});

test('a month key is UTC', () => {
  // 31 October, 11pm in New York, is already November in UTC.
  assert.equal(monthKey(new Date('2026-11-01T03:00:00Z')), '2026-11');
});

test('Shopify answers sort orders by the app attribute', () => {
  const sources = sourcesFromNodes(
    ['1', '2', '3'],
    [
      { id: 'gid://shopify/Order/1', customAttributes: [{ key: 'app_uid', value: 'dee' }] },
      { id: 'gid://shopify/Order/2', customAttributes: [{ key: 'gift_note', value: 'hi' }] },
      null,
    ],
  );
  assert.equal(sources.get('1'), 'app');
  assert.equal(sources.get('2'), 'website');
  // Deleted, or too old to read: not guessed into either total.
  assert.equal(sources.get('3'), 'unknown');
});

test('an answer of the wrong length is refused rather than misaligned', () => {
  assert.throws(() => sourcesFromNodes(['1', '2'], [null]));
});
