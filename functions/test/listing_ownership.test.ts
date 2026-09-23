import { strict as assert } from 'node:assert';
import { test } from 'node:test';

import {
  MAX_OWNED_LISTINGS,
  SITE_ROLES,
  listingOwnershipRefusal,
} from '../src/directory.ts';

/**
 * Authorship is not ownership.
 *
 * 2026-09-24, production: a member linked by her verified email, correctly,
 * to WordPress user 6 — login `lbcerin`, role `administrator`, and the
 * author of all 263 listings on littlebluecart.com, because staff enter
 * them on the businesses' behalf. The app concluded she owned the whole
 * directory: 263 listings mirrored under her uid, 263 feed posts written as
 * her, and her profile renamed after the first listing it found. Every step
 * did what it was told; nothing asked whether it made sense.
 */
void test('the account that runs the site is refused, whatever it authored', () => {
  for (const role of SITE_ROLES) {
    const reason = listingOwnershipRefusal({ roles: [role], listingCount: 1 });
    assert.ok(reason, `${role} should be refused`);
    assert.match(reason!, new RegExp(role));
  }
});

void test('the exact shape of the account that caused it', () => {
  const reason = listingOwnershipRefusal({
    roles: ['administrator'],
    listingCount: 263,
  });
  assert.ok(reason);
});

void test('a role is judged however it is capitalised or padded', () => {
  assert.ok(listingOwnershipRefusal({ roles: ['  Administrator '], listingCount: 1 }));
  assert.ok(listingOwnershipRefusal({ roles: ['customer', 'EDITOR'], listingCount: 1 }));
});

void test('an ordinary member with a listing or two is fine', () => {
  assert.equal(listingOwnershipRefusal({ roles: ['customer'], listingCount: 1 }), null);
  assert.equal(listingOwnershipRefusal({ roles: [], listingCount: 3 }), null);
  assert.equal(
    listingOwnershipRefusal({ roles: ['subscriber'], listingCount: MAX_OWNED_LISTINGS }),
    null,
  );
});

void test('volume alone is refused, for a staff account with no telling role', () => {
  // The second guard: an account nobody flagged, that still authored more
  // than any one business plausibly has.
  const reason = listingOwnershipRefusal({
    roles: ['subscriber'],
    listingCount: MAX_OWNED_LISTINGS + 1,
  });
  assert.ok(reason);
  assert.match(reason!, /authored 26 listings/);
});

void test('the reason is something a person could act on', () => {
  // It reaches an admin in the logs and, reworded, the member. "false" would
  // not have told Grace what happened.
  const reason = listingOwnershipRefusal({ roles: ['administrator'], listingCount: 263 });
  assert.ok(reason!.length > 20);
  assert.ok(!/^(true|false)$/.test(reason!));
});
