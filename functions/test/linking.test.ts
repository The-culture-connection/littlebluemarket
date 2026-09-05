import { strict as assert } from 'node:assert';
import { test } from 'node:test';

import {
  gidTail,
  purchaseDocId,
  purchaseDocsFor,
  type BackfilledOrder,
} from '../src/linking.ts';

/**
 * The order backfill, tested where its bugs would be quiet: a purchase id
 * that differs from the webhook's (two cells for one order), a seller thrown
 * away (a purchase that links to nobody).
 */

const resolve = async (hints: { vendor?: string; productId?: string }) =>
  ({ Gwynstone: 'kali', 'Rae Ortiz': 'rae' })[hints.vendor ?? ''] ?? '';

const order: BackfilledOrder = {
  id: 'gid://shopify/Order/4471',
  name: '#4471',
  processedAt: '2026-06-15T12:00:00Z',
  lineItems: {
    nodes: [
      {
        id: 'gid://shopify/LineItem/901',
        title: 'Cocoa Mint Lip Balm',
        quantity: 2,
        product: { id: 'gid://shopify/Product/p1' },
        vendor: 'Gwynstone',
        image: { url: 'https://cdn/x.jpg' },
      },
      {
        id: 'gid://shopify/LineItem/902',
        title: 'A print',
        quantity: 1,
        product: null,
        vendor: 'Nobody Known',
        image: null,
      },
    ],
  },
};

test('purchase ids match the webhook path: orderId_lineId', () => {
  // orders.ts writes `${order.id}_${line.id}` with the numeric ids. A backfill
  // that used the line's *index* produced a second document for the same
  // purchase once the webhook also saw the order.
  assert.equal(purchaseDocId('4471', '901'), '4471_901');
  assert.equal(gidTail('gid://shopify/LineItem/901'), '901');
  assert.equal(gidTail('901'), '901');
});

test('the vendor string is passed through to the seller lookup', async () => {
  const docs = await purchaseDocsFor([order], resolve);
  assert.equal(docs.length, 2);
  assert.equal(docs[0]!.id, '4471_901');
  assert.equal(docs[0]!.data.sellerId, 'kali');
  assert.equal(docs[0]!.data.productId, 'p1');
  assert.equal(docs[0]!.data.imageUrl, 'https://cdn/x.jpg');
  assert.equal(docs[0]!.data.delivered, true);
  assert.equal(docs[0]!.data.backfilled, true);
});

test('an unknown vendor leaves the seller empty rather than guessing', async () => {
  const docs = await purchaseDocsFor([order], resolve);
  assert.equal(docs[1]!.data.sellerId, '');
  assert.equal(docs[1]!.data.productId, '');
  assert.equal(docs[1]!.data.imageUrl, null);
});

test('quantities are carried so the purchase count can be summed', async () => {
  const docs = await purchaseDocsFor([order], resolve);
  const items = docs.reduce((n, d) => n + Number(d.data.quantity), 0);
  assert.equal(items, 3);
});
