import { strict as assert } from 'node:assert';
import { test } from 'node:test';

import { authHeaders, extractVendorUsers } from '../src/shipturtle_api.ts';

/**
 * The roster parser, against the shapes an API like Shipturtle's plausibly
 * returns. The real shape is recorded by the probe; these make sure a
 * reasonable variety does not silently produce an empty roster.
 */

test('a flat list of vendors with emails', () => {
  const users = extractVendorUsers({
    data: [
      { id: 1092484, company_id: 1092484, name: 'Grace', email: 'Grace-S@Example.com' },
      { id: 2, company_id: 2, name: 'Gwynstone', email: 'g@example.com' },
    ],
  });
  assert.deepEqual(users, [
    { companyId: '1092484', email: 'grace-s@example.com', name: 'Grace' },
    { companyId: '2', email: 'g@example.com', name: 'Gwynstone' },
  ]);
});

test('vendors with nested user logins', () => {
  const users = extractVendorUsers({
    vendors: [
      {
        vendor_id: 7,
        company_name: 'Femme & Fawn',
        users: [{ email: 'a@x.com', name: 'A' }, { email: 'b@x.com', name: 'B' }],
      },
    ],
  });
  assert.deepEqual(
    users.map((u) => [u.companyId, u.email]),
    [
      ['7', 'a@x.com'],
      ['7', 'b@x.com'],
    ],
  );
});

test('a bare array, and entries without an email are dropped', () => {
  const users = extractVendorUsers([
    { company_id: 1, email: 'one@x.com' },
    { company_id: 2 },
    { email: 'orphan@x.com' },
  ]);
  assert.deepEqual(users.map((u) => u.companyId), ['1']);
});

test('garbage yields an empty roster, never a throw', () => {
  assert.deepEqual(extractVendorUsers(null), []);
  assert.deepEqual(extractVendorUsers('nope'), []);
  assert.deepEqual(extractVendorUsers({ message: 'Unauthenticated.' }), []);
});

test('auth header styles', () => {
  assert.deepEqual(authHeaders('t', 'Authorization'), { Authorization: 'Bearer t' });
  assert.deepEqual(authHeaders('t', 'x-api-key'), { 'x-api-key': 't' });
  assert.deepEqual(authHeaders('t', 'access-token'), { 'access-token': 't' });
});
