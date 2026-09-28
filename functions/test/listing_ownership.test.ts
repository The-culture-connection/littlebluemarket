import { strict as assert } from 'node:assert';
import { test } from 'node:test';

import {
  MAX_OWNED_LISTINGS,
  SITE_ROLES,
  indexReplacementIsSafe,
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

/**
 * Why it came back (Grace, 2026-09-28: "will this fix stay because it came
 * back").
 *
 * The first fix put the decision in `ownsListings`, which is recomputed
 * from the website on every refresh, and the app asks for a refresh on
 * launch. So a release lasted exactly until the person next opened the app
 * and the recomputation came out differently. Two ways it could:
 *
 *  * the role arrives empty, because the endpoint littlebluecart.com
 *    actually answers is WooCommerce's customers list, whose shape carries
 *    `role` rather than `roles[]` and need not carry either; and
 *  * the listing count is read off an index that a short crawl had just
 *    replaced, so an account that authored 260 reads as having authored 9.
 *
 * Either alone leaves the other guard standing. Together they let the whole
 * directory be handed back. `released` is the answer: it is not derived
 * from the website at all, so no answer from the website can overturn it.
 */
void test('an admin release outlives a website that says nothing is wrong', () => {
  // The exact shape of a recomputation that finds nothing: no role, and a
  // count under the threshold because the index was short.
  const looksInnocent = { roles: [] as string[], listingCount: 9 };
  assert.equal(listingOwnershipRefusal(looksInnocent), null);

  // The same recomputation, once an admin has released the account.
  const reason = listingOwnershipRefusal({ ...looksInnocent, released: true });
  assert.ok(reason, 'a released account must stay released');
  assert.match(reason!, /admin released/);
});

void test('a release beats even a website that looks perfectly ordinary', () => {
  // Nothing suspicious anywhere: a plain customer with two listings.
  const reason = listingOwnershipRefusal({
    roles: ['customer'],
    listingCount: 2,
    released: true,
  });
  assert.match(reason!, /admin released/);
  // And without the release that same account is allowed, which is what
  // makes the flag the thing doing the work rather than a coincidence.
  assert.equal(listingOwnershipRefusal({ roles: ['customer'], listingCount: 2 }), null);
});

void test('releasing is not the default: an ordinary account is still allowed', () => {
  assert.equal(listingOwnershipRefusal({ roles: ['customer'], listingCount: 3, released: false }), null);
  assert.equal(listingOwnershipRefusal({ roles: ['subscriber'], listingCount: MAX_OWNED_LISTINGS }), null);
});

/**
 * The other half: a crawl that comes back short must not replace the index.
 *
 * The index is what the listing-count guard reads, so a short crawl does
 * not merely lose rows, it disarms the guard. `crawlIndex` stopped when it
 * had seen `result.totalPages ?? page` pages, so a response without the
 * page-count header — one caching layer in front of WordPress — ended the
 * crawl after a single page of a hundred and wrote that over an index of
 * nearly two thousand.
 */
void test('a short crawl does not replace a healthy index', () => {
  // 1,783 published listings on the site today; one page of the crawl.
  assert.equal(indexReplacementIsSafe(1783, 100), false);
  assert.equal(indexReplacementIsSafe(1783, 0), false);
  // A site that genuinely shrank a little is still believed.
  assert.equal(indexReplacementIsSafe(1783, 1700), true);
  assert.equal(indexReplacementIsSafe(1783, 900), true);
});

void test('the first crawl of an empty project is allowed to be any size', () => {
  // Nothing to protect yet, and refusing here would mean the index could
  // never be built at all.
  assert.equal(indexReplacementIsSafe(0, 0), true);
  assert.equal(indexReplacementIsSafe(0, 1783), true);
  assert.equal(indexReplacementIsSafe(10, 1), true);
});
