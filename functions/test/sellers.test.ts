import { strict as assert } from 'node:assert';
import * as crypto from 'node:crypto';
import { test } from 'node:test';

import { hashClaimCode, normalizeVendorName } from '../src/sellers.ts';

test('a vendor name normalises to one stable id', () => {
  // The real store's vendor names are full of spaces, commas and ampersands:
  // "Jilly Bean Publishing, LLC", "Chill, Babe Candle Co", "Femme & Fawn".
  // Two spellings of one shop must not reserve two different names, or the
  // "one vendor, one owner" guarantee is worth nothing.
  assert.equal(normalizeVendorName('Gwynstone'), 'gwynstone');
  assert.equal(normalizeVendorName('  GWYNSTONE  '), 'gwynstone');
  assert.equal(normalizeVendorName('Femme & Fawn'), 'femme-fawn');
  assert.equal(
    normalizeVendorName('Jilly Bean Publishing, LLC'),
    'jilly-bean-publishing-llc',
  );
  assert.equal(normalizeVendorName('Chill, Babe Candle Co'), 'chill-babe-candle-co');
});

test('normalising never leaves a leading or trailing separator', () => {
  // A document id of "-gwynstone-" is a different shop from "gwynstone", and
  // the difference would be invisible in the console.
  for (const raw of ['& Gwynstone &', '  ...Gwynstone...  ', '!!Gwynstone']) {
    const id = normalizeVendorName(raw);
    assert.equal(id, 'gwynstone', `from ${JSON.stringify(raw)}`);
  }
});

test('a claim code is hashed, never stored as typed', () => {
  const code = 'LBM-GWYN-2026';
  const hash = hashClaimCode(code);

  assert.match(hash, /^[0-9a-f]{64}$/);
  assert.notEqual(hash, code);
  assert.equal(
    hash,
    crypto.createHash('sha256').update(code, 'utf8').digest('hex'),
  );
});

test('a code is matched however it was typed out of the email', () => {
  // People paste these. Case and stray whitespace are not a security boundary,
  // they are a support ticket.
  const canonical = hashClaimCode('LBM-GWYN-2026');
  assert.equal(hashClaimCode('lbm-gwyn-2026'), canonical);
  assert.equal(hashClaimCode('  LBM-GWYN-2026  '), canonical);
  assert.equal(hashClaimCode('Lbm-Gwyn-2026'), canonical);
});

test('different codes do not collide', () => {
  assert.notEqual(hashClaimCode('LBM-GWYN-2026'), hashClaimCode('LBM-GWYN-2027'));
});
