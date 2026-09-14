import { strict as assert } from 'node:assert';
import { test } from 'node:test';

import {
  PROMO_CAPTION_MAX,
  PROMO_CTA_LABEL_MAX,
  PROMO_PHOTOS_MAX,
  PROMO_TITLE_MAX,
  cleanUrl,
  isPromoEvent,
  isPromoKind,
  validatePromo,
} from '../src/promos.ts';

const good = {
  kind: 'ad' as const,
  title: 'Holiday market, December 14',
  caption: 'Forty makers, one room, all day.',
  audience: 'all' as const,
};

test('a plain advert passes and comes back trimmed', () => {
  const clean = validatePromo({ ...good, title: '  Holiday market  ', caption: ' Forty makers. ' });
  assert.equal(clean.title, 'Holiday market');
  assert.equal(clean.caption, 'Forty makers.');
  assert.equal(clean.kind, 'ad');
  assert.equal(clean.audience, 'all');
  assert.deepEqual(clean.imageUrls, []);
  assert.equal(clean.ctaLabel, '');
  assert.equal(clean.ctaUrl, '');
  assert.equal(clean.startsAt, null);
  assert.equal(clean.endsAt, null);
});

test('the kind and the audience are both from the fixed lists', () => {
  assert.equal(isPromoKind('ad'), true);
  assert.equal(isPromoKind('announcement'), true);
  assert.equal(isPromoKind('advert'), false);
  assert.equal(isPromoKind(undefined), false);
  assert.throws(() => validatePromo({ ...good, kind: 'advert' as never }), /advert or an announcement/);
  assert.throws(() => validatePromo({ ...good, audience: 'everyone' as never }), /who this goes to/);
});

test('words are required and capped', () => {
  assert.throws(() => validatePromo({ ...good, title: '   ' }), /Give it a title/);
  assert.throws(() => validatePromo({ ...good, caption: '' }), /Write a caption/);
  assert.throws(() => validatePromo({ ...good, title: 'x'.repeat(PROMO_TITLE_MAX + 1) }), /under 60/);
  assert.throws(() => validatePromo({ ...good, caption: 'x'.repeat(PROMO_CAPTION_MAX + 1) }), /under 180/);
  // Exactly at the cap is fine; off-by-one here would reject a legal advert.
  assert.equal(validatePromo({ ...good, title: 'x'.repeat(PROMO_TITLE_MAX) }).title.length, PROMO_TITLE_MAX);
});

test('a link with no scheme is assumed to be https', () => {
  assert.equal(cleanUrl('littlebluecart.com', 'x'), 'https://littlebluecart.com/');
  assert.equal(cleanUrl('  https://littlebluecart.com/sale  ', 'x'), 'https://littlebluecart.com/sale');
  assert.equal(cleanUrl('', 'x'), '');
  assert.equal(cleanUrl(undefined, 'x'), '');
});

test('only https reaches a phone', () => {
  // The popup's button opens whatever this says in an external browser, so
  // these are holes in the app, not typos in a form.
  assert.throws(() => cleanUrl('javascript:alert(1)', 'The button link'), /has to start with https/);
  assert.throws(() => cleanUrl('http://littlebluecart.com', 'The button link'), /has to start with https/);
  assert.throws(() => cleanUrl('intent://evil#Intent;end', 'The button link'), /has to start with https/);
  assert.throws(() => cleanUrl('file:///etc/passwd', 'The button link'), /has to start with https/);
  assert.throws(() => cleanUrl('https://', 'The button link'), /not a web address|has no website/);
});

test('a button needs both its wording and its link', () => {
  assert.throws(() => validatePromo({ ...good, ctaLabel: 'Shop the sale' }), /both its wording and its link/);
  assert.throws(() => validatePromo({ ...good, ctaUrl: 'littlebluecart.com' }), /both its wording and its link/);
  const clean = validatePromo({ ...good, ctaLabel: 'Shop the sale', ctaUrl: 'littlebluecart.com' });
  assert.equal(clean.ctaLabel, 'Shop the sale');
  assert.equal(clean.ctaUrl, 'https://littlebluecart.com/');
});

test("the button's wording is capped too", () => {
  assert.throws(
    () => validatePromo({ ...good, ctaLabel: 'x'.repeat(PROMO_CTA_LABEL_MAX + 1), ctaUrl: 'littlebluecart.com' }),
    /under 24/,
  );
});

test('photos are capped and each one is checked', () => {
  const many = Array.from({ length: PROMO_PHOTOS_MAX + 1 }, () => 'https://x.test/a.jpg');
  assert.throws(() => validatePromo({ ...good, imageUrls: many }), /At most 4 photos/);
  assert.throws(() => validatePromo({ ...good, imageUrls: ['http://x.test/a.jpg'] }), /Photo 1 has to start with https/);
  const clean = validatePromo({ ...good, imageUrls: ['https://x.test/a.jpg', 'x.test/b.jpg'] });
  assert.deepEqual(clean.imageUrls, ['https://x.test/a.jpg', 'https://x.test/b.jpg']);
  // Anything that is not a list at all is simply no photos.
  assert.deepEqual(validatePromo({ ...good, imageUrls: 'nope' }).imageUrls, []);
});

test('a window has to run forwards', () => {
  const clean = validatePromo({ ...good, startsAt: '2026-12-01T00:00:00Z', endsAt: '2026-12-15T00:00:00Z' });
  assert.ok(clean.startsAt && clean.endsAt);
  assert.ok(clean.endsAt.toMillis() > clean.startsAt.toMillis());
  assert.throws(
    () => validatePromo({ ...good, startsAt: '2026-12-15T00:00:00Z', endsAt: '2026-12-01T00:00:00Z' }),
    /after the start date/,
  );
  assert.throws(() => validatePromo({ ...good, startsAt: 'next Tuesday' }), /not a date I can read/);
  // One-sided windows are the common case and stay legal.
  assert.equal(validatePromo({ ...good, endsAt: '2026-12-15T00:00:00Z' }).startsAt, null);
});

test("an event is 'seen' or 'tap' and nothing else", () => {
  assert.equal(isPromoEvent('seen'), true);
  assert.equal(isPromoEvent('tap'), true);
  assert.equal(isPromoEvent('impression'), false);
  assert.equal(isPromoEvent(1), false);
});
