import { FieldPath, FieldValue, getFirestore, Timestamp } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions';

import { notify } from './notifications.ts';

/**
 * "New from a shop you bought from."
 *
 * Who bought from whom is a reverse index, `sellers/{sellerUid}/buyers/
 * {buyerUid}`, written by the order pipeline on every paid order and by the
 * backfill for website history; nothing on a phone can read or write it.
 * When a seller's product goes active for the first time, every buyer in
 * that index hears about it, once: the product is stamped `announcedAt`
 * before anyone is told, and a product that was already active when the
 * app first saw it (the first deploy, a catalog backfill) is never
 * announced, because the transition is what counts, not the state.
 */

export const PROGRESS_DOC = '_internal/buyerIndexBackfill';
/** How recent a brand-new active product must be to count as a first appearance. */
export const FRESH_MS = 10 * 60_000;
/** People per call of the rebuild. */
export const PAGE = 100;

export interface BuyerEntry {
  lastOrderId: string;
  lastPurchaseAt: Timestamp | null;
  count: number;
}

function millis(value: unknown): number {
  if (value instanceof Timestamp) return value.toMillis();
  if (value instanceof Date) return value.getTime();
  if (typeof value === 'string') {
    const t = Date.parse(value);
    return Number.isNaN(t) ? 0 : t;
  }
  return 0;
}

/**
 * Whether this catalog write is the moment a seller's product first became
 * live. Pure. `before` missing means the mirror document is new: only a
 * product created in the last few minutes counts then, so an import of the
 * existing catalog announces nothing.
 */
export function shouldAnnounce(
  before: Record<string, unknown> | undefined,
  after: Record<string, unknown> | undefined,
  now = Date.now(),
): boolean {
  if (!after || after.active !== true) return false;
  if (!after.sellerId) return false;
  if (after.announcedAt) return false;
  if (before) return before.active !== true;
  const created = millis(after.createdAt);
  return created > 0 && now - created <= FRESH_MS;
}

/** One person's purchases folded into their sellers' buyer entries. Pure. */
export function buyersFromPurchases(
  purchases: Array<{ sellerId?: unknown; orderId?: unknown; purchasedAt?: unknown }>,
): Map<string, BuyerEntry> {
  const out = new Map<string, BuyerEntry>();
  for (const p of purchases) {
    const sellerId = String(p.sellerId ?? '');
    if (!sellerId) continue;
    const at = p.purchasedAt instanceof Timestamp ? p.purchasedAt : null;
    const current = out.get(sellerId);
    if (!current) {
      out.set(sellerId, { lastOrderId: String(p.orderId ?? ''), lastPurchaseAt: at, count: 1 });
      continue;
    }
    current.count += 1;
    if (at && (!current.lastPurchaseAt || at.toMillis() > current.lastPurchaseAt.toMillis())) {
      current.lastPurchaseAt = at;
      current.lastOrderId = String(p.orderId ?? '');
    }
  }
  return out;
}

export interface RebuildResult {
  /** People walked so far in this run. */
  processed: number;
  /** Buyer entries written so far in this run. */
  indexed: number;
  nextCursor: string | null;
  done: boolean;
}

/**
 * Rebuilds the index from every account's purchases, a page of people per
 * call. Sets rather than increments, so running it twice is harmless.
 */
export async function rebuildBuyerIndexPage(
  cursor: string | null,
  { reset = false }: { reset?: boolean } = {},
): Promise<RebuildResult> {
  const db = getFirestore();
  const progressRef = db.doc(PROGRESS_DOC);
  const stored = reset ? {} : ((await progressRef.get()).data() ?? {});
  const progress = stored.done === true && !cursor ? {} : stored;
  const after = cursor ?? (progress.nextCursor as string | null) ?? null;
  let processed = Number(progress.processed ?? 0);
  let indexed = Number(progress.indexed ?? 0);

  let query = db.collection('users').orderBy(FieldPath.documentId()).limit(PAGE);
  if (after) query = query.startAfter(after);
  const people = await query.get();

  for (const person of people.docs) {
    const purchases = await person.ref.collection('purchases').get();
    const entries = buyersFromPurchases(purchases.docs.map((d) => d.data()));
    if (entries.size) {
      const batch = db.batch();
      for (const [sellerId, entry] of entries) {
        batch.set(
          db.collection('sellers').doc(sellerId).collection('buyers').doc(person.id),
          { ...entry, rebuiltAt: FieldValue.serverTimestamp() },
          { merge: true },
        );
      }
      await batch.commit();
      indexed += entries.size;
    }
    processed++;
  }

  const last = people.docs.at(-1)?.id ?? null;
  const done = people.size < PAGE;
  await progressRef.set(
    { processed, indexed, nextCursor: done ? null : last, done, updatedAt: FieldValue.serverTimestamp() },
    { merge: true },
  );
  logger.info('Buyer index rebuilt (page)', { processed, indexed, done });
  return { processed, indexed, nextCursor: done ? null : last, done };
}

/** The trigger body: stamp first, then tell every buyer of that seller. */
export async function announceIfNew(
  productId: string,
  before: Record<string, unknown> | undefined,
  after: Record<string, unknown> | undefined,
): Promise<number> {
  if (!shouldAnnounce(before, after)) return 0;
  const db = getFirestore();
  const sellerId = String(after!.sellerId);
  await db.collection('catalog').doc(productId).set({ announcedAt: FieldValue.serverTimestamp() }, { merge: true });
  const buyers = await db.collection('sellers').doc(sellerId).collection('buyers').select().get();
  let told = 0;
  for (const buyer of buyers.docs) {
    if (buyer.id === sellerId) continue;
    await notify(buyer.id, {
      type: 'newProduct',
      fromUid: sellerId,
      text: String(after!.title ?? 'Something new'),
      route: `/market/product/${productId}`,
      productId,
    });
    told++;
  }
  logger.info('New product announced', { productId, sellerId, told });
  return told;
}
