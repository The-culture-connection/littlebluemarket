import { strict as assert } from 'node:assert';
import { test } from 'node:test';

import { parseHashtags, parseMentionHandles } from '../src/mentions.ts';

/**
 * These two patterns are a copy of `parseMentionHandles` and `parseHashtags`
 * in `lib/models/notification.dart`, because the phone highlights exactly
 * what the backend resolves. The cases below are the ones where a
 * hand-rolled pattern usually goes wrong, and they are the same cases the
 * Dart side is held to.
 */

test('a handle is picked out, once, however often it appears', () => {
  assert.deepEqual(parseMentionHandles('thanks @kali and @kali again'), ['kali']);
  assert.deepEqual(parseMentionHandles('@Kali and @kali are one person'), ['Kali']);
});

test('a full stop that ends a sentence is not part of the handle', () => {
  assert.deepEqual(parseMentionHandles('go and see @foundhouse.'), ['foundhouse']);
  // But one inside it is.
  assert.deepEqual(parseMentionHandles('@found.house makes bowls'), ['found.house']);
});

test('an email address is not a mention', () => {
  assert.deepEqual(parseMentionHandles('write to grace@example.com'), []);
});

test('several handles come back in the order they were written', () => {
  assert.deepEqual(
    parseMentionHandles('@rae, @kali and @dee are at the market'),
    ['rae', 'kali', 'dee'],
  );
});

test('no handles is an empty list, not a null', () => {
  assert.deepEqual(parseMentionHandles('nothing to see here'), []);
  assert.deepEqual(parseMentionHandles(''), []);
});

test('hashtags keep the spelling they were first written in', () => {
  assert.deepEqual(parseHashtags('#PlasticFree and #plasticfree'), ['#PlasticFree']);
  assert.deepEqual(parseHashtags('#WomanOwned #BIPOCOwned'), ['#WomanOwned', '#BIPOCOwned']);
});

test('a bare hash is not a hashtag', () => {
  assert.deepEqual(parseHashtags('# not a tag'), []);
  assert.deepEqual(parseHashtags('number #1 seller'), ['#1']);
});

test('the two do not collect each other', () => {
  const text = 'Meet @kali at the #HolidayMarket';
  assert.deepEqual(parseMentionHandles(text), ['kali']);
  assert.deepEqual(parseHashtags(text), ['#HolidayMarket']);
});
