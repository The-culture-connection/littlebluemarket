// The six-hourly directory sync, against the Firestore emulator.
//
// Skipped unless FIRESTORE_EMULATOR_HOST is set. Run it with:
//   npx firebase emulators:exec --only firestore --project demo-lbm \
//     "node --test --experimental-strip-types test/directory_ownership_emulator.test.ts"
//
// It proves the regression Grace kept seeing (2026-09-28 to 30): an account
// an admin had released was handed directory listings again within six
// hours, because `syncAllDirectoryListings` ignored the lock.
import { strict as assert } from 'node:assert';
import { before, test } from 'node:test';

const emulated = !!process.env.FIRESTORE_EMULATOR_HOST;

before(async () => {
  if (!emulated) return;
  process.env.GCLOUD_PROJECT ??= 'demo-lbm';
  process.env.WP_BASE_URL ??= 'https://littlebluecart.example';
  const { initializeApp, getApps } = await import('firebase-admin/app');
  if (!getApps().length) initializeApp({ projectId: process.env.GCLOUD_PROJECT });
});

/** A website that says what it is told, and remembers what it was asked. */
function fakeSite(authors: Record<number, number>) {
  const asked: number[][] = [];
  return {
    asked,
    lookups: {
      user: async () => null,
      customer: async () => null,
      ordersByCustomer: async () => [],
      ordersByEmail: async () => [],
      crawlIndex: async () =>
        Object.entries(authors).map(([id, author]) => ({
          id: Number(id),
          author,
          modified: '2026-09-30T00:00:00',
          status: 'publish',
        })),
      listingsByIds: async (ids: number[]) => {
        asked.push(ids);
        return [];
      },
      termNames: async () => ({}),
      mediaUrl: async () => '',
      mediaUrls: async () => ({}),
    },
  };
}

async function reset() {
  const { getFirestore } = await import('firebase-admin/firestore');
  const db = getFirestore();
  for (const name of ['directory', 'directoryListings', 'posts', 'users', '_internal']) {
    const snap = await db.collection(name).get();
    await Promise.all(snap.docs.map((d) => d.ref.delete()));
  }
  return db;
}

test('a released account stays released through the six-hourly sync', { skip: !emulated }, async () => {
  const db = await reset();
  const { syncAllDirectoryListings } = await import('../src/directory.ts');
  await db.doc('directory/erin').set({ status: 'linked', wpUserId: 7, ownershipLocked: true });
  await db.doc('directory/biz').set({ status: 'linked', wpUserId: 42 });
  // What an earlier bad run left behind.
  await db.doc('directoryListings/100').set({ ownerUid: 'erin', title: 'Somebody else' });
  await db.doc('posts/directory_100').set({ authorId: 'erin' });

  const site = fakeSite({ 100: 7, 101: 7, 200: 42 });
  await syncAllDirectoryListings(site.lookups as never);

  // Erin's listings were never even fetched; the business's were.
  assert.deepEqual(site.asked, [[200]]);
  assert.equal((await db.doc('directoryListings/100').get()).data()?.ownerUid, '');
  assert.equal((await db.doc('posts/directory_100').get()).exists, false);
  assert.equal((await db.doc('directory/erin').get()).data()?.ownershipLocked, true);
});

test('the site account is refused and locked by id, with a short index and no role', { skip: !emulated }, async () => {
  const db = await reset();
  const { syncAllDirectoryListings } = await import('../src/directory.ts');
  // Not locked yet, and the index says only three listings: the case that
  // got past the count check every day.
  await db.doc('directory/erin').set({ status: 'linked', wpUserId: 6 });
  await db.doc('directoryListings/300').set({ ownerUid: 'erin', title: 'A real business' });

  const site = fakeSite({ 300: 6, 301: 6, 302: 6 });
  await syncAllDirectoryListings(site.lookups as never);

  assert.deepEqual(site.asked, []);
  assert.equal((await db.doc('directoryListings/300').get()).data()?.ownerUid, '');
  const link = (await db.doc('directory/erin').get()).data();
  assert.equal(link?.ownershipLocked, true);
  assert.equal(link?.ownsListings, false);
});

test('a refusal on a count is made to stick, not just logged', { skip: !emulated }, async () => {
  const db = await reset();
  const { syncAllDirectoryListings } = await import('../src/directory.ts');
  await db.doc('directory/staff').set({ status: 'linked', wpUserId: 9, wpRoles: ['editor'] });
  await db.doc('directoryListings/400').set({ ownerUid: 'staff', title: 'Not theirs' });

  const site = fakeSite({ 400: 9 });
  await syncAllDirectoryListings(site.lookups as never);

  assert.deepEqual(site.asked, []);
  assert.equal((await db.doc('directoryListings/400').get()).data()?.ownerUid, '');
  assert.equal((await db.doc('directory/staff').get()).data()?.ownershipLocked, true);
});

test('a blocked email is never handed listings, whatever website account it links to', { skip: !emulated }, async () => {
  const db = await reset();
  const { syncAllDirectoryListings } = await import('../src/directory.ts');
  await db.doc('_internal/directoryBlocklist').set({ emails: ['erin@example.com'] });
  // A fresh link, not locked, to an ordinary-looking website account.
  await db.doc('directory/erin2').set({ status: 'linked', wpUserId: 55, wpEmailLower: 'erin@example.com' });
  await db.doc('directoryListings/500').set({ ownerUid: 'erin2', title: 'Not hers' });

  const site = fakeSite({ 500: 55 });
  await syncAllDirectoryListings(site.lookups as never);

  assert.deepEqual(site.asked, []);
  assert.equal((await db.doc('directoryListings/500').get()).data()?.ownerUid, '');
});

test('the admin block reports, then blocks every identifier and cleans up', { skip: !emulated }, async () => {
  const db = await reset();
  const { blockDirectoryAccount } = await import('../src/directory_block.ts');
  await db.doc('directory/erin').set({ status: 'linked', wpUserId: 6, wpEmailLower: 'erin@example.com', wpLogin: 'lbcerin' });
  await db.doc('directoryListings/600').set({ ownerUid: 'erin', title: 'Hearth & Home' });
  await db.doc('posts/directory_600').set({ authorId: 'erin' });

  const check = await blockDirectoryAccount('erin', { apply: false });
  assert.ok(check.log.some((l) => l.includes('listings held      1')));
  assert.equal((await db.doc('directoryListings/600').get()).data()?.ownerUid, 'erin', 'a check changes nothing');

  const done = await blockDirectoryAccount('erin', { apply: true });
  assert.ok(done.log.some((l) => l.includes('listings held now  0')));
  const list = (await db.doc('_internal/directoryBlocklist').get()).data();
  assert.deepEqual(list?.uids, ['erin']);
  assert.deepEqual(list?.emails, ['erin@example.com']);
  assert.deepEqual(list?.wpUserIds, [6]);
  assert.equal((await db.doc('directoryListings/600').get()).data()?.ownerUid, '');
  assert.equal((await db.doc('posts/directory_600').get()).exists, false);
});
