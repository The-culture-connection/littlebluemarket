import { FieldValue, getFirestore, type Firestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions';

import { normalizeVendorName } from './sellers.ts';

/**
 * A profile for every shop on the market, whether or not anyone has signed
 * up for it.
 *
 * Grace, 2026-09-24: "all sellers on the market already have a profile and
 * they just need to sign in by verifying their seller email, so all products
 * are claimed by a profile... searching a seller shows all their products
 * and shows them as a regular profile, they are messagable, just unclaimed
 * with a notice."
 *
 * Before this, a product whose vendor had not signed up carried
 * `sellerId: ''`. That is a hole with a shop in it: the listing said "this
 * shop has not joined the app yet", searching the shop's name found the
 * odd listing whose title happened to match, and there was nobody to
 * message. Seventy-odd vendors were invisible as shops.
 *
 * So every vendor string the catalogue carries gets a **shell profile**: an
 * ordinary `users/{uid}` document under a derived uid, `shop_<vendorKey>`,
 * flagged `unclaimed: true`. Being an ordinary user document is the whole
 * point — search, the profile screen, the product's "Sold by" strip and
 * messaging all work on it with no special case anywhere.
 *
 * Three things keep a shell honest:
 *
 *  1. **It has no Firebase Auth account**, so nobody can sign in as one. It
 *     is a face, not a login.
 *  2. **It is never granted selling.** `sellers/{uid}` and the `seller`
 *     custom claim are untouched; a shell cannot list a product, take a
 *     payout or write anything. `isSeller` on the document is a display
 *     fact ("this is a shop"), which is all the phone reads it for.
 *  3. **It hands everything over on a claim.** See [claimShopShell]: the
 *     products re-attribute (that already happened), and the sales it
 *     accrued and the conversations people started with it move to the
 *     account that claimed it.
 */

/** The uid a vendor's shell profile lives under. Pure. */
export function shopUidFor(vendorName: string): string {
  const key = normalizeVendorName(vendorName);
  return key ? `shop_${key}` : '';
}

/** Whether a uid belongs to a shell rather than a person. Pure. */
export function isShopUid(uid: string): boolean {
  return uid.startsWith('shop_');
}

/**
 * A handle for a shop nobody has claimed.
 *
 * Derived from the vendor string so it is stable and recognisable, and
 * deliberately not guaranteed unique against real handles: uniqueness is
 * enforced for handles people choose (`handleAvailable`), and a shell's is
 * a placeholder until somebody claims it and picks their own. Kept out of
 * the way of a collision by the `handleLower` it is stored under being the
 * vendor key, which contains no characters a person may type.
 */
export function shopHandleFor(vendorName: string): string {
  const key = normalizeVendorName(vendorName);
  return key ? `@${key}` : '';
}

/** What the phone shows as the shop's name: the brand, else the raw string. */
export function shopNameFor(vendorName: string, brandName?: string | null): string {
  return (brandName ?? '').trim() || vendorName.trim();
}

export interface ShellFacts {
  vendorName: string;
  brandName?: string | null;
  cityState?: string | null;
}

/**
 * Creates or refreshes a vendor's shell profile, and returns its uid.
 *
 * Idempotent, and careful about what it overwrites: a claimed shop's
 * document is left completely alone, because by then it is somebody's real
 * profile and the vendor string is not the authority on their name any
 * more. Counters are never written here.
 */
export async function ensureShopShell(
  facts: ShellFacts,
  db: Firestore = getFirestore(),
): Promise<string> {
  const uid = shopUidFor(facts.vendorName);
  if (!uid) return '';
  const ref = db.collection('users').doc(uid);
  const existing = await ref.get();
  if (existing.exists && existing.data()?.unclaimed !== true) {
    // Claimed, or somehow a real account. Not ours to touch.
    return uid;
  }

  const name = shopNameFor(facts.vendorName, facts.brandName);
  const handle = shopHandleFor(facts.vendorName);
  await ref.set(
    {
      name,
      nameLower: name.toLowerCase(),
      handle,
      handleLower: handle.replace(/^@/, ''),
      // A shop, for display. Not a grant: `sellers/{uid}` and the custom
      // claim are what actually permit anything, and a shell has neither.
      isSeller: true,
      unclaimed: true,
      shopVendorName: facts.vendorName,
      ...(facts.cityState ? { cityState: facts.cityState } : {}),
      ...(existing.exists
        ? {}
        : {
            bio: '',
            tags: [],
            tagsLower: [],
            revenueCents: 0,
            grossSalesCents: 0,
            purchaseCount: 0,
            postCount: 0,
            createdAt: FieldValue.serverTimestamp(),
          }),
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
  return uid;
}

/**
 * Moves everything a shell accrued to the account that has just claimed it,
 * then marks the shell claimed so it stops appearing as a shop of its own.
 *
 * The products are not touched here: `backfillSellerForVendor` already
 * re-points every product carrying the vendor string, and it runs from the
 * `sellers/{uid}` trigger the grant writes.
 */
export async function claimShopShell(
  vendorName: string,
  uid: string,
  db: Firestore = getFirestore(),
): Promise<{ shellUid: string; conversations: number; grossSalesCents: number }> {
  const shellUid = shopUidFor(vendorName);
  if (!shellUid || shellUid === uid) {
    return { shellUid: '', conversations: 0, grossSalesCents: 0 };
  }
  const shellRef = db.collection('users').doc(shellUid);
  const shell = await shellRef.get();
  if (!shell.exists || shell.data()?.unclaimed !== true) {
    return { shellUid, conversations: 0, grossSalesCents: 0 };
  }

  // What the shop earned while nobody had signed up for it belongs to
  // whoever has now. Incremented onto the real account rather than copied,
  // because they may already have some of their own.
  const data = shell.data() ?? {};
  const gross = Number(data.grossSalesCents ?? 0) || 0;
  const revenue = Number(data.revenueCents ?? 0) || 0;
  if (gross || revenue) {
    await db.collection('users').doc(uid).set(
      {
        grossSalesCents: FieldValue.increment(gross),
        revenueCents: FieldValue.increment(revenue),
      },
      { merge: true },
    );
  }

  const conversations = await moveShellConversations(shellUid, uid, db);

  await shellRef.set(
    {
      unclaimed: false,
      claimedBy: uid,
      claimedAt: FieldValue.serverTimestamp(),
      // Out of search and off the shop rails: the real profile is the shop
      // now, and two of them would be worse than none.
      isSeller: false,
      nameLower: '',
      handleLower: '',
      grossSalesCents: 0,
      revenueCents: 0,
    },
    { merge: true },
  );

  logger.info('Shop shell claimed', { vendorName, shellUid, uid, conversations, gross });
  return { shellUid, conversations, grossSalesCents: gross };
}

/**
 * Hands every conversation somebody started with the shell to the account
 * that claimed it.
 *
 * The documents are **moved**, not relabelled: a thread's id is derived
 * from the sorted pair of uids, so leaving it where it is and swapping a
 * participant would strand it — the buyer's next tap would derive the id
 * for the new pair, find nothing, and start an empty second thread beside
 * the one holding the history.
 */
async function moveShellConversations(
  shellUid: string,
  uid: string,
  db: Firestore,
): Promise<number> {
  const snapshot = await db
    .collection('conversations')
    .where('participantIds', 'array-contains', shellUid)
    .get();

  let moved = 0;
  for (const doc of snapshot.docs) {
    const data = doc.data();
    const others = (Array.isArray(data.participantIds) ? data.participantIds : [])
      .map(String)
      .filter((p) => p !== shellUid);
    const other = others[0];
    // A thread with nobody else in it, or one the claimant was already in,
    // has nowhere useful to go.
    if (!other || other === uid) continue;

    const participantIds = [uid, other].sort();
    const target = db.collection('conversations').doc(conversationIdFor(uid, other));
    if (target.id === doc.id) continue;

    const unread = (data.unread ?? {}) as Record<string, unknown>;
    const existing = await target.get();
    await target.set(
      {
        ...data,
        participantIds,
        unread: {
          [other]: Number(unread[other] ?? 0) || 0,
          // What the shop never read is unread for whoever owns it now.
          [uid]: Number(unread[shellUid] ?? 0) || 0,
        },
      },
      { merge: existing.exists },
    );

    // The messages themselves. A pre-claim thread is short by nature, and
    // this runs once per shop, so a straight copy is the honest way.
    const messages = await doc.ref.collection('messages').get();
    for (let i = 0; i < messages.docs.length; i += 400) {
      const batch = db.batch();
      for (const message of messages.docs.slice(i, i + 400)) {
        batch.set(target.collection('messages').doc(message.id), message.data());
        batch.delete(message.ref);
      }
      await batch.commit();
    }
    await doc.ref.delete();
    moved += 1;
  }
  return moved;
}

/**
 * Gives every vendor already in the catalogue a shell, and attaches the
 * products that have no shop to it.
 *
 * What makes the seventy-odd shops that were mirrored before today visible.
 * Idempotent: a vendor that already has a shell is refreshed, a product that
 * already has a seller is left alone, and a claimed shop is not touched.
 */
export async function backfillShopShells(
  db: Firestore = getFirestore(),
): Promise<{ vendors: number; shells: number; products: number }> {
  const snapshot = await db.collection('catalog').select('vendorName', 'sellerId').get();

  // vendor string -> the product docs under it that have no shop.
  const orphansByVendor = new Map<string, string[]>();
  const vendors = new Set<string>();
  for (const doc of snapshot.docs) {
    const vendorName = String(doc.get('vendorName') ?? '').trim();
    if (!vendorName) continue;
    vendors.add(vendorName);
    if (String(doc.get('sellerId') ?? '')) continue;
    const list = orphansByVendor.get(vendorName) ?? [];
    list.push(doc.id);
    orphansByVendor.set(vendorName, list);
  }

  let shells = 0;
  let products = 0;
  for (const vendorName of vendors) {
    const uid = await ensureShopShell({ vendorName }, db);
    if (!uid) continue;
    shells += 1;
    const orphans = orphansByVendor.get(vendorName) ?? [];
    for (let i = 0; i < orphans.length; i += 400) {
      const batch = db.batch();
      for (const id of orphans.slice(i, i + 400)) {
        batch.set(db.collection('catalog').doc(id), { sellerId: uid }, { merge: true });
        products += 1;
      }
      await batch.commit();
    }
  }
  logger.info('Shop shells backfilled', { vendors: vendors.size, shells, products });
  return { vendors: vendors.size, shells, products };
}

/** The same id the app derives, so a moved thread lands where the buyer's
 * next tap will look for it. Mirrors `Conversation.idFor` in
 * `lib/models/message.dart`; if one changes, both change.
 */
export function conversationIdFor(a: string, b: string): string {
  return [a, b].sort().join('_');
}
