import { strict as assert } from 'node:assert';
import { test } from 'node:test';

import {
  conversationIdFor,
  isShopUid,
  shopHandleFor,
  shopNameFor,
  shopUidFor,
} from '../src/shops.ts';

/**
 * Every shop on the market has a profile, whether or not anybody has signed
 * up for it (Grace, 2026-09-24). These are the pure parts: what a shell is
 * called and where it lives.
 */

test('a shell uid is derived from the vendor string, not invented', () => {
  assert.equal(shopUidFor('Found House Ceramics'), 'shop_found-house-ceramics');
  // Same shop, typed differently on two products: one shell, not two.
  assert.equal(shopUidFor('found house ceramics'), shopUidFor('Found House Ceramics'));
  assert.equal(shopUidFor('  Found  House   Ceramics '), 'shop_found-house-ceramics');
});

test('a vendor string with nothing usable in it gets no shell', () => {
  assert.equal(shopUidFor(''), '');
  assert.equal(shopUidFor('   '), '');
  assert.equal(shopUidFor('!!!'), '');
});

test('a shell is recognisable as one', () => {
  assert.equal(isShopUid(shopUidFor('Found House')), true);
  // A real Firebase uid never starts with our prefix.
  assert.equal(isShopUid('kOx3mA1bC2dE3fG4h'), false);
});

test('the handle is the vendor key, so it cannot collide with a typed one', () => {
  assert.equal(shopHandleFor('Found House Ceramics'), '@found-house-ceramics');
  assert.equal(shopHandleFor(''), '');
});

test('the shop shows its brand name when Shipturtle knows one', () => {
  assert.equal(shopNameFor('found-house-ceramics', 'Found House'), 'Found House');
  // And the vendor string when it does not.
  assert.equal(shopNameFor('Found House Ceramics', null), 'Found House Ceramics');
  assert.equal(shopNameFor('Found House Ceramics', '   '), 'Found House Ceramics');
});

test('a shell is told apart from a real account, which is what gates the feed', () => {
  // `mirrorProduct` posts a listing to the feed for a product with a seller.
  // Giving every vendor a shell made every product have one, which would
  // have posted sixteen thousand listings the next time each was touched.
  // This is the check that stops it, so it is the check worth pinning.
  assert.equal(isShopUid(shopUidFor('Polly Politics')), true);
  assert.equal(isShopUid('d1GMG6NPhUQplgS8p1nWT1ZedQ92'), false);
  assert.equal(isShopUid(''), false);
});

test('a moved thread lands on the id the app will look under', () => {
  // Mirrors Conversation.idFor in lib/models/message.dart: the sorted pair
  // joined with one underscore. If these disagree, a claimed shop's history
  // is stranded and the buyer starts an empty second thread beside it.
  assert.equal(conversationIdFor('bbb', 'aaa'), 'aaa_bbb');
  assert.equal(conversationIdFor('aaa', 'bbb'), conversationIdFor('bbb', 'aaa'));
  // A shell uid has an underscore of its own; the id is still the sorted join.
  assert.equal(conversationIdFor('zed', 'shop_found-house'), 'shop_found-house_zed');
});

test('every shell uid sorts inside the range the cleanup sweeps, and nothing else does', () => {
  // `removeShellListingPosts` finds its posts with a range query on authorId,
  // 'shop_' to 'shop_\uffff', because Firestore has no starts-with. If a real
  // uid could land in that range the sweep would delete a real seller's
  // listings, so this is the check that keeps it safe.
  const inRange = (uid: string) => uid >= 'shop_' && uid < 'shop_\uffff';

  for (const vendor of ['Polly Politics', 'Allways Drops', 'zzz', '1 Thing']) {
    assert.equal(inRange(shopUidFor(vendor)), true, vendor);
  }
  // Real uids are 28 characters of base62: no underscore, so none can match.
  for (const real of ['d1GMG6NPhUQplgS8p1nWT1ZedQ92', 'LlLpQCwWg4bxxnd1dqxVLESm7G32', 'shop', 'shoq']) {
    assert.equal(inRange(real), false, real);
  }
});
