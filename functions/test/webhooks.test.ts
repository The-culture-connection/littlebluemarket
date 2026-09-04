import { strict as assert } from 'node:assert';
import * as crypto from 'node:crypto';
import { test } from 'node:test';

import { verifyShopifyHmac, webhookHmacHeader, webhookTopic } from '../src/webhooks.ts';
import { attribute, toCents } from '../src/orders.ts';

/**
 * The webhook endpoint is a public URL that moves money data. If signature
 * verification is wrong, anyone who guesses the URL can credit themselves
 * revenue by POSTing JSON — so these are the tests that matter most in the
 * whole functions package.
 */

const SECRET = 'shpss_test_secret';

function sign(body: string, secret = SECRET): string {
  return crypto.createHmac('sha256', secret).update(body, 'utf8').digest('base64');
}

test('accepts a body signed with the configured secret', () => {
  const body = JSON.stringify({ id: 1, total_price: '12.00' });
  assert.equal(verifyShopifyHmac(body, sign(body), [SECRET]), true);
});

test('rejects a body signed with the wrong secret', () => {
  const body = JSON.stringify({ id: 1 });
  assert.equal(
    verifyShopifyHmac(body, sign(body, 'not-the-secret'), [SECRET]),
    false,
  );
});

test('rejects a tampered body', () => {
  const original = JSON.stringify({ id: 1, total_price: '12.00' });
  const signature = sign(original);
  // The attack this exists to stop: same signature, larger order.
  const tampered = JSON.stringify({ id: 1, total_price: '9999.00' });
  assert.equal(verifyShopifyHmac(tampered, signature, [SECRET]), false);
});

test('rejects a missing signature outright', () => {
  const body = JSON.stringify({ id: 1 });
  assert.equal(verifyShopifyHmac(body, undefined, [SECRET]), false);
  assert.equal(verifyShopifyHmac(body, '', [SECRET]), false);
});

test('accepts either configured secret', () => {
  // A store can have webhooks registered by the app (signed with the client
  // secret) and others created in the admin UI (signed with their own).
  const body = JSON.stringify({ id: 2 });
  const secrets = ['client-secret', 'admin-ui-secret'];
  assert.equal(verifyShopifyHmac(body, sign(body, 'client-secret'), secrets), true);
  assert.equal(verifyShopifyHmac(body, sign(body, 'admin-ui-secret'), secrets), true);
  assert.equal(verifyShopifyHmac(body, sign(body, 'neither'), secrets), false);
});

test('undefined secrets are skipped, not treated as empty', () => {
  const body = JSON.stringify({ id: 3 });
  assert.equal(verifyShopifyHmac(body, sign(body), [undefined, SECRET]), true);
  assert.equal(verifyShopifyHmac(body, sign(body), [undefined]), false);
});

test('verifies raw bytes, not a re-serialised body', () => {
  // JSON.parse then stringify does not round-trip byte for byte, and the HMAC
  // is over the exact bytes sent. This is the subtle way it breaks.
  const raw = '{"id":1,  "name":"#1001"}';
  const signature = sign(raw);
  assert.equal(verifyShopifyHmac(raw, signature, [SECRET]), true);
  assert.equal(
    verifyShopifyHmac(JSON.stringify(JSON.parse(raw)), signature, [SECRET]),
    false,
  );
});

test('handles a Buffer body as well as a string', () => {
  const body = JSON.stringify({ id: 4 });
  assert.equal(
    verifyShopifyHmac(Buffer.from(body, 'utf8'), sign(body), [SECRET]),
    true,
  );
});

test('reads the topic and signature from headers', () => {
  assert.equal(webhookTopic({ 'x-shopify-topic': 'orders/paid' }), 'orders/paid');
  assert.equal(webhookTopic({}), '');
  assert.equal(
    webhookHmacHeader({ 'x-shopify-hmac-sha256': 'abc' }),
    'abc',
  );
});

// ------------------------------------------------------------------- money

test('money parses to integer cents', () => {
  assert.equal(toCents('12.00'), 1200);
  assert.equal(toCents('8'), 800);
  assert.equal(toCents('13.60'), 1360);
  assert.equal(toCents(4.2), 420);
});

test('a price that will not parse throws rather than reading as free', () => {
  // Silently recording an unparseable price as $0 is how a seller ends up
  // unpaid with nothing in the logs.
  assert.throws(() => toCents('free'));
  assert.throws(() => toCents(undefined));
  assert.throws(() => toCents(null));
});

test('rounding does not lose a cent', () => {
  assert.equal(toCents('0.1'), 10);
  assert.equal(toCents(0.07), 7);
  assert.equal(toCents('19.99'), 1999);
});

test('cart attributes are read by either key shape', () => {
  assert.equal(
    attribute([{ name: 'app_uid', value: 'maya' }], 'app_uid'),
    'maya',
  );
  assert.equal(
    attribute([{ key: 'app_uid', value: 'maya' }], 'app_uid'),
    'maya',
  );
  assert.equal(attribute([], 'app_uid'), undefined);
  assert.equal(attribute(undefined, 'app_uid'), undefined);
});
