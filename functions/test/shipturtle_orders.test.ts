import { strict as assert } from 'node:assert';
import { test } from 'node:test';

import {
  listShipturtleOrders,
  settlementFromOrder,
  shipmentFromOrder,
  shopifyOrderId,
  vendorFromUniqueName,
  type ShipturtleOrder,
} from '../src/shipturtle_orders.ts';

/**
 * Shipturtle's sub-orders, as recorded on 2026-09-05 (secret-free). What the
 * app takes from them: tracking for the buyer, settlement words for the
 * seller, never a payout figure computed here.
 */

const untracked: ShipturtleOrder = {
  id: 16911442,
  order_id: 1925040802455,
  admin_graphql_api_id: 'gid://shopify/Order/7886521106592',
  name: '#1001',
  company_id: 1092566,
  unique_name: '#1001_Hydrogen Vendor_physical',
  tracking_code: null,
  tracking_status: 'Pending',
  status: 'New Orders',
  payment_reconciliation_status: 'pending',
  credited: 0,
  total_amount_including_taxes: '600',
};

test('the vendor string is read out of unique_name, underscores and all', () => {
  assert.equal(vendorFromUniqueName('#1001_Hydrogen Vendor_physical'), 'Hydrogen Vendor');
  assert.equal(vendorFromUniqueName('#1002_little_blue_market_devtestingshop_physical'), 'little_blue_market_devtestingshop');
  assert.equal(vendorFromUniqueName(undefined), '');
  assert.equal(vendorFromUniqueName('odd'), '');
});

test('no tracking code means no shipment, but the settlement is still recorded', () => {
  assert.equal(shipmentFromOrder(untracked), null);
  assert.deepEqual(settlementFromOrder(untracked), {
    orderId: '7886521106592',
    companyId: '1092566',
    vendorName: 'Hydrogen Vendor',
    status: 'New Orders',
    payoutStatus: 'pending',
    credited: false,
    amount: '600',
  });
});

test('a tracked sub-order becomes a shipment with the courier state flattened', () => {
  const shipped = { ...untracked, tracking_code: 'ST123', tracking_link: 'https://t/ST123', tracking_status: 'In Transit', shipping_provider: 'USPS', credited: '1', payment_reconciliation_status: 'reconciled' };
  assert.deepEqual(shipmentFromOrder(shipped), {
    orderId: '7886521106592',
    companyId: '1092566',
    vendorName: 'Hydrogen Vendor',
    trackingNumber: 'ST123',
    trackingUrl: 'https://t/ST123',
    carrier: 'USPS',
    state: 'inTransit',
    shipturtleStatus: 'New Orders',
    payoutStatus: 'reconciled',
    credited: true,
  });
  assert.equal(shipmentFromOrder({ ...shipped, tracking_status: 'Delivered' })!.state, 'delivered');
});

test('the order id is the Shopify one, not Shipturtle\'s own number', () => {
  assert.equal(shopifyOrderId(untracked), '7886521106592');
  assert.equal(shopifyOrderId({ ...untracked, admin_graphql_api_id: null }), '1925040802455');
});

/**
 * 2026-11-21: every production run hung on a Shipturtle page that never
 * answered, until the platform killed the run. A page that does not answer
 * now ends the listing with what already arrived.
 */
test('a Shipturtle page that never answers ends the listing instead of hanging', async () => {
  process.env.SHIPTURTLE_API_KEY = 'test-key';
  process.env.SHIPTURTLE_BASE_URL = 'https://shipturtle.invalid';
  const fullPage = Array.from({ length: 100 }, (_, i) => ({ ...untracked, id: i }));
  let calls = 0;
  const fakeFetch = (async (_url: string, init?: RequestInit) => {
    calls += 1;
    if (calls === 1) return new Response(JSON.stringify({ data: fullPage }), { status: 200 });
    // Second page: never answers, except to the abort signal.
    return new Promise<Response>((_resolve, reject) => {
      init?.signal?.addEventListener('abort', () => reject(new DOMException('timed out', 'TimeoutError')));
    });
  }) as typeof fetch;
  const started = Date.now();
  const rows = await listShipturtleOrders(500, fakeFetch, Date.now() + 5_000, 200);
  assert.equal(rows.length, 100);
  assert.equal(calls, 2);
  assert.ok(Date.now() - started < 2_000, 'gave up on the slow page promptly');
});
