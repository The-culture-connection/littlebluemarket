import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether the first-time tour is waiting to be shown.
///
/// Set once, when a profile has just been created; consumed by the app
/// shell the first time it builds after that. It never survives a restart
/// on purpose: the tour belongs to that first successful arrival, and the
/// phone remembers it was shown (see `Tips.firstTour`).
class TourPending extends Notifier<bool> {
  @override
  bool build() => false;

  void request() => state = true;

  /// True exactly once per request: the caller that gets `true` shows it.
  bool consume() {
    if (!state) return false;
    state = false;
    return true;
  }
}

final tourPendingProvider = NotifierProvider<TourPending, bool>(
  TourPending.new,
);
