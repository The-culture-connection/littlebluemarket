#!/usr/bin/env node
//
// Prints the Firestore document that turns a claim code into a seller grant,
// so it can be pasted into the Firebase console without any admin credential
// on the laptop (CLAUDE.md forbids service-account keys).
//
//   npm run claim-code -- LBM-TEST-0001 --vendor "Snowboard Vendor" --email grace-s+seller1@example.com
//   npm run claim-code -- --generate --vendor "Snowboard Vendor"
//
// The code itself is never stored: the document id is its SHA-256, exactly as
// `sellers.ts` hashes it on redemption (trimmed, uppercased).

import * as crypto from 'node:crypto';

import { arg, hasFlag } from './lib/shopify-admin.mjs';

function hashClaimCode(code) {
  return crypto.createHash('sha256').update(code.trim().toUpperCase(), 'utf8').digest('hex');
}

function generate() {
  const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  const part = () =>
    Array.from(crypto.randomBytes(4), (b) => alphabet[b % alphabet.length]).join('');
  return `LBM-${part()}-${part()}`;
}

const positional = process.argv.slice(2).filter((a, i, all) => !a.startsWith('--') && !(all[i - 1] ?? '').startsWith('--'));
const code = hasFlag('generate') ? generate() : positional[0];
const vendor = arg('vendor');
const email = arg('email', '');
const vendorId = arg('vendor-id', '');
const days = Number(arg('days', '30'));

if (!code || !vendor) {
  console.error('Usage: npm run claim-code -- <CODE> --vendor "Exact Shopify vendor string" [--email who@] [--vendor-id 123] [--days 30]');
  console.error('       npm run claim-code -- --generate --vendor "..."');
  process.exit(1);
}

const expires = new Date(Date.now() + days * 86400000);
const id = hashClaimCode(code);

console.log(`
Claim code:  ${code}      (give this to the seller; it is not stored anywhere)
Vendor:      ${vendor}
Bound email: ${email || '(any verified email)'}
Expires:     ${expires.toISOString()}

Create this document in the Firebase console
  https://console.firebase.google.com/project/little-blue-610e5/firestore/data/~2FvendorClaims

  Collection:   vendorClaims
  Document ID:  ${id}
  Fields:
    vendorName  (string)     ${vendor}${email ? `\n    email       (string)     ${email}` : ''}${vendorId ? `\n    vendorId    (string)     ${vendorId}` : ''}
    expiresAt   (timestamp)  ${expires.toISOString()}

Then, in the app: Edit profile -> Start selling -> type the code -> Claim my shop.
`);
