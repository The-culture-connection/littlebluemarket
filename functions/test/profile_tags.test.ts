import { strict as assert } from 'node:assert';
import { test } from 'node:test';

import {
  lowerTags,
  tagKeyMirrorPatch,
  tagKeys,
  sameTags,
} from '../src/profile_tags.ts';

/**
 * A profile's hashtags are stored as they were typed; `array-contains` is
 * exact. The lowercase mirror is what lets a search find "#WomanOwned" when
 * someone types "#womanowned".
 */
test('the mirror folds case, adds the hash, and dedupes', () => {
  assert.deepEqual(lowerTags(['#WomanOwned', '#BIPOCOwned']), ['#womanowned', '#bipocowned']);
  assert.deepEqual(lowerTags(['WomanOwned']), ['#womanowned']);
  assert.deepEqual(lowerTags([' #PlasticFree ']), ['#plasticfree']);
  assert.deepEqual(lowerTags(['#Tag', '#tag', '#TAG']), ['#tag'], 'one entry, not three');
  assert.deepEqual(lowerTags(['', '   ']), []);
  assert.deepEqual(lowerTags(['#ok', 42, null]), ['#ok'], 'a stray non-string is skipped');
  assert.deepEqual(lowerTags(undefined), [], 'a profile with no tags at all');
});

test('the trigger only writes when the mirror has drifted', () => {
  assert.equal(sameTags(['#a', '#b'], ['#b', '#a']), true, 'order does not matter');
  assert.equal(sameTags(['#a'], ['#a', '#b']), false);
  assert.equal(sameTags([], []), true, 'no write, so no trigger loop');
});

/**
 * The same mirror on a post, and the reason the tag pages were empty.
 *
 * Grace, 2026-09-28: "Items or people that have tags are not showing up in
 * that tag's detail page on prod." The query guessed at spellings —
 * `#womanowned`, `#WOMANOWNED`, `#Womanowned` — and the tag people actually
 * type is `#WomanOwned`. Almost every hashtag on this market is two words
 * with an inner capital, so almost every tag page was empty of everything.
 */
void test('a post mirrors its hashtags as keys, whatever the spelling', () => {
  assert.deepEqual(tagKeys(['#WomanOwned']), ['womanowned']);
  assert.deepEqual(tagKeys(['#BIPOCOwned', '#PlasticFree']), ['bipocowned', 'plasticfree']);
  // The spelling that broke it, and the three the old query guessed, all
  // land on the same key, which is the whole point.
  assert.deepEqual(
    tagKeys(['#WomanOwned', '#womanowned', '#WOMANOWNED', '#Womanowned']),
    ['womanowned'],
  );
  // A tag typed without its hash still counts, and blanks do not.
  assert.deepEqual(tagKeys(['handmade', '  ', '#']), ['handmade']);
  assert.deepEqual(tagKeys(undefined), []);
  assert.deepEqual(tagKeys(['#Made', 42, null]), ['made']);
});

void test('the post mirror is written once and then leaves itself alone', () => {
  // The trigger writes the post it is triggered by, so "already in step"
  // has to mean "write nothing" or it loops for ever.
  assert.deepEqual(tagKeyMirrorPatch({ tags: ['#WomanOwned'] }), { tagsLower: ['womanowned'] });
  assert.equal(tagKeyMirrorPatch({ tags: ['#WomanOwned'], tagsLower: ['womanowned'] }), null);
  // Order is not drift.
  assert.equal(
    tagKeyMirrorPatch({ tags: ['#A', '#B'], tagsLower: ['b', 'a'] }),
    null,
  );
  // A tag removed from a post leaves the page it was on.
  assert.deepEqual(tagKeyMirrorPatch({ tags: [], tagsLower: ['womanowned'] }), { tagsLower: [] });
});

void test('a catalogue product mirrors its hashtags the same way', () => {
  // The half that actually mattered. Grace, 2026-09-28: a shirt tagged
  // #CanTEditHistory, and the page for #cantedithistory showing "0 things
  // here". The tag is on the product, not on any post, and the two strings
  // are not equal, which is all `array-contains` asks.
  assert.deepEqual(
    tagKeyMirrorPatch({ tags: ['#CanTEditHistory', '#AntiMagaTee'] }),
    { tagsLower: ['cantedithistory', 'antimagatee'] },
  );
  // The spelling on the product and the key in the route meet in the middle.
  assert.ok(tagKeys(['#CanTEditHistory']).includes('cantedithistory'));
  // A product with no hashtags writes nothing, so the catalogue trigger
  // does not rewrite every product on the market for no reason.
  assert.equal(tagKeyMirrorPatch({ tags: [] }), null);
  assert.equal(tagKeyMirrorPatch({}), null);
});
