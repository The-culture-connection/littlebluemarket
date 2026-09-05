import { strict as assert } from 'node:assert';
import * as crypto from 'node:crypto';
import { test } from 'node:test';

import {
  authenticateShipTurtleWebhook,
  mapShipmentState,
  verifyShipTurtleSignature,
} from '../src/shipturtle.ts';

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

// --- authenticateShipTurtleWebhook -----------------------------------------
//
// ShipTurtle's webhook registration offers no signing secret, so we cannot
// assume one exists. These four cases pin the resulting policy: verify when we
// can, accept when we cannot, and shout in the one case that proves we should
// have been able to.

test('a configured secret still verifies, and still rejects a forgery', () => {
  const body = JSON.stringify({ order_id: '4471' });

  const good = authenticateShipTurtleWebhook(
    body,
    { 'x-shipturtle-signature': sign(body) },
    SECRET,
  );
  assert.equal(good.ok, true);
  assert.equal(good.ok && good.verified, true);
  assert.equal(good.ok && good.alarm, undefined);

  const forged = authenticateShipTurtleWebhook(
    body,
    { 'x-shipturtle-signature': sign(body, 'wrong') },
    SECRET,
  );
  assert.equal(forged.ok, false);
});

test('no secret and no signature: accepted, flagged unverified, no alarm', () => {
  const body = JSON.stringify({ order_id: '4471' });
  const auth = authenticateShipTurtleWebhook(body, {}, undefined);

  // Failing closed here would mean vendor-side shipments never arrive at all.
  assert.equal(auth.ok, true);
  assert.equal(auth.ok && auth.verified, false);
  assert.equal(auth.ok && auth.alarm, undefined);
});

test('no secret but a signature header: accepted, and it sounds the alarm', () => {
  // The case that matters. A signature we cannot check is proof a secret
  // exists somewhere in their settings, and the only way we will ever find out.
  const body = JSON.stringify({ order_id: '4471' });
  const auth = authenticateShipTurtleWebhook(
    body,
    { 'x-shipturtle-signature': sign(body) },
    undefined,
  );

  assert.equal(auth.ok, true);
  assert.equal(auth.ok && auth.verified, false);
  assert.ok(auth.ok && auth.alarm, 'expected an alarm');
  // The message has to carry the fix, not just the complaint.
  assert.match(String(auth.ok && auth.alarm), /SHIPTURTLE_WEBHOOK_SECRET/);
  assert.match(String(auth.ok && auth.alarm), /functions:secrets:set/);
});

test('finds a signature header whose name we did not guess', () => {
  // `x-shipturtle-signature` is a guess. If they name it anything else, the
  // alarm must still fire — otherwise an unverified endpoint looks healthy.
  const body = JSON.stringify({ order_id: '4471' });
  const auth = authenticateShipTurtleWebhook(
    body,
    { 'x-webhook-hmac-sha256': 'deadbeef', 'x-request-id': 'not-a-signature' },
    undefined,
  );

  assert.ok(auth.ok && auth.alarm, 'expected an alarm for an unguessed header');
  assert.deepEqual(auth.ok && auth.sawHeaders, ['x-webhook-hmac-sha256']);
});
