import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';
import '../models/funding.dart';
import 'session.dart';

/// "Frequent but not annoying", written down as rules.
///
/// Grace's words for what the feed's chip-in nudge should feel like. The
/// only way to hold a phrase like that to account is to make it arithmetic
/// somebody can read and argue with, so all of it is here, pure, and all of
/// it is tested. Nothing about where the nudge goes is decided in a widget.

/// Everything the decision depends on. Passed in whole so the function has
/// no clock, no storage and no providers of its own to reach for.
class NudgeContext {
  const NudgeContext({
    required this.now,
    required this.itemCount,
    this.isGuest = false,
    this.shownThisSession = false,
    this.hasHero = false,
    this.dismissedAt,
    this.dismissals = const [],
    this.chippedInAt,
  });

  final DateTime now;

  /// How many items the feed has assembled. A slot past the end is no slot.
  final int itemCount;

  /// Guests never see it: they cannot check out, so it would be an ask with
  /// no way to say yes.
  final bool isGuest;

  /// One per app foreground. Held in memory, never written down: "this
  /// session" is a session, not a day.
  final bool shownThisSession;

  /// An announcement is already at the top of this feed. The hero wins;
  /// two asks on one screen is the thing being avoided.
  final bool hasHero;

  /// When ✕ was last pressed.
  final DateTime? dismissedAt;

  /// Every dismissal we still care about, newest last.
  final List<DateTime> dismissals;

  /// When this person last gave.
  final DateTime? chippedInAt;
}

/// Earliest and latest position. Never the first screen: an ask before
/// anything has been given is a leaflet through the door.
const int kNudgeFirstSlot = 7;
const int kNudgeLastSlot = 10;

/// How long ✕ buys.
const Duration kNudgeDismissRest = Duration(days: 7);

/// How long a gift buys. Longer than a dismissal on purpose: being asked
/// again a week after giving is the rudest version of this.
const Duration kNudgeGiftRest = Duration(days: 30);

/// Three ✕ in this long means stop asking for a good while.
const Duration kNudgeDismissWindow = Duration(days: 90);
const int kNudgeDismissLimit = 3;
const Duration kNudgeLongRest = Duration(days: 90);

/// Where the nudge goes in the feed, or null when it does not go anywhere.
///
/// Returns an index into the assembled list. Null is the common answer and
/// the important one: most feeds, most of the time, should not carry an ask.
int? donationNudgeSlot(NudgeContext ctx) {
  if (ctx.isGuest) return null;
  if (ctx.shownThisSession) return null;
  if (ctx.hasHero) return null;

  // Gave recently: thanked, not asked. The You-tab row says the thank-you
  // instead, which is where somebody who has just given will look.
  final gift = ctx.chippedInAt;
  if (gift != null && ctx.now.difference(gift) < kNudgeGiftRest) return null;

  // Said no recently.
  final dismissed = ctx.dismissedAt;
  if (dismissed != null && ctx.now.difference(dismissed) < kNudgeDismissRest) {
    return null;
  }

  // Said no three times in a season: that is an answer, and asking again
  // soon would be pretending it was not.
  final recent = ctx.dismissals
      .where((at) => ctx.now.difference(at) < kNudgeDismissWindow)
      .length;
  if (recent >= kNudgeDismissLimit) {
    final last = ctx.dismissals.isEmpty ? null : ctx.dismissals.last;
    if (last != null && ctx.now.difference(last) < kNudgeLongRest) return null;
  }

  // Not on the first screen, and not past the end of a short feed.
  if (ctx.itemCount <= kNudgeFirstSlot) return null;
  final span = kNudgeLastSlot - kNudgeFirstSlot + 1;
  // The day decides where in the window it lands, so it is not always in the
  // same place, and it is the same place all day rather than jumping about
  // as the feed refreshes under somebody's thumb.
  final offset = _dayOfYear(ctx.now) % span;
  final slot = kNudgeFirstSlot + offset;
  return slot < ctx.itemCount ? slot : ctx.itemCount;
}

/// The four lines, rotating by day so it is not the same sentence every
/// time, and never a number that was not read from `funding/{month}`.
List<String> donationNudgeCopy(int? donorsThisMonth) {
  final n = donorsThisMonth;
  if (n == null || n <= 0) {
    return const [
      'Little Blue Market is member-run. No ads, no investors.',
      'This app is paid for by the people using it.',
      'No ads here, and none coming. Members keep it that way.',
      'Member-run, and the bill is published every month.',
    ];
  }
  return [
    '$n people chipped in this month.',
    '$n members are keeping this ad-free.',
    'Paid for by $n people this month, not by ads.',
    '$n chipped in. The bill is published every month.',
  ];
}

/// Which of the four lines today gets. Pure.
String donationNudgeLine(DateTime now, int? donorsThisMonth) {
  final lines = donationNudgeCopy(donorsThisMonth);
  return lines[_dayOfYear(now) % lines.length];
}

int _dayOfYear(DateTime when) =>
    when.difference(DateTime(when.year)).inDays;

/// This month's funding document, for the live number in the nudge and the
/// thank-you on the You tab.
final fundingThisMonthProvider = FutureProvider<Funding?>((ref) {
  return ref
      .watch(fundingRepositoryProvider)
      .month(Funding.monthOf(DateTime.now()));
});

/// Last month's, which is the bill the Chip in page publishes.
final fundingLastMonthProvider = FutureProvider<Funding?>((ref) {
  final month = Funding.previousMonthOf(Funding.monthOf(DateTime.now()));
  return ref.watch(fundingRepositoryProvider).month(month);
});

/// Whether this person has given inside the current calendar month.
final chippedInThisMonthProvider = Provider<bool>((ref) {
  final at = ref.watch(meProvider)?.chippedInAt;
  if (at == null) return false;
  return Funding.monthOf(at) == Funding.monthOf(DateTime.now());
});
