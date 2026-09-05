import { strict as assert } from 'node:assert';
import { test } from 'node:test';

import { parseGeocode } from '../src/geocode.ts';
import { mentionsToNotify } from '../src/notifications.ts';

test('a Nominatim answer becomes a point, and nothing becomes null', () => {
  assert.deepEqual(parseGeocode([{ lat: '42.3314', lon: '-83.0458', display_name: 'Detroit' }]), { lat: 42.3314, lng: -83.0458 });
  assert.equal(parseGeocode([]), null);
  assert.equal(parseGeocode({ error: 'x' }), null);
  assert.equal(parseGeocode([{ lat: 'north', lon: 'west' }]), null);
});

test('only newly mentioned members are notified, never the author', () => {
  assert.deepEqual(mentionsToNotify({ authorId: 'a', mentionedUids: ['a', 'b', 'c'] }, undefined), ['b', 'c']);
  assert.deepEqual(mentionsToNotify({ authorId: 'a', mentionedUids: ['b', 'c'] }, { mentionedUids: ['b'] }), ['c']);
  assert.deepEqual(mentionsToNotify({ authorId: 'a' }, undefined), []);
  assert.deepEqual(mentionsToNotify(undefined, { mentionedUids: ['b'] }), []);
});
