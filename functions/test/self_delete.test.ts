import { strict as assert } from 'node:assert';
import { test } from 'node:test';

import {
  DELETE_CONFIRMATION,
  REAUTH_WINDOW_MS,
  deletionScope,
  signedInRecently,
} from '../src/account_deletion.ts';

/**
 * Deleting your own account is irreversible and happens without anybody
 * checking, so the guards are the feature. These cover the two that are
 * pure; the other two (it is your own account, and an admin is refused) are
 * structural: the uid comes from the verified token and is never passed in,
 * and the admin refusal is the first thing the function does.
 */

const minutes = (n: number) => n * 60_000;
const NOW = Date.UTC(2026, 8, 14, 20, 0, 0);
/** A token as Firebase mints it: auth_time in seconds, not milliseconds. */
const at = (ms: number) => ({ auth_time: Math.floor(ms / 1000) });

test('a sign-in from moments ago is recent enough', () => {
  assert.equal(signedInRecently(at(NOW), NOW), true);
  assert.equal(signedInRecently(at(NOW - minutes(1)), NOW), true);
  assert.equal(signedInRecently(at(NOW - minutes(9)), NOW), true);
});

test('an old sign-in is not, however fresh the token itself is', () => {
  // The point of auth_time: a token refreshed every hour must not keep an
  // irreversible door open for ever.
  assert.equal(signedInRecently(at(NOW - minutes(11)), NOW), false);
  assert.equal(signedInRecently(at(NOW - minutes(60)), NOW), false);
  assert.equal(signedInRecently(at(NOW - minutes(60 * 24 * 30)), NOW), false);
  // Exactly on the boundary is refused rather than allowed.
  assert.equal(signedInRecently(at(NOW - REAUTH_WINDOW_MS), NOW), false);
});

test('a missing or nonsense auth_time is refused, never assumed recent', () => {
  assert.equal(signedInRecently(undefined, NOW), false);
  assert.equal(signedInRecently({}, NOW), false);
  assert.equal(signedInRecently({ auth_time: 0 }, NOW), false);
  assert.equal(signedInRecently({ auth_time: -1 }, NOW), false);
  assert.equal(signedInRecently({ auth_time: 'soon' }, NOW), false);
  assert.equal(signedInRecently({ auth_time: null }, NOW), false);
  // Seconds mistaken for milliseconds would read as the year 1970.
  assert.equal(signedInRecently({ auth_time: NOW }, NOW), false);
});

test('a phone whose clock runs slightly fast is still allowed', () => {
  // Four minutes into the future: a clock skew, not an attack.
  assert.equal(signedInRecently(at(NOW + minutes(4)), NOW), true);
  // An hour into the future is not a clock, it is a forged claim.
  assert.equal(signedInRecently(at(NOW + minutes(60)), NOW), false);
});

test('the window is ten minutes, and saying so is part of the contract', () => {
  assert.equal(REAUTH_WINDOW_MS, minutes(10));
});

test('the confirmation is one exact word', () => {
  assert.equal(DELETE_CONFIRMATION, 'DELETE');
  // The function compares strictly, so these are all refusals. Spelled out
  // here so a future kindness like trim() or toUpperCase() is a deliberate
  // decision rather than a quiet loosening.
  for (const typed of ['delete', 'Delete', ' DELETE', 'DELETE ', '', 'DELETE MY ACCOUNT']) {
    assert.notEqual(typed, DELETE_CONFIRMATION);
  }
});

test('the scope is the whole account unless the word is exactly data', () => {
  assert.equal(deletionScope('data'), 'data');
  assert.equal(deletionScope('account'), 'account');
  // Anything unexpected means the whole account, which is the safer reading
  // of an ambiguous request: it removes more, never less.
  assert.equal(deletionScope(undefined), 'account');
  assert.equal(deletionScope('DATA'), 'account');
  assert.equal(deletionScope(''), 'account');
});
