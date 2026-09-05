import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../data/repositories/dev_error_sink.dart';
import '../models/models.dart';
import 'providers.dart';
import 'session.dart';

/// Where "Near me" measures from.
///
/// The phone first, with permission asked in plain words. Failing that, the
/// city on the profile, which the backend has turned into a point. Failing
/// that, the toggle stays off and says why, rather than filtering everything
/// out of a search and calling it "nothing nearby".
enum NearMeOutcome { ready, needsCity }

Future<NearMeOutcome> ensureNearMeOrigin(WidgetRef ref) async {
  final filters = ref.read(searchFiltersProvider);
  if (filters.origin != null) return NearMeOutcome.ready;

  final fromDevice = kUnderFlutterTest ? null : await _deviceLocation();
  if (fromDevice != null) {
    ref.read(searchFiltersProvider.notifier).setOrigin(fromDevice);
    return NearMeOutcome.ready;
  }

  final me = ref.read(meProvider);
  if (me != null && me.lat != null && me.lng != null) {
    ref
        .read(searchFiltersProvider.notifier)
        .setOrigin(
          SearchOrigin(
            lat: me.lat!,
            lng: me.lng!,
            label: me.cityState.isEmpty ? 'Your city' : me.cityState,
          ),
        );
    return NearMeOutcome.ready;
  }
  return NearMeOutcome.needsCity;
}

Future<SearchOrigin?> _deviceLocation() async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return null;
    }
    // Whatever the phone already knows is good enough for a radius.
    final last = await Geolocator.getLastKnownPosition();
    if (last != null) return _origin(last);
    // A fresh fix. On Android the platform location manager is asked
    // directly: the fused provider on an emulator never sees the fix the
    // emulator was given, which is why "Near me" timed out there.
    final settings = defaultTargetPlatform == TargetPlatform.android
        ? AndroidSettings(
            accuracy: LocationAccuracy.high,
            forceLocationManager: true,
            timeLimit: const Duration(seconds: 15),
          )
        : const LocationSettings(
            accuracy: LocationAccuracy.medium,
            timeLimit: Duration(seconds: 15),
          );
    final position = await Geolocator.getCurrentPosition(
      locationSettings: settings,
    );
    return _origin(position);
  } on TimeoutException {
    // No fix within the limit: a phone indoors, an emulator with no
    // location set. Expected, not an error; the profile city is next.
    return null;
  } catch (error, stack) {
    // A missing plugin or a refused service: reported so a dev sees why.
    DevErrorSink.report(error, stack, 'location getCurrentPosition');
    return null;
  }
}

SearchOrigin _origin(Position position) => SearchOrigin(
  lat: position.latitude,
  lng: position.longitude,
  label: 'Current location',
  fromDevice: true,
);

/// The Near me toggle, wherever it appears: off is one tap; on needs a place
/// to measure from, and says so when there is none.
Future<void> toggleNearMe(BuildContext context, WidgetRef ref) async {
  final filters = ref.read(searchFiltersProvider);
  if (filters.nearMe) {
    ref.read(searchFiltersProvider.notifier).toggleNearMe();
    return;
  }
  final messenger = ScaffoldMessenger.of(context);
  final outcome = await ensureNearMeOrigin(ref);
  if (outcome == NearMeOutcome.needsCity) {
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 8),
        content: const Text(
          'Near me needs a place to measure from. Allow location, or add '
          'your city in Edit profile.',
        ),
        action: SnackBarAction(
          label: 'Add my city',
          onPressed: () {
            if (context.mounted) context.push('/you/edit');
          },
        ),
      ),
    );
    return;
  }
  ref.read(searchFiltersProvider.notifier).toggleNearMe();
}
