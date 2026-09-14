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
}

final promoTurnTakenProvider = NotifierProvider<PromoTurnTaken, bool>(
  PromoTurnTaken.new,
);

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
