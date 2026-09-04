import { strict as assert } from 'node:assert';
import * as crypto from 'node:crypto';
import { test } from 'node:test';

import { mapShipmentState, verifyShipTurtleSignature } from '../src/shipturtle.ts';

const SECRET = 'shipturtle-test-secret';

function sign(body: string, secret = SECRET): string {
  return crypto.createHmac('sha256', secret).update(body, 'utf8').digest('hex');
}

test('accepts a correctly signed webhook', () => {
  const body = JSON.stringify({ order_id: '4471' });
  assert.equal(verifyShipTurtleSignature(body, sign(body), SECRET), true);
});

test('rejects a wrong signature, a missing one, or a missing secret', () => {
  const body = JSON.stringify({ order_id: '4471' });
  assert.equal(verifyShipTurtleSignature(body, sign(body, 'wrong'), SECRET), false);
  assert.equal(verifyShipTurtleSignature(body, undefined, SECRET), false);
  // An unconfigured secret must fail closed, not open.
  assert.equal(verifyShipTurtleSignature(body, sign(body), undefined), false);
});

test('rejects a tampered body', () => {
  const original = JSON.stringify({ order_id: '4471', status: 'in_transit' });
  const signature = sign(original);
  const tampered = JSON.stringify({ order_id: '9999', status: 'delivered' });
  assert.equal(verifyShipTurtleSignature(tampered, signature, SECRET), false);
});

test('maps their delivery states onto ours', () => {
  assert.equal(mapShipmentState('Delivered'), 'delivered');
  assert.equal(mapShipmentState('out for delivery'), 'outForDelivery');
  assert.equal(mapShipmentState('In Transit'), 'inTransit');
  assert.equal(mapShipmentState('shipped'), 'inTransit');
  // Anything unrecognised is the earliest state, not the latest: claiming a
  // parcel is delivered when it is not is the worse mistake.
  assert.equal(mapShipmentState('label_printed'), 'labelCreated');
  assert.equal(mapShipmentState(undefined), 'labelCreated');
});

test('out for delivery is not read as delivered', () => {
  // Both strings contain "deliver"; the order of the checks is what keeps them
  // apart.
  assert.notEqual(mapShipmentState('out for delivery'), 'delivered');
});
