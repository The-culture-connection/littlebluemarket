import 'package:flutter_test/flutter_test.dart';
import 'package:little_blue_market/models/funding.dart';
import 'package:little_blue_market/state/donation_nudge.dart';

/// "Frequent but not annoying" (Grace), as arithmetic rather than vibes.
///
/// Every rule here is one somebody can disagree with by reading it, which is
/// the point of writing them down. An ask in a feed is the easiest thing in
/// an app to get wrong, and the failure is invisible to whoever built it:
/// it does not crash, it just slowly makes people stop opening the app.
void main() {
  final now = DateTime(2026, 9, 29, 10);

  NudgeContext ctx({
    int itemCount = 40,
    bool isGuest = false,
    bool shownThisSession = false,
    bool hasHero = false,
    DateTime? dismissedAt,
    List<DateTime> dismissals = const [],
    DateTime? chippedInAt,
  }) => NudgeContext(
    now: now,
    itemCount: itemCount,
    isGuest: isGuest,
    shownThisSession: shownThisSession,
    hasHero: hasHero,
    dismissedAt: dismissedAt,
    dismissals: dismissals,
    chippedInAt: chippedInAt,
  );

  group('where it goes', () {
    test('never on the first screen, and inside the window', () {
      final slot = donationNudgeSlot(ctx());
      expect(slot, isNotNull);
      expect(slot, greaterThanOrEqualTo(kNudgeFirstSlot));
      expect(slot, lessThanOrEqualTo(kNudgeLastSlot));
    });

    test('the same place all day, a different place tomorrow', () {
      // It must not jump about as the feed refreshes under somebody's
      // thumb, and it must not be in the same spot for ever either.
      final morning = donationNudgeSlot(ctx());
      final evening = donationNudgeSlot(
        NudgeContext(now: DateTime(2026, 9, 29, 22), itemCount: 40),
      );
      expect(morning, evening);

      final slots = {
        for (var day = 0; day < 8; day++)
          donationNudgeSlot(
            NudgeContext(
              now: DateTime(2026, 9, 29).add(Duration(days: day)),
              itemCount: 40,
            ),
          ),
      };
      expect(slots.length, greaterThan(1), reason: 'always the same position');
    });

    test('a feed too short to have a middle gets nothing', () {
      expect(donationNudgeSlot(ctx(itemCount: kNudgeFirstSlot)), isNull);
      expect(donationNudgeSlot(ctx(itemCount: 0)), isNull);
    });
  });

  group('when it stays away', () {
    test('a guest is never asked', () {
      // They cannot check out, so it would be an ask with no way to say yes.
      expect(donationNudgeSlot(ctx(isGuest: true)), isNull);
    });

    test('once per session, not once per scroll', () {
      expect(donationNudgeSlot(ctx(shownThisSession: true)), isNull);
    });

    test('an announcement wins the screen', () {
      expect(donationNudgeSlot(ctx(hasHero: true)), isNull);
    });

    test('someone who just gave is thanked, not asked again', () {
      expect(
        donationNudgeSlot(
          ctx(chippedInAt: now.subtract(const Duration(days: 3))),
        ),
        isNull,
      );
      expect(
        donationNudgeSlot(
          ctx(chippedInAt: now.subtract(const Duration(days: 29))),
        ),
        isNull,
      );
      // A month later it is a fair question again.
      expect(
        donationNudgeSlot(
          ctx(chippedInAt: now.subtract(const Duration(days: 31))),
        ),
        isNotNull,
      );
    });

    test('a dismissal buys a week', () {
      expect(
        donationNudgeSlot(
          ctx(dismissedAt: now.subtract(const Duration(days: 2))),
        ),
        isNull,
      );
      expect(
        donationNudgeSlot(
          ctx(dismissedAt: now.subtract(const Duration(days: 8))),
        ),
        isNotNull,
      );
    });

    test('three dismissals in a season is an answer, and is heard', () {
      final three = [
        now.subtract(const Duration(days: 60)),
        now.subtract(const Duration(days: 40)),
        now.subtract(const Duration(days: 20)),
      ];
      expect(donationNudgeSlot(ctx(dismissals: three)), isNull);

      // Two is not three.
      expect(
        donationNudgeSlot(ctx(dismissals: three.take(2).toList())),
        isNotNull,
      );

      // And three long ago has expired: the window is ninety days, not for
      // ever, or one bad week would silence it permanently.
      final old = [
        now.subtract(const Duration(days: 400)),
        now.subtract(const Duration(days: 380)),
        now.subtract(const Duration(days: 360)),
      ];
      expect(donationNudgeSlot(ctx(dismissals: old)), isNotNull);
    });
  });

  group('what it says', () {
    test('the number is read, never invented', () {
      // The phase brief is blunt about this, and it applies to the nudge as
      // much as to the transparency tiles: with no funding document there is
      // no number, and the line has to work without one.
      final withData = donationNudgeLine(now, 212);
      expect(withData, contains('212'));

      for (final line in donationNudgeCopy(null)) {
        expect(RegExp(r'\d').hasMatch(line), isFalse, reason: line);
      }
      expect(donationNudgeCopy(0), donationNudgeCopy(null));
    });

    test('four lines, rotating by day', () {
      expect(donationNudgeCopy(212), hasLength(4));
      final seen = {
        for (var day = 0; day < 4; day++)
          donationNudgeLine(
            DateTime(2026, 9, 29).add(Duration(days: day)),
            212,
          ),
      };
      expect(seen, hasLength(4), reason: 'the same line every day');
    });
  });

  group('the month a gift lands in', () {
    test('is the one the webhook would write, including January', () {
      // The app and `orders.ts` both key `funding/{yyyy-mm}`, so the format
      // is decided once or the thank-you looks at the wrong month.
      expect(Funding.monthOf(DateTime(2026, 9, 29)), '2026-09');
      expect(Funding.monthOf(DateTime(2026, 12, 31)), '2026-12');
      expect(Funding.previousMonthOf('2026-09'), '2026-08');
      expect(Funding.previousMonthOf('2026-01'), '2025-12');
    });

    test('a bill with no budget does not draw a full bar', () {
      const none = Funding(month: '2026-08');
      expect(none.hasBill, isFalse);
      expect(none.hasTarget, isFalse);
      expect(none.progress, 0);

      const some = Funding(
        month: '2026-08',
        raisedCents: 41800,
        budgetCents: 62000,
        costs: {'Hosting & push': 28400},
      );
      expect(some.hasBill, isTrue);
      expect(some.progress, closeTo(0.674, 0.01));

      // Over target is a full bar, not an overflowing one.
      const over = Funding(
        month: '2026-08',
        raisedCents: 99000,
        budgetCents: 62000,
      );
      expect(over.progress, 1.0);
    });
  });
}
