import { strict as assert } from 'node:assert';
import { test } from 'node:test';

import { titleWords } from '../src/catalog.ts';

test('a title becomes its distinct lowercase words, in order', () => {
  // The search screen matches one word with array-contains, so "snowboard"
  // must be present for "The Complete Snowboard" or search finds nothing.
  assert.deepEqual(titleWords('The Complete Snowboard'), ['the', 'complete', 'snowboard']);
  assert.deepEqual(titleWords('The Collection Snowboard: Hydrogen'), [
    'the', 'collection', 'snowboard', 'hydrogen',
  ]);
});

test('punctuation and repeats do not become words', () => {
  assert.deepEqual(titleWords("Kali's Lip Balm — lip balm, 2-pack!"), [
    'kali', 's', 'lip', 'balm', '2', 'pack',
  ]);
  assert.deepEqual(titleWords(''), []);
  assert.deepEqual(titleWords('   '), []);
});
