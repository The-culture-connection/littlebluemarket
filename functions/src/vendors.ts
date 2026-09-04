import { getFirestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions';

/**
 * Which app account a sale belongs to.
 *
 * **This is the one piece that is genuinely blocked.** ShipTurtle is the
 * system of record for vendors, and the rule that maps one of its vendors to an
 * app account has not been decided yet. Everything else in the order pipeline
 * is finished and tested; revenue attribution cannot be *verified* until this
 * is settled against real vendor data.
 *
 * So it is built as a chain of strategies rather than one hardcoded rule.
 * Changing the answer means reordering or replacing a strategy here, not
 * touching the pipeline.
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
 *  3. **The Shopify product's vendor name**, matched against a seller's stored
 *     vendor name.
 *  4. **The vendor's email**, matched against a verified account. The most
 *     likely final rule, and the one to confirm first.
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

/** Cached for the life of an instance; vendor mappings change rarely. */
const resolved = new Map<string, string>();

function cacheKey(hints: VendorHints): string {
  return [hints.lineAttribute, hints.productId, hints.vendor, hints.email]
    .map((part) => part ?? '')
    .join('|');
}

export async function resolveSellerUid(hints: VendorHints): Promise<string> {
  // 1. Self-identifying. No lookup, no ambiguity.
  if (hints.lineAttribute) return hints.lineAttribute;

  const key = cacheKey(hints);
  const cached = resolved.get(key);
  if (cached !== undefined) return cached;

  const uid = await lookup(hints);
  resolved.set(key, uid);
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

  // 3. The vendor name a seller has recorded.
  if (hints.vendor) {
    const byVendor = await db
      .collection('users')
      .where('shopifyVendorName', '==', hints.vendor)
      .limit(2)
      .get();
    if (byVendor.size === 1) {
      const doc = byVendor.docs[0];
      if (doc) return doc.id;
    }
    if (byVendor.size > 1) {
      logger.error('Two accounts claim one vendor name', {
        vendor: hints.vendor,
      });
    }
  }

  // 4. The likely final rule, pending confirmation against real vendor data.
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

/** Clears the instance cache. Call after writing a mapping. */
export function forgetVendorCache(): void {
  resolved.clear();
}
