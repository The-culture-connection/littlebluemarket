import 'package:flutter_test/flutter_test.dart';
import 'package:little_blue_market/data/firebase/geohash.dart';
import 'package:little_blue_market/models/models.dart';

/// The radius search rests on this, and it is the one place where being subtly
/// wrong shows up as "why is a listing 500 miles away in my 20-mile search".
void main() {
  // Real coordinates, so the distances are checkable against a map.
  const detroit = (lat: 42.3314, lng: -83.0458);
  const hamtramck = (lat: 42.3928, lng: -83.0496); // ~4 mi from Detroit
  const nashville = (lat: 36.1627, lng: -86.7816); // ~471 mi from Detroit

  group('encode', () {
    test('is deterministic', () {
      expect(
        Geohash.encode(detroit.lat, detroit.lng),
        Geohash.encode(detroit.lat, detroit.lng),
      );
    });

    test('nearby points share a prefix', () {
      final a = Geohash.encode(detroit.lat, detroit.lng);
      final b = Geohash.encode(hamtramck.lat, hamtramck.lng);
      // Four characters is roughly a 12-mile box; two places four miles apart
      // should agree on at least the first three.
      expect(a.substring(0, 3), b.substring(0, 3));
    });

    test('distant points do not', () {
      final a = Geohash.encode(detroit.lat, detroit.lng);
      final b = Geohash.encode(nashville.lat, nashville.lng);
      expect(a.substring(0, 3), isNot(b.substring(0, 3)));
    });

    test('respects the requested precision', () {
      expect(Geohash.encode(detroit.lat, detroit.lng, precision: 5).length, 5);
      expect(Geohash.encode(detroit.lat, detroit.lng, precision: 9).length, 9);
    });

    test('handles the extremes without throwing', () {
      expect(Geohash.encode(90, 180), isNotEmpty);
      expect(Geohash.encode(-90, -180), isNotEmpty);
      expect(Geohash.encode(0, 0), isNotEmpty);
    });
  });

  group('coverRanges', () {
    test('produces ordered start/end pairs', () {
      final ranges = Geohash.coverRanges(detroit.lat, detroit.lng, 20);
      expect(ranges, isNotEmpty);
      for (final (start, end) in ranges) {
        expect(start.compareTo(end), lessThan(0));
      }
    });

    test('stays within what Firestore will run in parallel', () {
      // Each range is its own query, so this cannot grow without bound.
      for (final radius in [1.0, 20.0, 100.0, 500.0]) {
        final ranges = Geohash.coverRanges(detroit.lat, detroit.lng, radius);
        expect(ranges.length, lessThanOrEqualTo(9), reason: '$radius mi');
      }
    });

    test('a wider radius uses coarser boxes', () {
      final tight = Geohash.coverRanges(detroit.lat, detroit.lng, 2);
      final wide = Geohash.coverRanges(detroit.lat, detroit.lng, 400);
      expect(wide.first.$1.length, lessThan(tight.first.$1.length));
    });

    test('covers the point it is centred on', () {
      final ranges = Geohash.coverRanges(detroit.lat, detroit.lng, 20);
      final hash = Geohash.encode(detroit.lat, detroit.lng);
      final covered = ranges.any(
        (range) =>
            hash.compareTo(range.$1) >= 0 && hash.compareTo(range.$2) < 0,
      );
      expect(
        covered,
        isTrue,
        reason: 'the centre must be inside its own cover',
      );
    });

    test('covers a neighbour four miles away at a 20 mile radius', () {
      final ranges = Geohash.coverRanges(detroit.lat, detroit.lng, 20);
      final hash = Geohash.encode(hamtramck.lat, hamtramck.lng);
      final covered = ranges.any(
        (range) =>
            hash.compareTo(range.$1) >= 0 && hash.compareTo(range.$2) < 0,
      );
      expect(covered, isTrue);
    });
  });

  group('within', () {
    test('accepts a point inside the circle', () {
      expect(
        Geohash.within(
          hamtramck.lat,
          hamtramck.lng,
          detroit.lat,
          detroit.lng,
          20,
        ),
        isTrue,
      );
    });

    test('rejects a point outside it', () {
      // This is the filter that matters: the prefix scan returns boxes, and a
      // box overlapping the circle is not a point inside it.
      expect(
        Geohash.within(
          nashville.lat,
          nashville.lng,
          detroit.lat,
          detroit.lng,
          20,
        ),
        isFalse,
      );
    });
  });

  group('Geo.milesBetween', () {
    test('is zero for the same point', () {
      expect(
        Geo.milesBetween(detroit.lat, detroit.lng, detroit.lat, detroit.lng),
        closeTo(0, 0.001),
      );
    });

    test('matches a known distance', () {
      // Detroit to Nashville is about 471 miles as the crow flies. (Road
      // distance is nearer 525, which is not what this measures.)
      expect(
        Geo.milesBetween(
          detroit.lat,
          detroit.lng,
          nashville.lat,
          nashville.lng,
        ),
        closeTo(471, 10),
      );
    });

    test('is symmetric', () {
      final there = Geo.milesBetween(
        detroit.lat,
        detroit.lng,
        nashville.lat,
        nashville.lng,
      );
      final back = Geo.milesBetween(
        nashville.lat,
        nashville.lng,
        detroit.lat,
        detroit.lng,
      );
      expect(there, closeTo(back, 0.0001));
    });

    test('does not blow up across the date line', () {
      // Two points either side of 180°, about 70 miles apart.
      final distance = Geo.milesBetween(0, 179.5, 0, -179.5);
      expect(distance, closeTo(69, 5));
    });
  });
}
