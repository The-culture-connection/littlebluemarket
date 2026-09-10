import { strict as assert } from 'node:assert';
import { test } from 'node:test';

import { lowerTags, sameTags } from '../src/profile_tags.ts';

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
