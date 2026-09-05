#!/usr/bin/env node
//
// The security pass, as one command. Signs in as an ordinary member against
// the Firestore emulator and attempts every write the rules must refuse,
// printing PASS or FAIL per line. Tests S1–S4 from Planning/checkpoints.md;
// S5–S8 need the callables and are covered by the manual pass for now.
//
//   npm run verify:security        # wraps this in firebase emulators:exec
//
// Never run against a real project: it writes seed documents.

import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

import { initializeTestEnvironment } from '@firebase/rules-unit-testing';

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  console.error(
    'FIRESTORE_EMULATOR_HOST is not set. Run this through the emulator:\n' +
      '  npm run verify:security',
  );
  process.exit(2);
}

const RULES = join(dirname(fileURLToPath(import.meta.url)), '..', '..', 'firebase', 'firestore.rules');
const [host, port] = process.env.FIRESTORE_EMULATOR_HOST.split(':');

const env = await initializeTestEnvironment({
  projectId: 'little-blue-cart-security-pass',
  firestore: { rules: readFileSync(RULES, 'utf8'), host, port: Number(port) },
});

const me = env
  .authenticatedContext('grace', { firebase: { sign_in_provider: 'password' } })
  .firestore();

await env.withSecurityRulesDisabled(async (admin) => {
  await admin.firestore().doc('users/grace').set({
    name: 'Grace',
    revenueCents: 0,
    purchaseCount: 0,
    postCount: 0,
    isSeller: false,
  });
  await admin.firestore().doc('vendorNames/gwynstone').set({ uid: 'someone-else' });
  await admin.firestore().doc('vendorClaims/abc123').set({ vendorName: 'Gwynstone' });
});

const results = [];
async function mustFail(id, label, action) {
  try {
    await action();
    results.push({ id, ok: false, label, note: 'the write SUCCEEDED — the rules let it through' });
  } catch (error) {
    const denied = /PERMISSION_DENIED|permission-denied|Missing or insufficient permissions/i.test(`${error?.code ?? ''} ${error?.message ?? error}`);
    results.push({ id, ok: denied, label, note: denied ? 'denied' : `failed for the wrong reason: ${error?.message ?? error}` });
  }
}

await mustFail('S1', 'a member cannot set isSeller on their own user document', () =>
  me.doc('users/grace').update({ isSeller: true }));
await mustFail('S2', 'a member cannot set shopifyVendorName on their own user document', () =>
  me.doc('users/grace').update({ shopifyVendorName: 'Gwynstone' }));
await mustFail('S3a', 'a member cannot write sellers/{uid}', () =>
  me.doc('sellers/grace').set({ shopifyVendorName: 'Gwynstone' }));
await mustFail('S3b', 'a member cannot write vendorNames/', () =>
  me.doc('vendorNames/gwynstone').set({ uid: 'grace' }));
await mustFail('S3c', 'a member cannot write vendorClaims/', () =>
  me.doc('vendorClaims/anything').set({ vendorName: 'Gwynstone' }));
await mustFail('S4', 'a member cannot read vendorClaims/', () =>
  me.doc('vendorClaims/abc123').get());
await mustFail('M', 'a member cannot set their own revenue', () =>
  me.doc('users/grace').update({ revenueCents: 999999 }));
await mustFail('M2', 'a member cannot set their own purchase count', () =>
  me.doc('users/grace').update({ purchaseCount: 99 }));
await mustFail('M3', 'a member cannot write the catalog mirror', () =>
  me.doc('catalog/fake').set({ title: 'Fake', priceCents: 1 }));
await mustFail('M4', 'a member cannot write an order', () =>
  me.doc('orders/fake').set({ buyerUid: 'grace' }));

await env.cleanup();

let failed = 0;
for (const r of results) {
  if (!r.ok) failed += 1;
  console.log(`${r.ok ? 'PASS' : 'FAIL'}  ${r.id.padEnd(4)} ${r.label}${r.ok ? '' : `\n      -> ${r.note}`}`);
}
console.log(`\n${results.length - failed} PASS, ${failed} FAIL.`);
if (failed) {
  console.log('A FAIL here means a client can write something only the backend may write. Paste this block to Claude.');
  process.exit(1);
}
