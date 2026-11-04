import { strict as assert } from 'node:assert';
import { test } from 'node:test';

import { cleanEvents, dayStart, EVENTS_PER_CALL, PROPS_MAX } from '../src/analytics.ts';

// Grace, 2026-11-04: analytics of every screen and action, with the user id,
// downloadable as JSON from the admin website.

const NOW = Date.parse('2026-11-04T12:00:00Z');

test('an event keeps its name, small facts and where it came from', () => {
  const [e] = cleanEvents(
    [
      {
        name: 'add_to_cart',
        props: { productId: 'p1', quantity: 2, proof: true },
        at: '2026-11-04T11:59:00Z',
        sessionId: 's',
        deviceId: 'd',
        platform: 'ios',
        appVersion: '0.4.6+19',
        path: '/market/product/p1',
      },
    ],
    NOW,
  );
  assert.ok(e);
  assert.equal(e.name, 'add_to_cart');
  assert.deepEqual(e.props, { productId: 'p1', quantity: 2, proof: true });
  assert.equal(e.at.toDate().toISOString(), '2026-11-04T11:59:00.000Z');
  assert.equal(e.platform, 'ios');
  assert.equal(e.path, '/market/product/p1');
});

test('the phone cannot say who it is: there is no uid to take from it', () => {
  const [e] = cleanEvents([{ name: 'sign_in', uid: 'somebody-else', props: { uid: 'x' } }], NOW);
  assert.ok(e);
  assert.equal('uid' in e, false);
  // A prop called uid is just a fact; the stored uid is set by the server.
  assert.equal(e.props.uid, 'x');
});

test('bad events are dropped, not the batch', () => {
  const events = cleanEvents(
    [
      { name: 'Bad Name' },
      'not an event',
      null,
      { name: 'screen_view', props: { screen: '/market' } },
    ],
    NOW,
  );
  assert.deepEqual(events.map((e) => e.name), ['screen_view']);
});

test('props are limited to plain small values and a fixed number of keys', () => {
  const many = Object.fromEntries(Array.from({ length: 30 }, (_, i) => [`k${i}`, i]));
  const [e] = cleanEvents(
    [
      { name: 'x', props: { ...many } },
      { name: 'y', props: { nested: { a: 1 }, list: [1], long: 'z'.repeat(500), 'bad key': 1, nan: Number.NaN } },
    ],
    NOW,
  );
  assert.equal(Object.keys(e!.props).length, PROPS_MAX);
  const y = cleanEvents([{ name: 'y', props: { nested: { a: 1 }, list: [1], long: 'z'.repeat(500), 'bad key': 1, nan: Number.NaN } }], NOW)[0]!;
  assert.deepEqual(Object.keys(y.props), ['long']);
  assert.equal((y.props.long as string).length, 200);
});

test('a batch is capped, and a clock far out is replaced by arrival time', () => {
  const lots = Array.from({ length: EVENTS_PER_CALL + 10 }, () => ({ name: 'tap' }));
  assert.equal(cleanEvents(lots, NOW).length, EVENTS_PER_CALL);
  const [e] = cleanEvents([{ name: 'tap', at: '1970-01-01T00:00:00Z' }], NOW);
  assert.equal(e!.at.toMillis(), NOW);
});

test('the export dates are whole days, and a bad one is said out loud', () => {
  assert.equal(dayStart('2026-11-04', 'From').toDate().toISOString(), '2026-11-04T00:00:00.000Z');
  assert.throws(() => dayStart('next tuesday', 'The start date'), /The start date is not a date/);
});
