import 'dart:math' as math;

import '../../models/models.dart';

/// Geohashing, for the radius search.
///
/// Firestore has no geo query. The standard trick is to store a geohash — a
/// string whose prefix narrows to a box on the map — and range-scan on it,
/// because a prefix scan is something Firestore *can* do. A circle is then
/// covered by a handful of boxes, and the exact distance filter runs over the
/// small candidate set that comes back.
///
/// Hand-rolled rather than a package: this is one well-specified algorithm,
/// about eighty lines, and the alternative adds a dependency to the whole app
/// for it.
abstract final class Geohash {
  static const _base32 = '0123456789bcdefghjkmnpqrstuvwxyz';

  /// Encodes a point. Nine characters is roughly a 5 m box — far finer than a
  /// mile-scale search needs, but the extra precision costs nothing and makes
  /// the same field usable for pickup-level distances later.
  static String encode(double lat, double lng, {int precision = 9}) {
    var latMin = -90.0, latMax = 90.0;
    var lngMin = -180.0, lngMax = 180.0;

    final hash = StringBuffer();
    var bit = 0;
    var index = 0;
    var even = true;

    while (hash.length < precision) {
      if (even) {
        final mid = (lngMin + lngMax) / 2;
        if (lng > mid) {
          index = index * 2 + 1;
          lngMin = mid;
        } else {
          index *= 2;
          lngMax = mid;
        }
      } else {
        final mid = (latMin + latMax) / 2;
        if (lat > mid) {
          index = index * 2 + 1;
          latMin = mid;
        } else {
          index *= 2;
          latMax = mid;
        }
      }
      even = !even;

      if (++bit == 5) {
        hash.write(_base32[index]);
        bit = 0;
        index = 0;
      }
    }
    return hash.toString();
  }

  /// The prefix ranges covering a circle.
  ///
  /// Each pair is `[start, end]` for a `>= start && < end` scan. A circle
  /// rarely lands inside one box, so this returns the box the centre is in
  /// plus its eight neighbours at a precision chosen to fit the radius —
  /// nine ranges at most, well inside what Firestore will run in parallel.
  static List<(String, String)> coverRanges(
    double lat,
    double lng,
    double radiusMiles,
  ) {
    final precision = _precisionFor(radiusMiles);
    final centre = encode(lat, lng, precision: precision);

    // Neighbours are found by re-encoding points offset by roughly one box in
    // each direction. Cruder than walking the base-32 neighbour tables, and
    // correct at the boundaries — including the poles and the date line —
    // which those tables get wrong if you write them from memory.
    final latStep = _boxHeightMiles(precision);
    final lngStep = latStep / math.max(math.cos(lat * math.pi / 180).abs(), 0.01);

    final hashes = <String>{centre};
    for (final dLat in [-1, 0, 1]) {
      for (final dLng in [-1, 0, 1]) {
        final nextLat = (lat + dLat * latStep / 69.0).clamp(-90.0, 90.0);
        var nextLng = lng + dLng * lngStep / 69.0;
        if (nextLng > 180) nextLng -= 360;
        if (nextLng < -180) nextLng += 360;
        hashes.add(encode(nextLat, nextLng, precision: precision));
      }
    }

    return [
      for (final hash in hashes.toList()..sort()) (hash, '$hash~'),
    ];
  }

  /// How many characters keep the box comfortably larger than the radius.
  ///
  /// Too fine and the circle needs more boxes than Firestore will scan; too
  /// coarse and every search reads the whole state.
  static int _precisionFor(double radiusMiles) {
    if (radiusMiles > 300) return 2;
    if (radiusMiles > 80) return 3;
    if (radiusMiles > 20) return 4;
    if (radiusMiles > 3) return 5;
    return 6;
  }

  /// Roughly how tall a box is, in miles, at a given precision.
  static double _boxHeightMiles(int precision) => switch (precision) {
    1 => 3000,
    2 => 390,
    3 => 96,
    4 => 12,
    5 => 3,
    _ => 0.4,
  };

  /// Whether a point is genuinely inside the circle.
  ///
  /// The prefix scan returns boxes, and a box overlapping a circle is not the
  /// same as a point being inside it — so this is the filter that stops a
  /// listing 25 miles away appearing in a 20-mile search.
  static bool within(
    double lat,
    double lng,
    double centreLat,
    double centreLng,
    double radiusMiles,
  ) => Geo.milesBetween(centreLat, centreLng, lat, lng) <= radiusMiles;
}
