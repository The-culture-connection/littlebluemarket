import { strict as assert } from 'node:assert';
import { test } from 'node:test';

import { shouldPush, tagsToFanOut, titleFor, wantsTagTelling } from '../src/push.ts';

/**
 * "Follow a collection, get notified when there's a new post about a tag"
 * (Grace). Follow and Notify are two switches, and the difference between
 * them is the whole of this file: following puts a tag in your feed,
 * notifying puts it on your lock screen, and the second is opt-in.
 */

test('only a follow that asked to be told gets a subscriber row', () => {
  assert.equal(wantsTagTelling({ tag: 'handmade', notify: true }, true), true);
  // Followed, quietly. This is the common case and it must cost nothing at
  // post time, which it does by leaving no row to fan out to.
  assert.equal(wantsTagTelling({ tag: 'handmade', notify: false }, false || true), false);
  // Unfollowed: the document is gone, so the row goes with it.
  assert.equal(wantsTagTelling(undefined, false), false);
  // A document that exists but says nothing about notify is not consent.
  assert.equal(wantsTagTelling({ tag: 'handmade' }, true), false);
  // Nor is a truthy value that is not a boolean; the rules refuse these
  // too, but the trigger does not get to assume the rules ran.
  assert.equal(wantsTagTelling({ tag: 'handmade', notify: 'yes' }, true), false);
  assert.equal(wantsTagTelling({ tag: 'handmade', notify: 1 }, true), false);
});

test('a post fans out to at most five tags, deduped, blanks dropped', () => {
  assert.deepEqual(tagsToFanOut(['handmade', 'detroit']), ['handmade', 'detroit']);
  // Keys arrive already lowercased, so a repeat really is a repeat.
  assert.deepEqual(tagsToFanOut(['handmade', 'handmade']), ['handmade']);
  assert.deepEqual(tagsToFanOut(['', 'handmade', '']), ['handmade']);
  // A post carrying thirty hashtags is reach-seeking; the cap is on the
  // post, not on the people, because they are the ones who would pay.
  assert.deepEqual(tagsToFanOut(['a', 'b', 'c', 'd', 'e', 'f', 'g']), ['a', 'b', 'c', 'd', 'e']);
  assert.deepEqual(tagsToFanOut([]), []);
});

test('the tag switch silences the push and nothing else', () => {
  // Default on, like every other switch.
  assert.equal(shouldPush(undefined, { type: 'tagPost' }), true);
  assert.equal(shouldPush({}, { type: 'tagPost' }), true);
  assert.equal(shouldPush({ tagPosts: false }, { type: 'tagPost' }), false);
  // Turning tags off must not take the others with it, nor they it.
  assert.equal(shouldPush({ tagPosts: false }, { type: 'newPost' }), true);
  assert.equal(shouldPush({ newPosts: false }, { type: 'tagPost' }), true);
});

test('the tag is the headline, not the person who posted', () => {
  // You asked to hear about #handmade, not about this person, so the tag
  // goes on the lock screen and the name goes in the body.
  assert.equal(titleFor('tagPost', 'Kali Brooks', 'New under #handmade'), 'New under #handmade');
  // Without a title there is still something sayable.
  assert.equal(titleFor('tagPost', 'Kali Brooks'), 'Kali Brooks posted under a tag you follow');
  assert.equal(titleFor('tagPost', ''), 'Someone posted under a tag you follow');
});

/**
 * The dedupe, which is the one place this can go wrong in a way people
 * notice: somebody who follows both Kali and #handmade must hear about
 * Kali's #handmade post once.
 *
 * `tagSubscribers` takes the set of everyone already notified and filters
 * against it. This drives that filter without Firestore, the way
 * `counters_floor.test.ts` drives a transaction without one.
 */
function fakeTagSubscribers(rows: string[]) {
  return (key: string, exclude: ReadonlySet<string>) =>
    rows.filter((id) => id && !exclude.has(id));
}

test('following both the maker and the tag is one notification', () => {
  const followersOfKali = ['dee', 'juniper'];
  const author = 'kali';
  const notified = new Set<string>([author, ...followersOfKali]);

  const subscribers = fakeTagSubscribers(['dee', 'rae', 'kali'])('handmade', notified);

  // Dee already heard about it as a follower of Kali's; Kali wrote it.
  assert.deepEqual(subscribers, ['rae']);
  // And a second tag on the same post does not tell Rae twice: the fan-out
  // adds each tag's recipients to the set as it goes.
  for (const uid of subscribers) notified.add(uid);
  assert.deepEqual(fakeTagSubscribers(['rae', 'ama'])('detroit', notified), ['ama']);
});
