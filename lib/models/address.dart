import 'package:flutter/foundation.dart';

/// A postal address.
///
/// Kept structured rather than a formatted block of text because shipping
/// providers, tax calculation and the radius search all need the parts.
@immutable
class Address {
  const Address({
    required this.name,
    required this.line1,
    required this.city,
    required this.region,
    required this.postalCode,
    this.id,
    this.line2,
    this.countryCode = 'US',
    this.phone,
    this.isDefault = false,
    this.lat,
    this.lng,
  });

  /// Null until saved.
  final String? id;
  final String name;
  final String line1;
  final String? line2;
  final String city;

  /// State or province.
  final String region;
  final String postalCode;
  final String countryCode;
  final String? phone;
  final bool isDefault;

  /// Set once geocoded, so "near me" can start from a saved address rather
  /// than requiring a location permission.
  final double? lat;
  final double? lng;

  /// "Detroit, MI" — the short form used next to a listing or an order.
  String get cityState => '$city, $region';

  /// The single line shown in a summary row: "Maya E. · Detroit, MI".
  String get summary => '$name · $cityState';

  List<String> get displayLines => [
    name,
    line1,
    if (line2 != null && line2!.isNotEmpty) line2!,
    '$city, $region $postalCode',
    if (countryCode != 'US') countryCode,
  ];

  Address copyWith({
    String? id,
    String? name,
    String? line1,
    String? line2,
    String? city,
    String? region,
    String? postalCode,
    String? phone,
    bool? isDefault,
    double? lat,
    double? lng,
  }) => Address(
    id: id ?? this.id,
    name: name ?? this.name,
    line1: line1 ?? this.line1,
    line2: line2 ?? this.line2,
    city: city ?? this.city,
    region: region ?? this.region,
    postalCode: postalCode ?? this.postalCode,
    countryCode: countryCode,
    phone: phone ?? this.phone,
    isDefault: isDefault ?? this.isDefault,
    lat: lat ?? this.lat,
    lng: lng ?? this.lng,
  );
}
