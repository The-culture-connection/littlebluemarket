import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions';

import { geocodeCity } from './geocode.ts';
import { geohash } from './geohash.ts';

/**
 * Putting directory businesses on the map, so "Near me" can answer.
 *
 * The Market half of Near me is starved: a product takes its point from its
 * seller's profile city, and almost no vendor has claimed a shop and typed
 * one, so 3 of 16,567 products are findable by distance. The directory is
 * the half that already knows where its businesses are — every listing
 * carries the street, city and state that littlebluecart.com holds — and
 * nothing was ever done with it (Grace, 2026-09-28).
 */

/** Places that are not places. */
const NOT_A_PLACE = /online|virtual|worldwide|nationwide|remote|n\/?a/i;

/** A two-letter state, which is what makes a label specific enough to use. */
const CITY_STATE = /^\s*([^,]{2,}?)\s*,\s*([A-Za-z]{2})\s*$/;

/**
 * The place to look up for a listing, or null when there is nothing honest
 * to look up. Pure.
 *
 * Deliberately strict, because the alternative is worse than an empty
 * result. 505 of the 1,785 published listings are labelled "*Online/Virtual
 * Business" and a further few hundred carry a bare state, "California" or
 * "Ohio". Geocoding those would put them at a state's centroid, and a
 * business shown as eleven miles away when it is anywhere in California is
 * not a near miss, it is a wrong answer. Only a real town is used:
 *
 *  * the structured `city` the website holds, with its state; or
 *  * a label shaped "Town, ST", which is a town and not a state.
 */
export function placeForListing(listing: Record<string, unknown>): string | null {
  const city = String(listing.city ?? '').trim();
  const state = String(listing.state ?? '').trim();
  if (city && !NOT_A_PLACE.test(city)) {
    return state ? `${city}, ${state}` : city;
  }

  const label = String(listing.locationLabel ?? '').trim();
  if (!label || NOT_A_PLACE.test(label)) return null;
  const match = CITY_STATE.exec(label);
  if (!match) return null;
  const town = match[1]!.trim();
  return NOT_A_PLACE.test(town) ? null : `${town}, ${match[2]!.toUpperCase()}`;
}

/** The cache key for a place. Pure. */
export function placeKey(place: string): string {
  return place.trim().toLowerCase().replace(/\s+/g, ' ').replace(/[^a-z0-9, ]/g, '');
}

export interface GeoPoint {
  lat: number;
  lng: number;
}

/**
 * A place's point, from the cache when we have looked it up before.
 *
 * 1,785 listings share 345 places, and the public geocoder asks for no more
 * than one request a second, so looking each listing up on its own would be
 * both rude and half an hour. A miss is remembered too, so a place that
 * cannot be found is not asked about once per listing that names it.
 */
export async function pointForPlace(
  place: string,
  fetchImpl: typeof fetch = fetch,
): Promise<GeoPoint | null> {
  const key = placeKey(place);
  if (!key) return null;
  const db = getFirestore();
  const ref = db.collection('geoPlaces').doc(key);
  const cached = (await ref.get()).data();
  if (cached) {
    const lat = Number(cached.lat);
    const lng = Number(cached.lng);
    return Number.isFinite(lat) && Number.isFinite(lng) ? { lat, lng } : null;
  }

  const point = await geocodeCity(place, fetchImpl);
  await ref.set(
    point
      ? { place, lat: point.lat, lng: point.lng, at: FieldValue.serverTimestamp() }
      : { place, notFound: true, at: FieldValue.serverTimestamp() },
    { merge: true },
  );
  return point;
}

/** What a listing's geo fields should be, given a point. Pure. */
export function geoFieldsFor(point: GeoPoint, place: string): Record<string, unknown> {
  return {
    lat: point.lat,
    lng: point.lng,
    geohash: geohash(point.lat, point.lng),
    geocodedFor: place,
  };
}

/** Whether this listing already has the point it should have. Pure. */
export function listingGeoIsCurrent(
  listing: Record<string, unknown>,
  place: string,
): boolean {
  return (
    String(listing.geocodedFor ?? '') === place &&
    typeof listing.lat === 'number' &&
    typeof listing.lng === 'number' &&
    typeof listing.geohash === 'string'
  );
}

/**
 * Puts a page of directory listings on the map. Resumable, and paced.
 *
 * Paced because the geocoder is a public service that asks for one request a
 * second; the cache means only a place never seen before costs a request, so
 * a second run over the same listings is instant.
 */
export async function geocodeDirectoryPage(
  options: { after?: string; limit?: number } = {},
  fetchImpl: typeof fetch = fetch,
): Promise<{
  checked: number;
  located: number;
  noPlace: number;
  notFound: number;
  cursor: string | null;
  done: boolean;
}> {
  const db = getFirestore();
  const limit = Math.min(Math.max(options.limit ?? 150, 1), 500);
  let query = db.collection('directoryListings').orderBy('__name__').limit(limit);
  if (options.after) query = query.startAfter(options.after);

  const snapshot = await query.get();
  let located = 0;
  let noPlace = 0;
  let notFound = 0;

  for (const doc of snapshot.docs) {
    const data = doc.data();
    const place = placeForListing(data);
    if (!place) {
      noPlace += 1;
      continue;
    }
    if (listingGeoIsCurrent(data, place)) continue;

    const before = Date.now();
    const cacheRef = db.collection('geoPlaces').doc(placeKey(place));
    const wasCached = (await cacheRef.get()).exists;
    const point = await pointForPlace(place, fetchImpl);
    if (!point) {
      notFound += 1;
    } else {
      await doc.ref.set(geoFieldsFor(point, place), { merge: true });
      located += 1;
    }
    // One request a second, and only when one was actually made.
    if (!wasCached) {
      const spent = Date.now() - before;
      if (spent < 1100) await new Promise((r) => setTimeout(r, 1100 - spent));
    }
  }

  const done = snapshot.size < limit;
  const cursor = snapshot.empty ? null : snapshot.docs[snapshot.docs.length - 1]!.id;
  logger.info('Directory geocoded', { checked: snapshot.size, located, noPlace, notFound, done });
  return { checked: snapshot.size, located, noPlace, notFound, cursor: done ? null : cursor, done };
}
