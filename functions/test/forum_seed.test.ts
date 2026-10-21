import { strict as assert } from 'node:assert';
import { test } from 'node:test';

import { forumsToCreate, STARTER_FORUMS } from '../src/forum_seed.ts';

/** Pressing the button twice must never double a forum. */

test('every starter forum is made when none exist', () => {
  assert.equal(forumsToCreate([]).length, STARTER_FORUMS.length);
});

test('a forum already there is skipped, whatever its case', () => {
  const left = forumsToCreate(['  wins and shoutouts ', 'Photos and Listings']);
  assert.equal(left.length, STARTER_FORUMS.length - 2);
  assert.ok(!left.some((f) => f.title === 'Wins and Shoutouts'));
});

test('a second press makes nothing', () => {
  assert.deepEqual(forumsToCreate(STARTER_FORUMS.map((f) => f.title)), []);
});

test('the copy has no em dashes', () => {
  // Grace: no em dashes anywhere.
  assert.ok(!JSON.stringify(STARTER_FORUMS).includes('\u2014'));
});
