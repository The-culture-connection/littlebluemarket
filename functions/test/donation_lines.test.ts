import { strict as assert } from 'node:assert';
import { test } from 'node:test';

import {
  DONATION_ATTRIBUTE,
  donationCentsIn,
  fundingMonth,
  isDonationItem,
  numericId,
} from '../src/donation_lines.ts';
import { normalizeOrder } from '../src/orders.ts';

/**
 * Telling a gift from a sale.
 *
 * The failure this guards against is the expensive one: a donation line
 * credited to a maker as revenue, or a maker's line mistaken for a donation
 * and never credited at all. Both are silent, and both are money.
 */

const resolve = async (hints: { vendor?: string; lineAttribute?: string }) => {
  if (hints.lineAttribute) return hints.lineAttribute;
  return { 'Kali Brooks': 'kali' }[hints.vendor ?? ''] ?? '';
};

const jam = {
  id: 1,
  product_id: 'p1',
  variant_id: 'v1',
  title: 'Spiced Plum Jam',
  price: '25.00',
  quantity: 1,
  vendor: 'Kali Brooks',
  requires_shipping: true,
};

/** Sixty pennies: the quantity is the amount. */
const roundUp = {
  id: 2,
  product_id: 'd9',
  variant_id: 'dv9',
  title: 'Round up for Little Blue Market',
  price: '0.01',
  quantity: 60,
  vendor: 'Little Blue Market',
  requires_shipping: false,
  properties: [{ name: DONATION_ATTRIBUTE, value: 'round-up' }],
};

void test('a line the app made says so itself, with no lookup', () => {
  assert.equal(isDonationItem(roundUp), true);
  // And says nothing about an ordinary line.
  assert.equal(isDonationItem(jam), false);
});

void test('a gift bought on the website is known by its product and its shipping', () => {
  const website = { ...roundUp, properties: undefined };
  const ids = new Set(['d9']);

  assert.equal(isDonationItem(website, ids), true);
  // Either test alone is wrong: a digital product that is not a donation
  // also needs no shipping, and a donation product's id is only a gift when
  // the line is not a physical thing somebody is owed.
  assert.equal(isDonationItem(website, new Set(['other'])), false);
  assert.equal(
    isDonationItem({ ...website, requires_shipping: true }, ids),
    false,
  );
});

void test('a paid order splits into a sale and a gift', async () => {
  const order = await normalizeOrder(
    {
      id: 5001,
      name: '#5001',
      created_at: '2026-09-29T12:00:00Z',
      financial_status: 'paid',
      total_price: '25.60',
      email: 'dee@example.com',
      line_items: [jam, roundUp],
    },
    resolve,
  );

  assert.equal(order.lines[0]?.donation, false);
  assert.equal(order.lines[0]?.sellerUid, 'kali');
  assert.equal(order.lines[1]?.donation, true);
  // No vendor on a gift. A line that carried one would be credited by the
  // paid webhook, which is the whole thing this prevents.
  assert.equal(order.lines[1]?.sellerUid, '');
});

void test('the vendor is credited for the jam and not for the round-up', async () => {
  const order = await normalizeOrder(
    {
      id: 5002,
      line_items: [jam, roundUp],
      total_price: '25.60',
      created_at: '2026-09-29T12:00:00Z',
    },
    resolve,
  );

  // The sum recordPaidOrder increments grossSalesCents by.
  const bySeller = new Map<string, number>();
  for (const line of order.lines) {
    if (line.donation || !line.sellerUid) continue;
    bySeller.set(
      line.sellerUid,
      (bySeller.get(line.sellerUid) ?? 0) + line.unitPriceCents * line.quantity,
    );
  }

  assert.equal(bySeller.get('kali'), 2500);
  assert.equal(donationCentsIn(order.lines), 60);
});

void test('a gift is counted once however many pennies it is', () => {
  assert.equal(donationCentsIn([]), 0);
  assert.equal(
    donationCentsIn([{ unitPriceCents: 1, quantity: 60, donation: true }]),
    60,
  );
  assert.equal(
    donationCentsIn([
      { unitPriceCents: 2500, quantity: 1 },
      { unitPriceCents: 500, quantity: 1, donation: true },
    ]),
    500,
  );
});

void test('a gift lands in the month it was paid for, in UTC', () => {
  assert.equal(fundingMonth(new Date('2026-09-29T12:00:00Z')), '2026-09');
  assert.equal(fundingMonth(new Date('2026-01-01T00:00:00Z')), '2026-01');
  // The turn of the year, which is where an off-by-one would show.
  assert.equal(fundingMonth(new Date('2025-12-31T23:59:59Z')), '2025-12');
});

void test('a product gid becomes the id a webhook line carries', () => {
  assert.equal(numericId('gid://shopify/Product/8123456789'), '8123456789');
  assert.equal(numericId(''), '');
});
