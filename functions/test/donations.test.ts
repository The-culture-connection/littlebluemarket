import { strict as assert } from 'node:assert';
import { test } from 'node:test';

import {
  isValidRoundUpCents,
  pickAmountVariant,
  roundUpCentsFor,
} from '../src/donations.ts';

/**
 * The round-up is the one piece of this phase that touches somebody's card,
 * and the one where being a penny out is a real complaint rather than a
 * cosmetic one. All of the arithmetic is pure so it can be argued with here
 * rather than discovered on a statement.
 */

void test('rounding up reaches the next whole dollar', () => {
  assert.equal(roundUpCentsFor(6340), 60); // $63.40 -> $64.00
  assert.equal(roundUpCentsFor(1), 99);
  assert.equal(roundUpCentsFor(99), 1);
  assert.equal(roundUpCentsFor(2599), 1);
});

void test('a subtotal already on a dollar rounds up a whole one, not nothing', () => {
  // The plan is explicit: never $0. A switch that adds a zero line looks
  // broken, and "round up" on $63.00 meaning "give nothing" is not what
  // anybody turning it on expects.
  assert.equal(roundUpCentsFor(6300), 100);
  assert.equal(roundUpCentsFor(100), 100);
});

void test('nothing to round up on an empty or nonsense subtotal', () => {
  assert.equal(roundUpCentsFor(0), 0);
  assert.equal(roundUpCentsFor(-500), 0);
  assert.equal(roundUpCentsFor(Number.NaN), 0);
});

void test('only 1 to 100 is sent, because the quantity is the amount', () => {
  // The round-up product is one penny bought `cents` times, so a bad number
  // here is a bad charge rather than a bad screen.
  assert.equal(isValidRoundUpCents(60), true);
  assert.equal(isValidRoundUpCents(1), true);
  assert.equal(isValidRoundUpCents(100), true);

  assert.equal(isValidRoundUpCents(0), false);
  assert.equal(isValidRoundUpCents(101), false);
  assert.equal(isValidRoundUpCents(-1), false);
  assert.equal(isValidRoundUpCents(60.5), false);
  assert.equal(isValidRoundUpCents('60'), false);
  assert.equal(isValidRoundUpCents(undefined), false);
});

void test('every rounding is a valid amount to send', () => {
  // The two halves have to agree: whatever the cart computes must be
  // something the checkout is willing to charge.
  for (let subtotal = 1; subtotal <= 2000; subtotal++) {
    const cents = roundUpCentsFor(subtotal);
    assert.ok(isValidRoundUpCents(cents), `subtotal ${subtotal} gave ${cents}`);
    // And it really does land on a dollar.
    assert.equal((subtotal + cents) % 100, 0, `subtotal ${subtotal}`);
  }
});

void test('a chip-in amount is matched by price, not by position', () => {
  // The app asks for an amount; the variant is found by what it costs. So
  // re-ordering or re-pricing the variants in Shopify cannot silently
  // charge somebody the wrong one.
  const variants = [
    { id: 'gid://shopify/ProductVariant/1', priceCents: 200 },
    { id: 'gid://shopify/ProductVariant/2', priceCents: 500 },
    { id: 'gid://shopify/ProductVariant/3', priceCents: 1000 },
    { id: 'gid://shopify/ProductVariant/4', priceCents: 2000 },
    // The unused Monthly variant that exists on the product and must never
    // be picked by a one-time amount (addendum: ignore it).
    { id: 'gid://shopify/ProductVariant/5', priceCents: 300 },
  ];

  assert.equal(pickAmountVariant(variants, 500)?.id, 'gid://shopify/ProductVariant/2');
  assert.equal(pickAmountVariant(variants, 2000)?.id, 'gid://shopify/ProductVariant/4');
  // An amount the product does not carry is refused rather than rounded to
  // the nearest, which would charge a number nobody chose.
  assert.equal(pickAmountVariant(variants, 750), null);
  assert.equal(pickAmountVariant([], 500), null);
});
