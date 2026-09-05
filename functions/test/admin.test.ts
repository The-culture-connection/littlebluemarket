import { strict as assert } from 'node:assert';
import { test } from 'node:test';

import { isAllowedAdmin } from '../src/admin.ts';

test('an email on the list may claim admin, case and whitespace aside', () => {
  const doc = { emails: ['Grace-S@The-Culture-Connection.com ', 'other@x.com'] };
  assert.equal(isAllowedAdmin('grace-s@the-culture-connection.com', doc), true);
  assert.equal(isAllowedAdmin('  GRACE-S@the-culture-connection.com', doc), true);
});

test('anyone else may not', () => {
  const doc = { emails: ['grace-s@the-culture-connection.com'] };
  assert.equal(isAllowedAdmin('grace-s+buyer1@the-culture-connection.com', doc), false);
  assert.equal(isAllowedAdmin('', doc), false);
  assert.equal(isAllowedAdmin(undefined, doc), false);
});

test('a missing or malformed list grants nobody', () => {
  assert.equal(isAllowedAdmin('grace-s@the-culture-connection.com', undefined), false);
  assert.equal(isAllowedAdmin('grace-s@the-culture-connection.com', {}), false);
  assert.equal(isAllowedAdmin('grace-s@the-culture-connection.com', { emails: 'grace-s@the-culture-connection.com' }), false);
  assert.equal(isAllowedAdmin('grace-s@the-culture-connection.com', { emails: [42, null] }), false);
});
