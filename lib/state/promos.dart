import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/repositories/dev_error_sink.dart';
import '../models/models.dart';
import 'providers.dart';
import 'session.dart';

/// Which adverts and announcements this phone has already been shown.
///
/// Kept on the phone rather than on the profile, for the same reason the
/// tips are: it is a fact about this device having displayed something, not
/// about the person. A phone with no storage sees a popup again next launch,
/// which is a far smaller problem than a popup nobody can ever dismiss.
class PromosSeenNotifier extends Notifier<Set<String>> {
  static const _key = 'lbm.promosSeen';

  /// Bounded so a year of adverts cannot grow the stored list without limit.
  /// Oldest ids fall off; an advert that old is long gone anyway.
  static const _keep = 200;

  @override
  Set<String> build() {
    if (!kUnderFlutterTest) _load();
    return const {};
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final seen = prefs.getStringList(_key) ?? const [];
      state = {...state, ...seen};
    } catch (_) {
      // Nothing remembered; every promo counts as unseen.
    }
  }

  bool seen(String id) => state.contains(id);

  Future<void> markSeen(String id) async {
    if (state.contains(id)) return;
    final next = [...state, id];
    state = next.length > _keep
        ? next.sublist(next.length - _keep).toSet()
        : next.toSet();
    if (kUnderFlutterTest) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_key, state.toList());
    } catch (_) {
      // Left unsaved; it shows once more next launch.
    }
  }

  /// Forgets every promo this phone has been shown, so the normal flow
  /// offers them again. For the Diagnostics screen: testing a popup that is
  /// shown once per phone otherwise means reinstalling the app.
  Future<void> forget() async {
    state = const {};
    if (kUnderFlutterTest) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {
      // Then it stays remembered, and Show it now is the way to test.
    }
  }
}

final promosSeenProvider = NotifierProvider<PromosSeenNotifier, Set<String>>(
  PromosSeenNotifier.new,
);

/// Whether a popup has already had its turn this app opening.
///
/// Grace's rule: one per opening. This is deliberately not persisted, so
/// force-closing the app and opening it again is what earns the next one.
class PromoTurnTaken extends Notifier<bool> {
  @override
  bool build() => false;

  void take() => state = true;

  /// Gives this opening its turn back, so the normal flow can offer another
  /// popup without force-closing the app. Diagnostics only.
  void release() => state = false;
}

final promoTurnTakenProvider = NotifierProvider<PromoTurnTaken, bool>(
  PromoTurnTaken.new,
);

/// A promo to show **right now**, ignoring every rule that governs the
/// normal flow: the three-second wait, one per app opening, never the same
/// one twice, and the audience filter.
///
/// Set only from the Diagnostics screen, which is dev-only. Testing a popup
/// that shows once per phone per app opening otherwise means reinstalling
/// the app between attempts, which is how Grace was having to do it
/// (2026-09-14). Nothing here is counted: an impression logged while
/// testing would be a lie in the advert's own numbers.
class PromoOverride extends Notifier<Promo?> {
  @override
  Promo? build() => null;

  void show(Promo promo) => state = promo;
  void clear() => state = null;
}

final promoOverrideProvider = NotifierProvider<PromoOverride, Promo?>(
  PromoOverride.new,
);

/// Every promo this phone is allowed to read, newest first, whoever it is
/// aimed at. The Diagnostics list; the normal flow uses
/// [promoForThisLaunchProvider], which filters.
final allPromosProvider = FutureProvider<List<Promo>>((ref) {
  return ref.watch(promoRepositoryProvider).live(limit: 50);
});

/// The one promo to fade in this app opening, or null when there is nothing
/// to show.
///
/// Read once and cached for the session: a popup that re-queried on every
/// tab change would be both wasteful and a second popup waiting to happen.
final promoForThisLaunchProvider = FutureProvider<Promo?>((ref) async {
  ref.keepAlive();
  if (ref.watch(promoTurnTakenProvider)) return null;

  final isSeller = ref.watch(isSellerProvider);
  final linked = ref.watch(directoryLinkProvider).value?.linked ?? false;
  final seen = ref.watch(promosSeenProvider);

  final live = await ref.watch(promoRepositoryProvider).live();
  for (final promo in live) {
    if (seen.contains(promo.id)) continue;
    if (!promo.showsTo(isSeller: isSeller, directoryLinked: linked)) continue;
    return promo;
  }
  return null;
});
