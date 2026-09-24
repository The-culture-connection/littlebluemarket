import 'package:flutter_test/flutter_test.dart';
import 'package:little_blue_market/models/models.dart';

/// Where an advert's button goes.
///
/// Grace, 2026-09-24: "can we also add cta links for things within the app?
/// I would like to add it to be a search of a hashtag or a person's
/// profile." The button had one destination, a web page, so an advert about
/// a shop on this market sent people out to a browser to find something
/// three taps away.
///
/// The first character decides, and the rule is written in three places:
/// here, `cleanCtaTarget` in `functions/src/promos.ts`, and `ctaWhere` in
/// the admin website. These are the cases that keep them honest.
Promo _promo({
  required String ctaUrl,
  String ctaLabel = 'Have a look',
  Map<String, String> mentions = const {},
}) => Promo(
  id: 'p1',
  kind: PromoKind.ad,
  title: 'Market day',
  caption: 'Come along.',
  audience: AnnouncementAudience.all,
  ctaLabel: ctaLabel,
  ctaUrl: ctaUrl,
  mentions: mentions,
);

void main() {
  group('a handle opens a profile', () {
    test('by the uid stored with it, not by the handle', () {
      // An advert outlives the handle it was written with. A shop that
      // renames itself in March should still be the shop the button opens
      // in September, which is why the uid travels with the advert.
      final promo = _promo(
        ctaUrl: '@polly-politics',
        mentions: const {'polly-politics': 'uid-polly'},
      );
      expect(promo.ctaProfileUid, 'uid-polly');
      expect(promo.ctaTag, isNull);
      expect(promo.ctaUri, isNull, reason: 'not a web address');
      expect(promo.hasCta, isTrue);
    });

    test('the lookup does not care how the handle was typed', () {
      final promo = _promo(
        ctaUrl: '@Polly-Politics',
        mentions: const {'polly-politics': 'uid-polly'},
      );
      expect(promo.ctaProfileUid, 'uid-polly');
    });

    test('a handle with no uid behind it is no button at all', () {
      // Rather than a button that opens nothing. The backend refuses to
      // save one, so this is the belt to that braces: an advert written
      // before the uid was stored must not draw a dead button.
      final promo = _promo(ctaUrl: '@ghost');
      expect(promo.ctaProfileUid, isNull);
      expect(promo.hasCta, isFalse);
    });
  });

  group('a hashtag runs a search', () {
    test('kept with its hash, because that is what the search takes', () {
      final promo = _promo(ctaUrl: '#WomenOwned');
      expect(promo.ctaTag, '#WomenOwned');
      expect(promo.ctaProfileUid, isNull);
      expect(promo.ctaUri, isNull);
      expect(promo.hasCta, isTrue);
    });

    test('a bare hash is not a search', () {
      expect(_promo(ctaUrl: '#').ctaTag, isNull);
      expect(_promo(ctaUrl: '#').hasCta, isFalse);
    });
  });

  group('anything else is still the web', () {
    test('a link without a scheme still works', () {
      final promo = _promo(ctaUrl: 'littlebluecart.com/market');
      expect(promo.ctaUri.toString(), 'https://littlebluecart.com/market');
      expect(promo.ctaProfileUid, isNull);
      expect(promo.ctaTag, isNull);
    });

    test('a web address containing an @ is a web address, not a mention', () {
      // The case that made the backend resolve only in-app targets: read as
      // a mention this would name nobody and refuse a good link.
      final promo = _promo(ctaUrl: 'https://instagram.com/@romantiquebooks');
      expect(promo.ctaProfileUid, isNull);
      expect(promo.ctaUri?.host, 'instagram.com');
      expect(promo.hasCta, isTrue);
    });

    test('no words on the button means no button, wherever it points', () {
      expect(
        _promo(ctaUrl: '#WomenOwned', ctaLabel: '').hasCta,
        isFalse,
        reason: 'a link with no button is invisible',
      );
    });
  });
}
