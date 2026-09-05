import { strict as assert } from 'node:assert';
import { test } from 'node:test';

import { counterDelta, starKey } from '../src/counters.ts';

test('a document appearing counts up, disappearing counts down, editing counts nothing', () => {
  assert.equal(counterDelta(false, true), 1);
  assert.equal(counterDelta(true, false), -1);
  assert.equal(counterDelta(true, true), 0);
  assert.equal(counterDelta(false, false), 0);
});

test('a rating lands on one of five bars, whatever the client sent', () => {
  assert.equal(starKey(5), 'stars5');
  assert.equal(starKey(3.6), 'stars4');
  assert.equal(starKey(0), 'stars1');
  assert.equal(starKey(9), 'stars5');
  assert.equal(starKey('4'), 'stars4');
  assert.equal(starKey('lots'), null);
});
