import { strict as assert } from 'node:assert';
import { test } from 'node:test';

import { deletionScope, plausibleEmail } from '../src/account_deletion.ts';

/**
 * The page behind these works for someone who is not signed in, so what it
 * sends is the only thing standing between the list and junk.
 */
test('the scope is one of two answers, whatever arrives', () => {
  assert.equal(deletionScope('data'), 'data');
  assert.equal(deletionScope('account'), 'account');
  assert.equal(deletionScope('everything'), 'account', 'an unknown word means the whole account');
  assert.equal(deletionScope(undefined), 'account');
  assert.equal(deletionScope(42), 'account');
});

test('an address is lowercased and loosely checked', () => {
  assert.equal(plausibleEmail('  Maya@Example.COM '), 'maya@example.com');
  assert.equal(plausibleEmail('maya at example dot com'), '', 'no @ or spaces');
  assert.equal(plausibleEmail('maya@example'), '', 'no dot');
  assert.equal(plausibleEmail(''), '');
  assert.equal(plausibleEmail(undefined), '');
  assert.equal(plausibleEmail('a'.repeat(400) + '@example.com'), '', 'absurdly long');
});
