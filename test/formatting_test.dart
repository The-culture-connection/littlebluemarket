import 'package:flutter_test/flutter_test.dart';
import 'package:little_blue_market/models/models.dart';

/// Every display string in the app comes out of `Fmt`, so these are the tests
/// that stop a backend change from quietly reformatting the whole UI.
void main() {
  group('money', () {
    test('keeps whole dollars whole', () {
      expect(Fmt.money(800), r'$8');
      expect(Fmt.money(45000), r'$450');
    });

    test('pads the cents', () {
      expect(Fmt.money(1360), r'$13.60');
      expect(Fmt.money(805), r'$8.05');
    });

    test('groups thousands', () {
      expect(Fmt.money(482000), r'$4,820');
      expect(Fmt.money(1140500), r'$11,405');
    });

    test('puts the sign outside the symbol', () {
      expect(Fmt.money(-420), r'-$4.20');
    });

    test('handles zero', () {
      expect(Fmt.money(0), r'$0');
    });
  });

  group('count', () {
    test('groups in threes', () {
      expect(Fmt.count(2412), '2,412');
      expect(Fmt.count(984), '984');
      expect(Fmt.count(1000000), '1,000,000');
    });

    test('does not group a bare hundred', () {
      expect(Fmt.count(100), '100');
    });
  });

  group('relative', () {
    final now = DateTime(2026, 6, 15, 12);

    test('collapses the first minute to "now"', () {
      expect(
        Fmt.relative(now.subtract(const Duration(seconds: 30)), now: now),
        'now',
      );
    });

    test('steps through the units', () {
      expect(
        Fmt.relative(now.subtract(const Duration(minutes: 4)), now: now),
        '4m',
      );
      expect(
        Fmt.relative(now.subtract(const Duration(hours: 6)), now: now),
        '6h',
      );
      expect(
        Fmt.relative(now.subtract(const Duration(days: 3)), now: now),
        '3d',
      );
      expect(
        Fmt.relative(now.subtract(const Duration(days: 14)), now: now),
        '2w',
      );
      expect(
        Fmt.relative(now.subtract(const Duration(days: 60)), now: now),
        '2mo',
      );
      expect(
        Fmt.relative(now.subtract(const Duration(days: 400)), now: now),
        '1y',
      );
    });

    test('does not report 7 days as a week boundary artefact', () {
      expect(
        Fmt.relative(now.subtract(const Duration(days: 7)), now: now),
        '1w',
      );
      expect(
        Fmt.relative(now.subtract(const Duration(days: 6)), now: now),
        '6d',
      );
    });
  });

  group('inboxAge', () {
    // Mid-afternoon on a Monday, so "yesterday" and the weekday branch are
    // both reachable without a date-line edge case.
    final now = DateTime(2026, 6, 15, 15);

    test('uses durations inside a day', () {
      expect(
        Fmt.inboxAge(now.subtract(const Duration(minutes: 2)), now: now),
        '2m',
      );
      expect(
        Fmt.inboxAge(now.subtract(const Duration(hours: 1)), now: now),
        '1h',
      );
    });

    test('names yesterday', () {
      expect(
        Fmt.inboxAge(now.subtract(const Duration(days: 1)), now: now),
        'Yesterday',
      );
    });

    test('names the weekday inside a week', () {
      // Four days before Monday 15 June 2026 is Thursday.
      expect(
        Fmt.inboxAge(now.subtract(const Duration(days: 4)), now: now),
        'Thu',
      );
    });

    test('falls back to a date past a week', () {
      expect(Fmt.inboxAge(DateTime(2026, 3, 14, 9), now: now), '14 Mar');
    });
  });

  group('distanceMiles', () {
    test('keeps one decimal under ten miles', () {
      expect(Fmt.distanceMiles(2.44), '2.4 mi');
      expect(Fmt.distanceMiles(0.5), '0.5 mi');
    });

    test('drops a trailing zero', () {
      expect(Fmt.distanceMiles(4.0), '4 mi');
    });

    test('rounds to whole miles past ten', () {
      expect(Fmt.distanceMiles(23.6), '24 mi');
    });
  });

  group('model labels', () {
    test(
      'a variant reports low stock as "left" and high stock as "in stock"',
      () {
        expect(
          const Variant('a', 800, quantityAvailable: 3).stockLabel,
          '3 left',
        );
        expect(
          const Variant('a', 800, quantityAvailable: 6).stockLabel,
          '6 left',
        );
        expect(
          const Variant('a', 800, quantityAvailable: 9).stockLabel,
          '9 in stock',
        );
      },
    );

    test('an unknown quantity is just "In stock"', () {
      expect(const Variant('a', 800).stockLabel, 'In stock');
    });

    test('a note wins over any count', () {
      expect(
        const Variant(
          'a',
          45000,
          availabilityNote: 'Sept 18, 24 open',
        ).stockLabel,
        'Sept 18, 24 open',
      );
    });

    test('sold out is reported even with stock unknown', () {
      expect(
        const Variant('a', 800, availableForSale: false).stockLabel,
        'Sold out',
      );
    });

    test('a product without a viewer location omits the distance', () {
      const p = Product(
        id: 'p',
        title: 't',
        priceCents: 800,
        sellerId: 's',
        tags: [],
        rating: 5,
        ratingCount: 1,
        type: 'x',
        description: 'd',
        cityState: 'Detroit, MI',
        saveCount: 0,
        commentCount: 0,
      );
      expect(p.locationLabel(), 'Detroit, MI');
      expect(p.locationLabel(distanceMiles: 4), 'Detroit, MI · 4 mi');
    });

    test('free shipping replaces the distance when there is no viewer', () {
      const p = Product(
        id: 'p',
        title: 't',
        priceCents: 800,
        sellerId: 's',
        tags: [],
        rating: 5,
        ratingCount: 1,
        type: 'x',
        description: 'd',
        cityState: 'Nashville, TN',
        freeShipping: true,
        saveCount: 0,
        commentCount: 0,
      );
      expect(p.locationLabel(), 'Nashville, TN · ships free');
    });

    test('an empty rating summary reports zero rather than a floor of one', () {
      const empty = RatingSummary(
        average: 0,
        bars: [
          (stars: 5, count: 0),
          (stars: 4, count: 0),
          (stars: 3, count: 0),
          (stars: 2, count: 0),
          (stars: 1, count: 0),
        ],
      );
      expect(empty.total, 0);
      expect(empty.isEmpty, isTrue);
    });

    test('the shipment step is derived from its state', () {
      expect(ShipmentState.labelCreated.step, 1);
      expect(ShipmentState.delivered.step, 4);
      expect(ShipmentState.delivered.isDelivered, isTrue);
    });
  });
}
