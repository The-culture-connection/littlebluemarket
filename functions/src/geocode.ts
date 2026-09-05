import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions';

import { geohash } from './geohash.ts';

/**
 * Where a seller is, from the city they typed.
 *
 * "Near me" measures from the buyer's phone to the seller's coordinates,
 * and a seller only ever types "Detroit, MI". OpenStreetMap's Nominatim
 * turns that into a point, free, with a User-Agent and one request per
 * second — fine for a profile save, and cached on the profile so it runs
 * once per city, not once per view.
 */

export interface GeoPoint {
  lat: number;
  lng: number;
}

/** Pure: Nominatim's answer → a point, or null when it found nothing. */
export function parseGeocode(json: unknown): GeoPoint | null {
  if (!Array.isArray(json) || json.length === 0) return null;
  const first = json[0] as { lat?: unknown; lon?: unknown };
  const lat = Number(first.lat);
  const lng = Number(first.lon);
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) return null;
  return { lat, lng };
}

export async function geocodeCity(city: string, fetchImpl: typeof fetch = fetch): Promise<GeoPoint | null> {
  const q = city.trim();
  if (!q) return null;
  const url = `https://nominatim.openstreetmap.org/search?format=json&limit=1&q=${encodeURIComponent(q)}`;
  const res = await fetchImpl(url, {
    headers: { 'User-Agent': 'LittleBlueMarket/1.0 (little-blue-610e5)', Accept: 'application/json' },
  });
  if (!res.ok) {
    logger.warn('Geocoding request failed', { status: res.status, q });
    return null;
  }
  return parseGeocode(await res.json());
}

/**
 * Runs on a profile write. When the city is new or has no point yet, it is
 * geocoded, stored on the profile, and copied onto every product the
 * seller has so the radius search can find them.
 */
export async function geocodeProfileIfNeeded(
  uid: string,
  before: Record<string, unknown> | undefined,
  after: Record<string, unknown> | undefined,
  fetchImpl: typeof fetch = fetch,
): Promise<'skipped' | 'geocoded' | 'not-found'> {
  const city = String(after?.cityState ?? '').trim();
  if (!city) return 'skipped';
  const cityChanged = String(before?.cityState ?? '').trim() !== city;
  const hasPoint = typeof after?.lat === 'number' && typeof after?.lng === 'number';
  if (!cityChanged && hasPoint) return 'skipped';

  const point = await geocodeCity(city, fetchImpl);
  const db = getFirestore();
  if (!point) {
    await db.collection('users').doc(uid).set({ geocodeFailedFor: city }, { merge: true });
    return 'not-found';
  }
  const hash = geohash(point.lat, point.lng);
  await db.collection('users').doc(uid).set(
    { lat: point.lat, lng: point.lng, geohash: hash, geocodedFor: city, geocodeFailedFor: FieldValue.delete() },
    { merge: true },
  );

  // The seller's products carry the point too; that is what the radius
  // query scans.
  const products = await db.collection('catalog').where('sellerId', '==', uid).get();
  for (let i = 0; i < products.docs.length; i += 400) {
    const batch = db.batch();
    for (const doc of products.docs.slice(i, i + 400)) {
      batch.set(doc.ref, { lat: point.lat, lng: point.lng, geohash: hash, cityState: city }, { merge: true });
    }
    await batch.commit();
  }
  logger.info('Geocoded a profile', { uid, city, products: products.size });
  return 'geocoded';
}
