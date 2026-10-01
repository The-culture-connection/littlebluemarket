import { strict as assert } from 'node:assert';
import { test } from 'node:test';

import {
  MAX_OWNED_LISTINGS,
  SITE_ROLES,
  indexReplacementIsSafe,
  listingOwnershipRefusal,
  profileAfterRelease,
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

/**
 * What releasing does to the released account's own profile.
 *
 * Grace, 2026-09-28, minutes after the release ran: "now she has no
 * username or name". It blanked the profile whether or not the profile had
 * anything to do with a listing. Snapshots only started being kept on
 * 2026-09-23, so the account this was all written for had none, and had
 * long since been renamed back to her own name by hand. All of it went.
 */
void test('a snapshot is put back exactly', () => {
  const { profile, outcome } = profileAfterRelease({
    current: { name: 'Liberal Lawn', handle: '@liberallawn' },
    before: { name: 'Erin', handle: '@erin', handleLower: 'erin', bio: 'Hi', tags: ['#Local'], cityState: 'Springfield, VA' },
    borrowedTitles: ['Liberal Lawn'],
  });
  assert.equal(outcome, 'restored');
  assert.equal(profile!.name, 'Erin');
  assert.equal(profile!.handle, '@erin');
  assert.equal(profile!.cityState, 'Springfield, VA');
});

void test('no snapshot, and the profile is wearing a released listing: cleared', () => {
  const { profile, outcome } = profileAfterRelease({
    current: { name: 'Liberal Lawn', handle: '@liberallawn', cityState: 'Detroit, MI' },
    borrowedTitles: ['Wild Sage Tea Co', 'Liberal Lawn', 'Organized Q'],
  });
  assert.equal(outcome, 'cleared');
  assert.equal(profile!.name, '');
  assert.equal(profile!.handle, '');
  // Capitalisation and stray spacing are not what decides this.
  assert.equal(
    profileAfterRelease({ current: { name: '  liberal lawn ' }, borrowedTitles: ['Liberal Lawn'] }).outcome,
    'cleared',
  );
});

void test('no snapshot, and the name is the person\'s own: left alone', () => {
  // The case that cost somebody their name. She had put "Erin" back
  // herself; no listing released here is called that.
  const { profile, outcome } = profileAfterRelease({
    current: { name: 'Erin', handle: 'Erin (she/her)', cityState: 'Springfield, VA' },
    borrowedTitles: ['Wild Sage Tea Co', 'Liberal Lawn', 'Organized Q'],
  });
  assert.equal(outcome, 'kept');
  assert.equal(profile, null, 'nothing is written, so nothing can be lost');
});

void test('an empty name is not a match for anything', () => {
  // Otherwise a listing with a blank title would clear every profile it
  // touched, and releasing twice would wipe what the first release kept.
  assert.equal(profileAfterRelease({ current: { name: '' }, borrowedTitles: [''] }).outcome, 'kept');
  assert.equal(profileAfterRelease({ current: {}, borrowedTitles: ['Liberal Lawn'] }).outcome, 'kept');
});

/**
 * The third time (Grace, 2026-09-29: "the erin bug happened again!!").
 *
 * The production log for `directoryLinkMe` carries no refusal at all for
 * that run — and 259 businesses were attributed to one account anyway. That
 * is not the guard failing to decide; it is the guard being asked the wrong
 * question at the wrong moment.
 *
 * `syncDirectory` reads the owner index, counts this account's listings and
 * asks `listingOwnershipRefusal`. Then, if allowed, it calls `syncListings`,
 * which reads the index *again* with `force`, so it may rebuild from the
 * website. A first read that came back short made the count small, nothing
 * was refused, and the second read then returned everything.
 *
 * The rule, in one line: the count that authorises must be the count that is
 * acted on. `syncListings` now asks about the ids it is about to mirror, and
 * that check cannot be separated from the write by anything.
 */
void test('the count that authorises is the count that is acted on', () => {
  // What the first read saw, on the run that went wrong.
  const atCheckTime = 9;
  // What the second read returned, and what was written.
  const atWriteTime = 259;

  assert.equal(listingOwnershipRefusal({ roles: [], listingCount: atCheckTime }), null);
  const refusal = listingOwnershipRefusal({ roles: [], listingCount: atWriteTime });
  assert.ok(refusal, 'the number actually being written must be refused');
  assert.match(refusal!, /259 listings/);
});

void test('the boundary is the same wherever it is asked', () => {
  // One business with a lot of listings is still a business; the site's own
  // account is not. Both checks read the same constant, so moving it moves
  // every copy at once.
  assert.equal(listingOwnershipRefusal({ roles: [], listingCount: MAX_OWNED_LISTINGS }), null);
  assert.ok(listingOwnershipRefusal({ roles: [], listingCount: MAX_OWNED_LISTINGS + 1 }));
});

// ---- 2026-09-30: the directory kept coming back to the site account daily.

void test('the site account is refused by id, even when the index makes it look small', async () => {
  const { listingOwnershipRefusal: refuse } = await import('../src/directory.ts');
  // A short owner index: three listings, and no role known. Before, this
  // passed both the role and the count check.
  assert.ok(refuse({ roles: [], listingCount: 3, wpUserId: 6 }));
  assert.equal(refuse({ roles: [], listingCount: 3, wpUserId: 42 }), null);
});

void test('one predicate decides for every path that hands out listings', async () => {
  const { mayOwnListings } = await import('../src/directory.ts');
  assert.equal(mayOwnListings({ ownershipLocked: true, wpUserId: 42 }), false);
  assert.equal(mayOwnListings({ ownsListings: false, wpUserId: 42 }), false);
  assert.equal(mayOwnListings({ wpUserId: 6 }), false);
  assert.equal(mayOwnListings({ wpUserId: 42 }), true);
});

void test('the block list matches by account, email or website user, and reads junk as empty', async () => {
  const { blocklistFrom, isBlocked, mayOwnListings } = await import('../src/directory.ts');
  const list = blocklistFrom({ uids: ['erin'], emails: [' Erin@Example.com '], wpUserIds: [6, 'x'] });
  assert.ok(isBlocked(list, { uid: 'erin' }));
  assert.ok(isBlocked(list, { emailLower: 'erin@example.com' }));
  assert.ok(isBlocked(list, { wpUserId: 6 }));
  assert.equal(isBlocked(list, { uid: 'biz', emailLower: 'biz@example.com', wpUserId: 42 }), false);
  // A link whose website email is on the list is barred even with a clean
  // website account number.
  assert.equal(mayOwnListings({ wpUserId: 42, wpEmailLower: 'erin@example.com' }, list, 'new'), false);
  assert.equal(blocklistFrom(undefined).uids.size, 0);
});
