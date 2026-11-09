// The company sweep: finding Shipturtle vendors that have no products yet.
//
// The pure rule runs everywhere. The sweep itself needs Firestore, so that
// half is skipped unless FIRESTORE_EMULATOR_HOST is set (it runs in
// `npm run test:rules`).
//
// The regression (2026-11-09): luckyducklady@gmail.com was approved in
// Shipturtle and could log in there, but "Connect my Market account" said
// she was not on the vendor list, because every roster the app could read
// was built from vendor names already on products.
import { strict as assert } from 'node:assert';
import { before, test } from 'node:test';

import { companyVerdict } from '../src/vendor_directory.ts';

const MARKET = '1066319';

test('companyVerdict: an Active vendor of ours is an entry, even with no products', () => {
  const v = companyVerdict('1098001', {
    parent_id: 1066319,
    status: 'Active',
    brand_name: 'Lucky Duck Lady',
    email: 'LuckyDuckLady@gmail.com',
  }, MARKET);
  assert.equal(v.kind, 'vendor');
  if (v.kind !== 'vendor') return;
  assert.deepEqual(v.entry, {
    vendorKey: 'lucky-duck-lady',
    vendorName: 'Lucky Duck Lady',
    companyId: '1098001',
    brandName: 'Lucky Duck Lady',
    emails: ['luckyducklady@gmail.com'],
  });
});

test('companyVerdict: not yet approved is pending; another marketplace is not ours', () => {
  assert.equal(companyVerdict('1', { parent_id: MARKET, status: 'Pending', brand_name: 'A', email: 'a@x.com' }, MARKET).kind, 'pending');
  assert.equal(companyVerdict('1', { parent_id: MARKET, status: 'Inactive', brand_name: 'A', email: 'a@x.com' }, MARKET).kind, 'pending');
  assert.equal(companyVerdict('1', { parent_id: MARKET, status: 'Active', brand_name: '', email: 'a@x.com' }, MARKET).kind, 'pending');
  assert.equal(companyVerdict('1', { parent_id: 839444, status: 'Active', brand_name: 'Remi & Reid', email: 'r@x.com' }, MARKET).kind, 'other');
  // The marketplace's own company is its own parent, and is not a vendor.
  assert.equal(companyVerdict(MARKET, { parent_id: MARKET, status: 'Active', brand_name: 'Little Blue Market', email: 'kate@lbc.com' }, MARKET).kind, 'other');
  assert.equal(companyVerdict('1', { parent_id: MARKET, status: 'Active', brand_name: 'A', email: 'a@x.com' }, '').kind, 'other');
});

// ------------------------------------------------------------ the emulator

const emulated = !!process.env.FIRESTORE_EMULATOR_HOST;

before(async () => {
  if (!emulated) return;
  process.env.GCLOUD_PROJECT ??= 'demo-lbm';
  process.env.SHIPTURTLE_API_KEY = 'test-key';
  process.env.SHIPTURTLE_MARKETPLACE_ID = '1000';
  const { initializeApp, getApps } = await import('firebase-admin/app');
  if (!getApps().length) initializeApp({ projectId: process.env.GCLOUD_PROJECT });
});

/** A Shipturtle with companies 1000..top, holes where told, and a call log. */
function fakeShipturtle(companies: Map<number, Record<string, unknown>>) {
  const asked: number[] = [];
  const fetchImpl = (async (url: string | URL) => {
    const m = String(url).match(/\/api\/v1\/companies\/(\d+)$/);
    if (!m) return new Response('nope', { status: 404 });
    const id = Number(m[1]);
    asked.push(id);
    const c = companies.get(id);
    if (!c) return new Response(JSON.stringify({ message: 'No query results' }), { status: 404 });
    return new Response(JSON.stringify({ data: c }), { status: 200 });
  }) as typeof fetch;
  return { fetchImpl, asked };
}

function world(top: number) {
  const companies = new Map<number, Record<string, unknown>>();
  for (let id = 1000; id <= top; id++) {
    if (id >= 1010 && id <= 1012) continue; // deleted companies
    companies.set(id, { parent_id: id === 1000 ? 1000 : 777, status: 'Active', brand_name: `Other ${id}`, email: `o${id}@x.com` });
  }
  return companies;
}

test('discoverNewCompanies: finds an approved vendor with no products, and notices a later approval', { skip: !emulated }, async () => {
  const { getFirestore } = await import('firebase-admin/firestore');
  const { discoverNewCompanies, directoryRoster, DIRECTORY } = await import('../src/vendor_directory.ts');
  const db = getFirestore();
  await db.recursiveDelete(db.doc('_internal/vendorDirectory'));

  const companies = world(1040);
  companies.set(1030, { parent_id: 1000, status: 'Active', brand_name: 'Lucky Duck Lady', email: 'luckyducklady@gmail.com' });
  companies.set(1035, { parent_id: 1000, status: 'Pending', brand_name: 'Slow Poke', email: 'slow@x.com' });
  const st = fakeShipturtle(companies);

  const first = await discoverNewCompanies({ budgetMs: 60_000, fetchImpl: st.fetchImpl });
  assert.deepEqual(first.added, ['Lucky Duck Lady']);
  assert.equal(first.pending, 1);
  assert.equal(first.caughtUp, true);

  const roster = await directoryRoster();
  assert.deepEqual(
    roster.filter((r) => r.email === 'luckyducklady@gmail.com'),
    [{ companyId: '1030', email: 'luckyducklady@gmail.com', name: 'Lucky Duck Lady' }],
    'the seller tap and the admin card match against this roster',
  );
  assert.equal(roster.some((r) => r.email === 'slow@x.com'), false, 'not approved yet, not on the roster');
  assert.equal(roster.some((r) => r.email.startsWith('o10')), false, "another marketplace's vendors are never stored");

  // Approved later, and two new companies arrive, one of them ours.
  companies.set(1035, { ...companies.get(1035), status: 'Active' });
  companies.set(1041, { parent_id: 777, status: 'Active', brand_name: 'Other', email: 'x@x.com' });
  companies.set(1042, { parent_id: 1000, status: 'Active', brand_name: 'New Today', email: 'new@x.com' });
  st.asked.length = 0;
  const second = await discoverNewCompanies({ budgetMs: 60_000, fetchImpl: st.fetchImpl });
  assert.deepEqual(second.added.sort(), ['New Today', 'Slow Poke']);
  assert.equal(second.pending, 0);
  assert.equal(st.asked.filter((id) => id < 1030).length, 0, 'a finished range is never walked again');

  const third = await discoverNewCompanies({ budgetMs: 60_000, fetchImpl: st.fetchImpl });
  assert.deepEqual(third.added, [], 'nothing is re-added');

  // A brand name another company already holds is left alone.
  await db.collection(DIRECTORY).doc('clash').set({ vendorName: 'Clash', companyId: '9', emails: ['first@x.com'] });
  companies.set(1043, { parent_id: 1000, status: 'Active', brand_name: 'Clash', email: 'second@x.com' });
  const fourth = await discoverNewCompanies({ budgetMs: 60_000, fetchImpl: st.fetchImpl });
  assert.deepEqual(fourth.added, []);
  const held = await db.collection(DIRECTORY).doc('clash').get();
  assert.equal(held.data()?.companyId, '9');
});

test('discoverNewCompanies: newest first, and resumes where a short budget stopped', { skip: !emulated }, async () => {
  const { getFirestore } = await import('firebase-admin/firestore');
  const { discoverNewCompanies } = await import('../src/vendor_directory.ts');
  const db = getFirestore();
  await db.recursiveDelete(db.doc('_internal/vendorDirectory'));

  const companies = world(1400);
  companies.set(1399, { parent_id: 1000, status: 'Active', brand_name: 'Newest', email: 'newest@x.com' });
  companies.set(1001, { parent_id: 1000, status: 'Active', brand_name: 'Oldest', email: 'oldest@x.com' });
  // Each answer takes a moment, so a short budget cannot finish 400 ids.
  const slow = fakeShipturtle(companies);
  const delayed = (async (url: string | URL) => {
    await new Promise((r) => setTimeout(r, 60));
    return slow.fetchImpl(url);
  }) as typeof fetch;

  const first = await discoverNewCompanies({ budgetMs: 11_000, fetchImpl: delayed, concurrency: 2 });
  assert.ok(first.added.includes('Newest'), 'the newest vendor is found on the first, short run');
  assert.equal(first.caughtUp, false);
  assert.ok((first.left ?? 0) > 0);

  let rest = first;
  for (let i = 0; i < 20 && !rest.caughtUp; i++) {
    rest = await discoverNewCompanies({ budgetMs: 60_000, fetchImpl: slow.fetchImpl });
  }
  assert.equal(rest.caughtUp, true);
  const state = (await db.doc('_internal/vendorDirectory').get()).data();
  assert.deepEqual(state?.companyRanges, []);
  const oldest = await db.collection('_internal/vendorDirectory/vendors').doc('oldest').get();
  assert.equal(oldest.data()?.companyId, '1001', 'the oldest vendor is reached in the end');
});

test('discoverNewCompanies: jumps a long hole in the ids, as on the real account', { skip: !emulated }, async () => {
  const { getFirestore } = await import('firebase-admin/firestore');
  const { discoverNewCompanies, directoryRoster } = await import('../src/vendor_directory.ts');
  const db = getFirestore();
  await db.recursiveDelete(db.doc('_internal/vendorDirectory'));

  // Dense to 1100, nothing from 1101 to 5000 (real: ~1098466 to ~1105700),
  // dense again to 5100, and the new vendor near the very top.
  const companies = world(1100);
  for (let id = 5001; id <= 5100; id++) companies.set(id, { parent_id: 777, status: 'Active', brand_name: `Other ${id}`, email: `o${id}@x.com` });
  companies.set(5090, { parent_id: 1000, status: 'Active', brand_name: 'Lucky Duck Farm', email: 'Luckyducklady@gmail.com' });
  const st = fakeShipturtle(companies);

  const run = await discoverNewCompanies({ budgetMs: 60_000, fetchImpl: st.fetchImpl });
  assert.ok(run.added.includes('Lucky Duck Farm'), `found across the hole; added ${JSON.stringify(run.added)}`);
  const state = (await db.doc('_internal/vendorDirectory').get()).data();
  assert.equal(state?.companyHighest, 5100, 'the newest id, exactly');
  const roster = await directoryRoster();
  assert.ok(roster.some((r) => r.email === 'luckyducklady@gmail.com' && r.companyId === '5090'));
});
