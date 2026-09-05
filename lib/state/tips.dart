import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/repositories/dev_error_sink.dart';

/// One-time tips, remembered per phone.
///
/// "♡ is now 🛒" is the one that matters: removing the heart from a social
/// feed reads as a missing feature unless it is explained, so the explanation
/// is shown until it has been read once. Kept on the phone rather than on
/// the profile because it is about this screen, not this person.
class TipsNotifier extends Notifier<Set<String>> {
  static const _key = 'lbm.tipsSeen';

  @override
  Set<String> build() {
    // Nothing stored yet; load in the background. Under test there is no
    // plugin, and every tip counts as unseen.
    if (!kUnderFlutterTest) _load();
    return const {};
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final seen = prefs.getStringList(_key) ?? const [];
      state = {...state, ...seen};
    } catch (_) {
      // A phone with no storage still gets the tip, every time. Acceptable.
    }
  }

  bool seen(String tip) => state.contains(tip);

  Future<void> markSeen(String tip) async {
    if (state.contains(tip)) return;
    state = {...state, tip};
    if (kUnderFlutterTest) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_key, state.toList());
    } catch (_) {
      // Left unsaved; it shows again next launch.
    }
  }
}

final tipsProvider = NotifierProvider<TipsNotifier, Set<String>>(
  TipsNotifier.new,
);

/// The tip names, so a typo is a compile error rather than a tip that never
/// clears.
abstract final class Tips {
  static const cartIsTheLike = 'cartIsTheLike';
}
