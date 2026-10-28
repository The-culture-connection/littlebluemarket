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
/// A stream, not a read: pausing an advert on the admin website has to take
/// it off the feed of a phone that is already looking at it.
final allPromosProvider = StreamProvider<List<Promo>>((ref) {
  return ref.watch(promoRepositoryProvider).watchLive(limit: 50);
});

/// Little Blue Market's own pages posted to the For you feed (Grace,
/// 2026-10-28). A stream, so hiding one on the admin website takes it off
/// a feed somebody is already looking at.
final storePagesProvider = StreamProvider<List<StorePage>>((ref) {
  return ref.watch(promoRepositoryProvider).watchStorePages();
});

/// A posted page with nothing to draw, read on the spot when it is opened.
/// See [PromoRepository.readStorePage].
final storePageReadProvider = FutureProvider.family<int, String>((ref, id) {
  return ref.watch(promoRepositoryProvider).readStorePage(id);
});

/// A promo somebody tapped on, to open as the full popup with every photo
/// to swipe through (Grace, 2026-10-28: "Allow to click on announcements to
/// show pop up version and slide through images").
///
/// Not the Diagnostics override: this one was asked for by the person
/// holding the phone, so it counts as seen and never pops up by itself
/// afterwards, and it stays until they put it away rather than timing out
/// in the middle of their reading it.
class PromoOpened extends Notifier<Promo?> {
  @override
  Promo? build() => null;

  void open(Promo promo) => state = promo;
  void clear() => state = null;
}

final promoOpenedProvider = NotifierProvider<PromoOpened, Promo?>(
  PromoOpened.new,
);

/// The one promo to fade in this app opening, or null when there is nothing
/// to show.
///
/// **Watched live, not looked up once.** It used to be a single read at
/// launch, re-asked only after five minutes in the background, so a popup
/// posted while somebody had the app open, or had just switched away to
/// post it, never reached them: Grace posted one, went back to the app,
/// and nothing came (2026-10-28, "Popups not working"). It follows the same
/// stream the banner does now, so a new one arrives within seconds.
///
/// Still one per opening ([promoTurnTakenProvider]) and never the same one
/// twice ([promosSeenProvider]).
final promoForThisLaunchProvider = Provider<AsyncValue<Promo?>>((ref) {
  if (ref.watch(promoTurnTakenProvider)) return const AsyncData(null);

  final isSeller = ref.watch(isSellerProvider);
  final linked = ref.watch(directoryLinkProvider).value?.linked ?? false;
  final seen = ref.watch(promosSeenProvider);
  final now = DateTime.now();

  return ref.watch(allPromosProvider).whenData((live) {
    for (final promo in live) {
      if (seen.contains(promo.id)) continue;
      // The stream is "switched on"; the clock decides the window.
      if (!promo.isLiveAt(now)) continue;
      if (!promo.showsTo(isSeller: isSeller, directoryLinked: linked)) continue;
      return promo;
    }
    return null;
  });
});
