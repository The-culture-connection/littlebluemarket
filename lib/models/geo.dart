import 'dart:math' as math;

/// Distance on the ground.
///
/// Used in two places that must agree: the radius filter that decides whether a
/// listing is in your results, and the distance shown on the card once it is.
/// If those two ever disagree, people see listings labelled 25 mi inside a
/// 20 mi search.
abstract final class Geo {
  static const earthRadiusMiles = 3958.7613;

  /// Great-circle distance in miles.
  ///
  /// Haversine rather than a flat approximation: cheap enough at this scale,
  /// and it does not fall apart at high latitudes or across the date line.
  static double milesBetween(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    final dLat = _radians(lat2 - lat1);
    final dLng = _radians(lng2 - lng1);
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_radians(lat1)) *
            math.cos(_radians(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return earthRadiusMiles * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  static double _radians(double degrees) => degrees * math.pi / 180;
}
