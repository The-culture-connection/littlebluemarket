import { strict as assert } from 'node:assert';
import { test } from 'node:test';

import { normalizeOrder } from '../src/orders.ts';

/**
 * Order normalisation, tested against payloads shaped like the real thing.
 *
 * This is the function whose bugs corrupt money data, and the failures are the
 * quiet kind: a seller credited for someone else's line, a multi-vendor order
 * paying one vendor twice, a price read as zero. None of those throw.
 */

/** Stands in for the vendor lookup, which needs Firestore. */
const resolve = async (hints: {
  vendor?: string;
  lineAttribute?: string;
}): Promise<string> => {
  if (hints.lineAttribute) return hints.lineAttribute;
  return { 'Kali Brooks': 'kali', 'Rae Ortiz': 'rae' }[hints.vendor ?? ''] ?? '';
};

const baseOrder = {
  id: 4471,
  name: '#4471',
  created_at: '2026-06-15T12:00:00Z',
  financial_status: 'paid',
  total_price: '28.00',
  email: 'Dee@Example.com',
  line_items: [
    {
      id: 1,
      product_id: 'p1',
      variant_id: 'v1',
      title: 'Cocoa Mint Lip Balm',
      variant_title: 'Cocoa Mint',
      price: '8.00',
      quantity: 2,
      vendor: 'Kali Brooks',
    },
    {
      id: 2,
      product_id: 'p2',
      variant_id: 'v2',
      title: 'Wildflower Sticker Pack',
      variant_title: 'Pack of 5',
      price: '12.00',
      quantity: 1,
      vendor: 'Rae Ortiz',
    },
  ],
};

test('normalizes a two-vendor order', async () => {
  const order = await normalizeOrder(baseOrder, resolve);

  assert.equal(order.id, '4471');
  assert.equal(order.number, '#4471');
  assert.equal(order.totalCents, 2800);
  assert.equal(order.lines.length, 2);
  assert.equal(order.lines[0]?.unitPriceCents, 800);
  assert.equal(order.lines[0]?.quantity, 2);
});

test('each line carries its own seller', async () => {
  // The property that matters for a multi-vendor order: crediting one seller
  // for the whole basket is the failure this prevents.
  const order = await normalizeOrder(baseOrder, resolve);
  assert.equal(order.lines[0]?.sellerUid, 'kali');
  assert.equal(order.lines[1]?.sellerUid, 'rae');
});

test('revenue splits per seller, not per order', async () => {
  const order = await normalizeOrder(baseOrder, resolve);

  const bySeller = new Map<string, number>();
  for (const line of order.lines) {
    bySeller.set(
      line.sellerUid,
      (bySeller.get(line.sellerUid) ?? 0) + line.unitPriceCents * line.quantity,
    );
  }
  assert.equal(bySeller.get('kali'), 1600); // 2 x $8
  assert.equal(bySeller.get('rae'), 1200); // 1 x $12
  // And the two together are the order total, so nothing is lost or doubled.
  assert.equal([...bySeller.values()].reduce((a, b) => a + b, 0), 2800);
});

test('an app order is self-identifying', async () => {
  const order = await normalizeOrder(
    { ...baseOrder, note_attributes: [{ name: 'app_uid', value: 'dee' }] },
    resolve,
  );
  assert.equal(order.buyerUid, 'dee');
});

test('a website order carries no uid and falls back to its email', async () => {
  const order = await normalizeOrder(baseOrder, resolve);
  assert.equal(order.buyerUid, null);
  // Kept as sent; the lookup lowercases. This is what makes a purchase made on
  // the website appear on the buyer's app profile.
  assert.equal(order.buyerEmail, 'Dee@Example.com');
});

test('a line attribute beats the vendor name', async () => {
  // An app order stamps the seller on the line, so no lookup is needed and no
  // vendor-name ambiguity can misattribute it.
  const order = await normalizeOrder(
    {
      ...baseOrder,
      line_items: [
        {
          ...baseOrder.line_items[0],
          vendor: 'Someone Else',
          properties: [{ name: 'app_seller_uid', value: 'kali' }],
        },
      ],
    },
    resolve,
  );
  assert.equal(order.lines[0]?.sellerUid, 'kali');
});

test('an unknown vendor is left uncredited rather than guessed', async () => {
  const order = await normalizeOrder(
    {
      ...baseOrder,
      line_items: [{ ...baseOrder.line_items[0], vendor: 'Nobody' }],
    },
    resolve,
  );
  // Uncredited is a reconciliation task; miscredited is a wrong payout.
  assert.equal(order.lines[0]?.sellerUid, '');
});

test('an order with no lines does not throw', async () => {
  const order = await normalizeOrder(
    { ...baseOrder, line_items: [] },
    resolve,
  );
  assert.equal(order.lines.length, 0);
  assert.equal(order.totalCents, 2800);
});

test('a missing name falls back to the order number', async () => {
  const order = await normalizeOrder(
    { ...baseOrder, name: undefined, order_number: 1001 },
    resolve,
  );
  assert.equal(order.number, '#1001');
});

test('a missing created_at does not produce an invalid date', async () => {
  const order = await normalizeOrder(
    { ...baseOrder, created_at: undefined },
    resolve,
  );
  assert.ok(!Number.isNaN(order.placedAt.getTime()));
});

test('an unparseable line price throws rather than booking a free sale', async () => {
  await assert.rejects(
    normalizeOrder(
      {
        ...baseOrder,
        line_items: [{ ...baseOrder.line_items[0], price: 'free' }],
      },
      resolve,
    ),
  );
});

test('contact_email is used when email is absent', async () => {
  const order = await normalizeOrder(
    { ...baseOrder, email: undefined, contact_email: 'dee@example.com' },
    resolve,
  );
  assert.equal(order.buyerEmail, 'dee@example.com');
});
