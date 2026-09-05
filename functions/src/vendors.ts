import { getFirestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions';

import { normalizeVendorName } from './sellers.ts';

/**
 * Which app account a sale belongs to.
 *
 * Built as a chain of strategies rather than one hardcoded rule, so changing
 * the answer means reordering or replacing a strategy here, not touching the
 * order pipeline.
 *
 * The strategies, in the order they are tried:
 *
 *  1. **An explicit line attribute.** An order placed in the app stamps
 *     `app_seller_uid` on each line, so it is self-identifying and needs no
 *     lookup at all. This is exact, and it is why app orders will attribute
 *     correctly from day one regardless of how the rest is settled.
 *  2. **An explicit mapping document.** `vendorMappings/{vendorKey}` holds a
 *     uid. This is the escape hatch: anything the automatic rules get wrong can
 *     be corrected by writing one document, without a deploy.
 *  3. **The Shopify product's vendor name**, looked up in `vendorNames/`,
 *     which a seller reserves when their claim is granted and which nothing
 *     client-side can write. A revoked seller is not credited.
 *  4. **The vendor's email**, matched against a verified seller account.
 *
 * If none match, the sale is recorded with no seller rather than credited to
 * someone arbitrary. An uncredited sale is a reconciliation task; a
 * miscredited one is a wrong payout.
 */

export interface VendorHints {
  /** Shopify's product-level vendor name. */
  vendor?: string;
  /** The Shopify product id, for a mapping keyed by product. */
  productId?: string;
  /** `app_seller_uid`, present on app-originated orders. */
  lineAttribute?: string;
  /** The vendor's email, when the payload carries one. */
  email?: string;
}

export type Lookup = (hints: VendorHints) => Promise<string>;

/** Hits, cached for the life of an instance; vendor mappings change rarely. */
const resolved = new Map<string, string>();

/**
 * Misses, cached only briefly. A miss used to be cached forever, so a warm
 * instance kept returning "no seller" for a vendor whose claim had just been
 * granted — every product mirrored in the following hours stayed orphaned.
 */
const missedAt = new Map<string, number>();
export const MISS_TTL_MS = 60 * 1000;

function cacheKey(hints: VendorHints): string {
  return [hints.lineAttribute, hints.productId, hints.vendor, hints.email]
    .map((part) => part ?? '')
    .join('|');
}

export async function resolveSellerUid(
  hints: VendorHints,
  lookupFn: Lookup = lookup,
  now: () => number = Date.now,
): Promise<string> {
  // 1. Self-identifying. No lookup, no ambiguity.
  if (hints.lineAttribute) return hints.lineAttribute;

  const key = cacheKey(hints);
  const hit = resolved.get(key);
  if (hit !== undefined) return hit;

  const missed = missedAt.get(key);
  if (missed !== undefined && now() - missed < MISS_TTL_MS) return '';

  const uid = await lookupFn(hints);
  if (uid) {
    resolved.set(key, uid);
    missedAt.delete(key);
  } else {
    missedAt.set(key, now());
  }
  return uid;
}

async function lookup(hints: VendorHints): Promise<string> {
  const db = getFirestore();

  // 2. An explicit override, which is how a wrong answer gets corrected
  // without a deploy.
  for (const candidate of [hints.productId, hints.vendor, hints.email]) {
    if (!candidate) continue;
    const doc = await db
      .collection('vendorMappings')
      .doc(normalizeKey(candidate))
      .get();
    const uid = doc.data()?.uid;
    if (typeof uid === 'string' && uid) return uid;
  }

  // 3. The reservation a granted seller holds on their vendor name.
  if (hints.vendor) {
    const reserved = await db
      .collection('vendorNames')
      .doc(normalizeVendorName(hints.vendor))
      .get();
    const uid = reserved.data()?.uid;
    if (typeof uid === 'string' && uid) {
      const seller = await db.collection('sellers').doc(uid).get();
      if (seller.exists && !seller.data()?.revokedAt) return uid;
      logger.warn('Vendor name is reserved by a revoked seller', {
        vendor: hints.vendor,
        uid,
      });
    }
  }

  // 4. A verified seller account with the vendor's email.
  if (hints.email) {
    const byEmail = await db
      .collection('users')
      .where('emailLower', '==', hints.email.trim().toLowerCase())
      .where('isSeller', '==', true)
      .limit(2)
      .get();
    if (byEmail.size === 1) {
      const doc = byEmail.docs[0];
      if (doc) return doc.id;
    }
  }

  // Uncredited beats miscredited. This shows up in the logs as work to do,
  // rather than as a wrong payout nobody notices.
  logger.warn('Could not attribute a sale to a seller', { ...hints });
  return '';
}

function normalizeKey(value: string): string {
  return value.trim().toLowerCase().replace(/[^a-z0-9]+/g, '-');
}

/** Clears both caches. Called after a grant, a revoke, or a mapping write. */
export function forgetVendorCache(): void {
  resolved.clear();
  missedAt.clear();
}
