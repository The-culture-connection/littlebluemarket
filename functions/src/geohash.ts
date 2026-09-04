/**
 * Geohash, matching the client's implementation exactly.
 *
 * The two have to agree: the function writes the hash and the app scans
 * prefixes over it, so a difference of one character means a search that
 * silently misses listings. Kept as a small duplicate rather than a shared
 * package, because the alternative is a build step across two languages for
 * eighty lines of well-specified algorithm.
 */
const BASE32 = '0123456789bcdefghjkmnpqrstuvwxyz';

export function geohash(lat: number, lng: number, precision = 9): string {
  let latMin = -90;
  let latMax = 90;
  let lngMin = -180;
  let lngMax = 180;

  let hash = '';
  let bit = 0;
  let index = 0;
  let even = true;

  while (hash.length < precision) {
    if (even) {
      const mid = (lngMin + lngMax) / 2;
      if (lng > mid) {
        index = index * 2 + 1;
        lngMin = mid;
      } else {
        index *= 2;
        lngMax = mid;
      }
    } else {
      const mid = (latMin + latMax) / 2;
      if (lat > mid) {
        index = index * 2 + 1;
        latMin = mid;
      } else {
        index *= 2;
        latMax = mid;
      }
    }
    even = !even;

    if (++bit === 5) {
      hash += BASE32[index];
      bit = 0;
      index = 0;
    }
  }
  return hash;
}
