import { strict as assert } from 'node:assert';
import { test } from 'node:test';

import {
  decodeJwsPayload,
  membershipFromApple,
  membershipFromPlay,
  normalisePem,
} from '../src/membership.ts';

/**
 * Reading what the two stores say.
 *
 * The expensive failure here is generous rather than stingy: a lapsed
 * subscription read as active is a membership nobody is paying for, and it
 * would never be noticed because nothing breaks. So every test below asks
 * "does this stay a member when it should not".
 */

const now = new Date('2026-09-29T12:00:00Z');
const future = '2026-10-29T12:00:00Z';
const past = '2026-09-01T12:00:00Z';

// --------------------------------------------------------------- Play

void test('an active Play subscription is a member until its expiry', () => {
  const e = membershipFromPlay(
    {
      subscriptionState: 'SUBSCRIPTION_STATE_ACTIVE',
      latestOrderId: 'GPA.1',
      lineItems: [{ expiryTime: future }],
    },
    now,
  );

  assert.equal(e.active, true);
  assert.equal(e.store, 'google');
  assert.equal(e.periodId, 'GPA.1');
  assert.equal(e.expiresAt.toISOString(), new Date(future).toISOString());
});

void test('a cancelled Play subscription keeps what it paid for, then stops', () => {
  // Cancelled means "will not renew", not "refund the rest of the month".
  const during = membershipFromPlay(
    {
      subscriptionState: 'SUBSCRIPTION_STATE_CANCELED',
      lineItems: [{ expiryTime: future }],
    },
    now,
  );
  assert.equal(during.active, true);

  const after = membershipFromPlay(
    {
      subscriptionState: 'SUBSCRIPTION_STATE_CANCELED',
      lineItems: [{ expiryTime: past }],
    },
    now,
  );
  assert.equal(after.active, false);
});

void test('a Play subscription on hold or expired is not a member', () => {
  for (const state of [
    'SUBSCRIPTION_STATE_ON_HOLD',
    'SUBSCRIPTION_STATE_EXPIRED',
    'SUBSCRIPTION_STATE_PAUSED',
    'SUBSCRIPTION_STATE_PENDING',
  ]) {
    const e = membershipFromPlay(
      { subscriptionState: state, lineItems: [{ expiryTime: future }] },
      now,
    );
    assert.equal(e.active, false, `${state} should not be a member`);
  }
});

void test('a card that failed keeps the member while Google retries', () => {
  const e = membershipFromPlay(
    {
      subscriptionState: 'SUBSCRIPTION_STATE_IN_GRACE_PERIOD',
      lineItems: [{ expiryTime: future }],
    },
    now,
  );
  assert.equal(e.active, true);
});

void test('the latest expiry wins when there is more than one line', () => {
  // An upgrade mid-month leaves two lines; taking the first would cut the
  // membership short on the day they paid more.
  const e = membershipFromPlay(
    {
      subscriptionState: 'SUBSCRIPTION_STATE_ACTIVE',
      lineItems: [{ expiryTime: past }, { expiryTime: future }],
    },
    now,
  );
  assert.equal(e.expiresAt.toISOString(), new Date(future).toISOString());
});

void test('Play with no expiry is refused rather than guessed at', () => {
  assert.throws(() =>
    membershipFromPlay({ subscriptionState: 'SUBSCRIPTION_STATE_ACTIVE' }, now),
  );
});

// -------------------------------------------------------------- Apple

void test('an unexpired Apple transaction is a member', () => {
  const e = membershipFromApple(
    {
      expiresDate: new Date(future).getTime(),
      transactionId: '200001',
      originalTransactionId: '100001',
    },
    now,
  );

  assert.equal(e.active, true);
  assert.equal(e.store, 'apple');
  assert.equal(e.periodId, '200001');
});

void test('a refunded Apple subscription is not a member, whatever its dates say', () => {
  const e = membershipFromApple(
    {
      expiresDate: new Date(future).getTime(),
      revocationDate: new Date('2026-09-20T00:00:00Z').getTime(),
      transactionId: '200002',
    },
    now,
  );
  assert.equal(e.active, false);
});

void test('an expired Apple subscription is not a member', () => {
  const e = membershipFromApple(
    { expiresDate: new Date(past).getTime(), transactionId: '200003' },
    now,
  );
  assert.equal(e.active, false);
});

void test('Apple with no expiry is refused rather than guessed at', () => {
  assert.throws(() => membershipFromApple({ transactionId: '200004' }, now));
});

// ------------------------------------------------------------ plumbing

void test('a JWS payload is read out of the middle segment', () => {
  const payload = { expiresDate: 1790000000000, transactionId: '9' };
  const jws = [
    Buffer.from(JSON.stringify({ alg: 'ES256' })).toString('base64url'),
    Buffer.from(JSON.stringify(payload)).toString('base64url'),
    'not-checked-here',
  ].join('.');

  assert.deepEqual(decodeJwsPayload(jws), payload);
});

void test('a PEM survives a trip through an environment variable', () => {
  // The failure this prevents is an unreadable OpenSSL error, hours from now.
  const real = '-----BEGIN PRIVATE KEY-----\nabc\n-----END PRIVATE KEY-----\n';
  const escaped = real.replace(/\n/g, '\\n');

  assert.equal(normalisePem(escaped), real);
  assert.equal(normalisePem(real), real);
});
