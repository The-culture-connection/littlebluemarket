import { strict as assert } from 'node:assert';
import { test } from 'node:test';

import {
  settlementFromOrder,
  shipmentFromOrder,
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
  order_id: 7886521106592,
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
