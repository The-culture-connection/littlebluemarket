import { strict as assert } from 'node:assert';
import { test } from 'node:test';

import {
  geoFieldsFor,
  listingGeoIsCurrent,
  placeForListing,
  placeKey,
} from '../src/directory_geo.ts';

/**
 * Putting the directory on the map so Near me can answer.
 *
 * Measured against production, 2026-09-28: 3 of 16,567 catalogue products
 * are findable by distance, because a product takes its point from its
 * seller's profile city and almost no vendor has claimed a shop and typed
 * one. The directory is the half that already knows: 1,785 published
 * listings, 347 with the town littlebluecart.com holds for them.
 */

void test('a real town is used, with its state', () => {
  assert.equal(placeForListing({ city: 'Springfield', state: 'VA' }), 'Springfield, VA');
  assert.equal(placeForListing({ city: 'Detroit', state: 'MI' }), 'Detroit, MI');
  // A town with no state is still a town.
  assert.equal(placeForListing({ city: 'Ypsilanti' }), 'Ypsilanti');
});

void test('"Online/Virtual Business" is not a place, and is never guessed at', () => {
  // 505 of the 1,785 published listings carry exactly this. Putting them
  // anywhere would say a business is eleven miles away when it is nowhere.
  assert.equal(placeForListing({ locationLabel: '*Online/Virtual Business, ' }), null);
  assert.equal(placeForListing({ locationLabel: 'Online/Virtual Business' }), null);
  assert.equal(placeForListing({ city: 'Online' }), null);
  assert.equal(placeForListing({ locationLabel: 'Nationwide' }), null);
  assert.equal(placeForListing({ locationLabel: 'Remote' }), null);
  assert.equal(placeForListing({}), null);
});

void test('a bare state is refused: it is a region, not a point', () => {
  // The next commonest labels after "online" are "California", "Ohio",
  // "New York". A state's centre is not where the business is, and a
  // 20-mile circle drawn around it is a wrong answer rather than a rough
  // one. Better to be absent from Near me than to be wrong in it.
  assert.equal(placeForListing({ locationLabel: 'California, ' }), null);
  assert.equal(placeForListing({ locationLabel: 'Ohio, ' }), null);
  assert.equal(placeForListing({ locationLabel: 'North Carolina, ' }), null);
});

void test('a label shaped "Town, ST" is specific enough to use', () => {
  assert.equal(placeForListing({ locationLabel: 'Detroit, MI' }), 'Detroit, MI');
  assert.equal(placeForListing({ locationLabel: ' ypsilanti , mi ' }), 'ypsilanti, MI');
  // The structured address wins when both are there: it is what the website
  // holds deliberately, rather than a line somebody typed.
  assert.equal(
    placeForListing({ city: 'Hamtramck', state: 'MI', locationLabel: 'Detroit, MI' }),
    'Hamtramck, MI',
  );
});

void test('one place is asked about once, however it was typed', () => {
  // 1,785 listings share 345 places and the geocoder asks for no more than
  // one request a second, so the cache key has to ignore the spelling.
  assert.equal(placeKey('Detroit, MI'), placeKey('  detroit,   mi  '));
  assert.equal(placeKey('St. Petersburg, FL'), 'st petersburg, fl');
  assert.equal(placeKey(''), '');
});

void test('a listing already on the map is left alone', () => {
  const located = { geocodedFor: 'Detroit, MI', lat: 42.33, lng: -83.04, geohash: 'dpsc' };
  assert.equal(listingGeoIsCurrent(located, 'Detroit, MI'), true);
  // Moved town: it has to be looked up again.
  assert.equal(listingGeoIsCurrent(located, 'Hamtramck, MI'), false);
  // Half-written, from an older run that failed part way.
  assert.equal(listingGeoIsCurrent({ geocodedFor: 'Detroit, MI' }, 'Detroit, MI'), false);
  assert.equal(listingGeoIsCurrent({}, 'Detroit, MI'), false);
});

void test('what gets written is the point, its hash and what was asked', () => {
  const fields = geoFieldsFor({ lat: 42.3314, lng: -83.0458 }, 'Detroit, MI');
  assert.equal(fields.lat, 42.3314);
  assert.equal(fields.lng, -83.0458);
  assert.equal(fields.geocodedFor, 'Detroit, MI');
  // The hash is what the radius scan reads, so it has to be there and has
  // to be a prefix-comparable string.
  assert.equal(typeof fields.geohash, 'string');
  assert.ok((fields.geohash as string).length > 4);
});
