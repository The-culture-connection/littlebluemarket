/**
 * Security rules, tested against the emulator.
 *
 * These assert the promise the whole revenue design rests on: **a client cannot
 * write its own money.** Everything else in the app can be re-derived; a seller
 * who can set their own revenue cannot.
 *
 * Not part of `npm test`, because they need a running emulator:
 *
 *   npm run test:rules
 */
import { strict as assert } from 'node:assert';
import { after, before, describe, test } from 'node:test';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';

// Resolved against this file, not the process cwd, so the suite runs the same
// from `functions/` and from the repo root.
const RULES = join(
  dirname(fileURLToPath(import.meta.url)),
  '..',
  '..',
  'firebase',
  'firestore.rules',
);

let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'little-blue-cart-rules-test',
    firestore: {
      rules: readFileSync(RULES, 'utf8'),
      host: '127.0.0.1',
      port: 8080,
    },
  });
});

after(async () => {
  await env?.cleanup();
});

/** A signed-in member. */
const member = (uid = 'maya') =>
  env.authenticatedContext(uid, {
    firebase: { sign_in_provider: 'password' },
  }).firestore();

/** A guest: signed in anonymously, so they hold a uid but are not a member. */
const guest = () =>
  env.authenticatedContext('anon', {
    firebase: { sign_in_provider: 'anonymous' },
  }).firestore();

describe('money is never client-writable', () => {
  test('a seller cannot set their own revenue', async () => {
    const db = member('maya');
    await env.withSecurityRulesDisabled(async (admin) => {
      await admin.firestore().doc('users/maya').set({
        name: 'Maya',
        revenueCents: 100,
        purchaseCount: 1,
        postCount: 0,
      });
    });

    // The single most important assertion in this file.
    await assertFails(
      db.doc('users/maya').update({ revenueCents: 999999 }),
    );
    await assertFails(db.doc('users/maya').update({ purchaseCount: 999 }));
  });

  test('but can still edit their profile', async () => {
    const db = member('maya');
    await assertSucceeds(
      db.doc('users/maya').update({ bio: 'New bio.', name: 'Maya E.' }),
    );
  });

  test('nobody can write an order', async () => {
    await assertFails(
      member().doc('orders/o1').set({ totalCents: 1 }),
    );
  });

  test('nobody can write a purchase record', async () => {
    await assertFails(
      member('maya').doc('users/maya/purchases/p1').set({ reviewed: true }),
    );
  });

  test('nobody can touch the internal token cache', async () => {
    await assertFails(member().doc('_internal/shopifyAdminToken').get());
    await assertFails(
      member().doc('_internal/shopifyAdminToken').set({ token: 'stolen' }),
    );
  });

  test('nobody can write the catalog', async () => {
    await assertFails(
      member().doc('catalog/p1').set({ priceCents: 1 }),
    );
  });
});

describe('you can only act as yourself', () => {
  test('you cannot edit someone else\'s profile', async () => {
    await assertFails(member('maya').doc('users/kali').update({ bio: 'hi' }));
  });

  test('you cannot post as someone else', async () => {
    await assertFails(
      member('maya').collection('posts').add({
        kind: 'shoutout',
        authorId: 'kali',
        text: 'not mine',
        likeCount: 0,
        commentCount: 0,
      }),
    );
  });

  test('you cannot like on someone else\'s behalf', async () => {
    // The like document is keyed by uid, so this is what stops it.
    await assertFails(
      member('maya').doc('posts/p1/likes/kali').set({ uid: 'kali' }),
    );
  });

  test('you cannot create a post already carrying likes', async () => {
    await assertFails(
      member('maya').collection('posts').add({
        kind: 'shoutout',
        authorId: 'maya',
        text: 'hi',
        likeCount: 500,
        commentCount: 0,
      }),
    );
  });
});

describe('guests browse but do not write', () => {
  test('a guest can read the catalog and profiles', async () => {
    await assertSucceeds(guest().doc('catalog/p1').get());
    await assertSucceeds(guest().doc('users/maya').get());
  });

  test('a guest cannot post, like or message', async () => {
    const db = guest();
    await assertFails(
      db.collection('posts').add({
        kind: 'shoutout',
        authorId: 'anon',
        text: 'hi',
        likeCount: 0,
        commentCount: 0,
      }),
    );
    await assertFails(db.doc('posts/p1/likes/anon').set({ uid: 'anon' }));
    await assertFails(
      db.collection('chatroom').add({ authorId: 'anon', text: 'hi' }),
    );
  });

  test('a guest still owns their own cart', async () => {
    // They hold a uid, which is what lets a cart built before signing up
    // survive the upgrade.
    await assertSucceeds(guest().doc('carts/anon').set({ lines: [] }));
  });
});

describe('conversations are private to their two participants', () => {
  before(async () => {
    await env.withSecurityRulesDisabled(async (admin) => {
      await admin.firestore().doc('conversations/kali_maya').set({
        participantIds: ['kali', 'maya'],
        preview: 'hi',
      });
    });
  });

  test('a participant can read it', async () => {
    await assertSucceeds(member('maya').doc('conversations/kali_maya').get());
  });

  test('a third party cannot', async () => {
    await assertFails(member('rae').doc('conversations/kali_maya').get());
  });

  test('nobody can change who is in it', async () => {
    await assertFails(
      member('maya')
        .doc('conversations/kali_maya')
        .update({ participantIds: ['maya', 'rae'] }),
    );
  });
});

describe('forums', () => {
  test('a new forum starts with one member and no threads', async () => {
    await assertSucceeds(
      member('maya').doc('forums/new1').set({
        title: 'Refills',
        description: 'x',
        createdBy: 'maya',
        memberCount: 1,
        threadCount: 0,
      }),
    );
    await assertFails(
      member('maya').doc('forums/new2').set({
        title: 'Inflated',
        description: 'x',
        createdBy: 'maya',
        memberCount: 9999,
        threadCount: 0,
      }),
    );
  });

  test('member and thread counts are not client-writable', async () => {
    await assertFails(
      member('maya').doc('forums/new1').update({ memberCount: 5000 }),
    );
  });
});

describe('selling is a grant, not a client write', () => {
  // The escalation this closes was reachable in two writes: set
  // `isSeller: true` on your own user document, then claim a vendor name that
  // the real owner has not signed up to defend. The order pipeline credits a
  // sale to whichever single account claims that name, so the second write
  // inherited a stranger's catalogue and their revenue.

  test('a member cannot make themselves a seller', async () => {
    await env.withSecurityRulesDisabled(async (admin) => {
      await admin.firestore().doc('users/maya').set({
        name: 'Maya',
        revenueCents: 0,
        purchaseCount: 0,
        postCount: 0,
      });
    });

    // Write one of the two. Before this phase, both succeeded.
    await assertFails(member('maya').doc('users/maya').update({ isSeller: true }));
  });

  test('a member cannot claim a vendor name on their user document', async () => {
    // The leg that actually stole the money.
    await assertFails(
      member('maya').doc('users/maya').update({ shopifyVendorName: 'Gwynstone' }),
    );
    await assertFails(
      member('maya').doc('users/maya').update({ shopifyLocationId: 'gid://x' }),
    );
  });

  test('a new account cannot be created already selling', async () => {
    await assertFails(
      member('fresh').doc('users/fresh').set({
        name: 'Fresh',
        revenueCents: 0,
        purchaseCount: 0,
        postCount: 0,
        isSeller: true,
      }),
    );
  });

  test('seller identity documents are function-written only', async () => {
    await assertFails(
      member('maya').doc('sellers/maya').set({ shopifyVendorName: 'Gwynstone' }),
    );
    await assertFails(
      member('maya').doc('vendorNames/gwynstone').set({ uid: 'maya' }),
    );
    await assertFails(
      member('maya').doc('vendorClaims/abc123').set({ vendorName: 'Gwynstone' }),
    );
  });

  test('claim codes cannot be read by anyone', async () => {
    await env.withSecurityRulesDisabled(async (admin) => {
      await admin.firestore().doc('vendorClaims/abc123').set({
        vendorName: 'Gwynstone',
        vendorId: '1092484',
      });
    });

    // A readable list of unused codes is the same thing as no codes at all:
    // anyone who could read it could grant themselves any shop in it.
    await assertFails(member('maya').doc('vendorClaims/abc123').get());
    await assertFails(guest().doc('vendorClaims/abc123').get());
  });

  test('a grant is public to read, so a shop can be shown on a profile', async () => {
    await env.withSecurityRulesDisabled(async (admin) => {
      await admin.firestore().doc('sellers/kali').set({
        shopifyVendorName: 'Gwynstone',
      });
      await admin.firestore().doc('vendorNames/gwynstone').set({ uid: 'kali' });
    });

    await assertSucceeds(member('maya').doc('sellers/kali').get());
    await assertSucceeds(member('maya').doc('vendorNames/gwynstone').get());
  });
});

describe('creating a profile', () => {
  // The shape FirestoreProfileRepository.updateProfile writes on first save.
  // Grace hit PERMISSION_DENIED on her very first sign-up because the app
  // omitted the counters; this pins the contract between the two.
  const firstSave = {
    revenueCents: 0,
    purchaseCount: 0,
    postCount: 0,
    name: 'Grace',
    handle: '@grace',
    handleLower: 'grace',
    bio: '',
  };

  test('the first profile save, as the app writes it, is allowed', async () => {
    await assertSucceeds(member('newbie').doc('users/newbie').set(firstSave));
  });

  test('a first save that omits the counters is refused', async () => {
    const { revenueCents, purchaseCount, postCount, ...bare } = firstSave;
    await assertFails(member('newbie2').doc('users/newbie2').set(bare));
  });

  test('a first save cannot smuggle a non-zero counter or a seller flag', async () => {
    await assertFails(
      member('newbie3').doc('users/newbie3').set({ ...firstSave, revenueCents: 1 }),
    );
    await assertFails(
      member('newbie4').doc('users/newbie4').set({ ...firstSave, isSeller: true }),
    );
  });
});
