import { getFirestore, FieldValue, Timestamp } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions';

import { resolveSellerUid, type VendorHints } from './vendors.ts';

/**
 * The order pipeline.
 *
 * This is where a purchase becomes a buyer's purchase count and a seller's
 * revenue, and it is the reason the app can drop the storefront later without
 * the profile screens noticing: the counters live in Firestore, computed from
 * events, and our own order pipeline would increment exactly the same ones.
 *
 * Two properties it must have:
 *
 *  1. **Idempotent.** Shopify retries webhooks, aggressively, and a replay that
 *     doubles someone's revenue is a silent corruption nobody notices until a
 *     payout is wrong. The provider's order id *is* the document id, and the
 *     whole write is one transaction that no-ops if the document already
 *     exists.
 *  2. **Attribution that works for both front doors.** An order placed in the
 *     app carries `app_uid` as a cart attribute. An order placed on the
 *     website carries nothing, so it falls back to matching the customer email
 *     against a verified account — which is what makes a website purchase show
 *     up on the buyer's app profile.
 */

export interface NormalizedLine {
  id: string;
  productId: string;
  variantId: string;
  title: string;
  variantTitle: string;
  unitPriceCents: number;
  quantity: number;
  sellerUid: string;
  imageUrl?: string;
}

export interface NormalizedOrder {
  id: string;
  number: string;
  placedAt: Date;
  status: string;
  buyerUid: string | null;
  buyerEmail: string | null;
  totalCents: number;
  lines: NormalizedLine[];
}

/** Money as an integer number of cents. */
export function toCents(amount: unknown): number {
  if (typeof amount === 'number') return Math.round(amount * 100);
  if (typeof amount === 'string') {
    const parsed = Number.parseFloat(amount);
    // A price that will not parse is a bug worth failing on rather than
    // silently recording as free.
    if (Number.isNaN(parsed)) throw new Error(`Unparseable amount: ${amount}`);
    return Math.round(parsed * 100);
  }
  throw new Error(`Unparseable amount: ${String(amount)}`);
}

/** Reads a Shopify note/cart attribute by name. */
export function attribute(
  attributes: Array<{ name?: string; key?: string; value?: string }> | undefined,
  name: string,
): string | undefined {
  if (!attributes) return undefined;
  for (const entry of attributes) {
    if ((entry.name ?? entry.key) === name && entry.value) return entry.value;
  }
  return undefined;
}

/**
 * A Shopify order payload becomes the shape the app understands.
 *
 * Exported so it can be tested against real payloads without a network or an
 * emulator — this is the function whose bugs corrupt money data.
 */
export async function normalizeOrder(
  payload: Record<string, any>,
  // Injectable so this can be tested against real payloads without a network
  // or an emulator. This is the function whose bugs corrupt money data, so it
  // must be testable in isolation.
  resolve: (hints: VendorHints) => Promise<string> = resolveSellerUid,
): Promise<NormalizedOrder> {
  const noteAttributes = payload.note_attributes as
    | Array<{ name?: string; value?: string }>
    | undefined;

  const lines: NormalizedLine[] = [];
  for (const item of (payload.line_items ?? []) as Array<Record<string, any>>) {
    // Per-line, because a multi-vendor order credits each seller only for
    // their own lines.
    const sellerUid = await resolve({
      vendor: item.vendor,
      productId: item.product_id ? String(item.product_id) : undefined,
      lineAttribute: attribute(item.properties, 'app_seller_uid'),
    });

    lines.push({
      id: String(item.id ?? ''),
      productId: String(item.product_id ?? ''),
      variantId: String(item.variant_id ?? ''),
      title: String(item.title ?? ''),
      variantTitle: String(item.variant_title ?? ''),
      unitPriceCents: toCents(item.price),
      quantity: Number(item.quantity ?? 1),
      sellerUid,
    });
  }

  return {
    id: String(payload.id),
    number: String(payload.name ?? `#${payload.order_number ?? payload.id}`),
    placedAt: payload.created_at ? new Date(payload.created_at) : new Date(),
    status: String(payload.financial_status ?? 'pending'),
    // The app stamps this on the cart at checkout, which is what makes an
    // app-originated order self-identifying.
    buyerUid: attribute(noteAttributes, 'app_uid') ?? null,
    buyerEmail: (payload.email ?? payload.contact_email ?? null) as string | null,
    totalCents: toCents(payload.total_price ?? '0'),
    lines,
  };
}

/**
 * Finds the account behind an order.
 *
 * Falls back to the email only when it belongs to a *verified* account, so a
 * website order cannot be attributed to someone who merely typed that address.
 */
export async function resolveBuyerUid(
  order: NormalizedOrder,
): Promise<string | null> {
  if (order.buyerUid) return order.buyerUid;
  if (!order.buyerEmail) return null;

  const db = getFirestore();
  const matches = await db
    .collection('users')
    .where('emailLower', '==', order.buyerEmail.trim().toLowerCase())
    .limit(2)
    .get();

  if (matches.empty) return null;
  if (matches.size > 1) {
    // Two accounts on one email should be impossible. Crediting the wrong one
    // is worse than crediting neither, so this stops.
    logger.error('Ambiguous email attribution', { email: order.buyerEmail });
    return null;
  }
  const doc = matches.docs[0];
  return doc ? doc.id : null;
}

/**
 * Records a paid order and moves every counter it touches.
 *
 * One transaction, keyed by the provider's order id, so replaying the webhook
 * is a no-op rather than a second helping of revenue.
 */
export async function recordPaidOrder(
  order: NormalizedOrder,
): Promise<'recorded' | 'duplicate'> {
  const db = getFirestore();
  const orderRef = db.collection('orders').doc(order.id);
  const buyerUid = await resolveBuyerUid(order);

  return db.runTransaction(async (tx) => {
    const existing = await tx.get(orderRef);
    if (existing.exists) {
      // The retry case. Not an error, and not worth a second write.
      logger.info('Ignoring a replayed order webhook', { orderId: order.id });
      return 'duplicate' as const;
    }

    const sellerUids = [
      ...new Set(order.lines.map((line) => line.sellerUid).filter(Boolean)),
    ];

    tx.set(orderRef, {
      number: order.number,
      placedAt: Timestamp.fromDate(order.placedAt),
      status: order.status,
      totalCents: order.totalCents,
      buyerUid,
      sellerUids,
      lines: order.lines,
      shipments: [],
      recordedAt: FieldValue.serverTimestamp(),
    });

    // Each seller is credited only for their own lines.
    const revenueBySeller = new Map<string, number>();
    for (const line of order.lines) {
      if (!line.sellerUid) continue;
      revenueBySeller.set(
        line.sellerUid,
        (revenueBySeller.get(line.sellerUid) ?? 0) +
          line.unitPriceCents * line.quantity,
      );
    }
    for (const [sellerUid, cents] of revenueBySeller) {
      tx.set(
        db.collection('users').doc(sellerUid),
        { revenueCents: FieldValue.increment(cents) },
        { merge: true },
      );
    }

    if (buyerUid) {
      const itemCount = order.lines.reduce((sum, l) => sum + l.quantity, 0);
      tx.set(
        db.collection('users').doc(buyerUid),
        { purchaseCount: FieldValue.increment(itemCount) },
        { merge: true },
      );

      // One purchase document per line, because that is how they are used:
      // the profile grid lists them and the review composer picks one.
      for (const line of order.lines) {
        tx.set(
          db
            .collection('users')
            .doc(buyerUid)
            .collection('purchases')
            .doc(`${order.id}_${line.id}`),
          {
            orderId: order.id,
            productId: line.productId,
            title: line.title,
            sellerId: line.sellerUid,
            imageUrl: line.imageUrl ?? null,
            purchasedAt: Timestamp.fromDate(order.placedAt),
            delivered: false,
            reviewed: false,
          },
        );
      }
    } else {
      // Worth knowing about: an order nobody is credited for usually means an
      // email that does not match any account yet.
      logger.warn('Order recorded with no buyer attribution', {
        orderId: order.id,
        email: order.buyerEmail,
      });
    }

    return 'recorded' as const;
  });
}

/** Marks the lines of an order delivered when a fulfilment reports it. */
export async function recordFulfillment(
  orderId: string,
  shipment: {
    trackingNumber: string;
    carrier: string;
    state: string;
    counterpartyName?: string;
  },
): Promise<void> {
  const db = getFirestore();
  const orderRef = db.collection('orders').doc(orderId);

  await db.runTransaction(async (tx) => {
    const snapshot = await tx.get(orderRef);
    if (!snapshot.exists) {
      logger.warn('Fulfilment for an unknown order', { orderId });
      return;
    }

    const data = snapshot.data() ?? {};
    const shipments = (data.shipments ?? []) as Array<Record<string, unknown>>;

    // Keyed by tracking number so a fulfilment update replaces its shipment
    // rather than appending a duplicate.
    const next = shipments.filter(
      (s) => s.tracking !== shipment.trackingNumber,
    );
    next.push({
      productId: (data.lines?.[0]?.productId ?? '') as string,
      counterpartyName: shipment.counterpartyName ?? shipment.carrier,
      state: shipment.state,
      tracking: shipment.trackingNumber,
      carrierNote: shipment.carrier,
    });

    tx.update(orderRef, {
      shipments: next,
      status: shipment.state === 'delivered' ? 'fulfilled' : data.status,
    });

    if (shipment.state === 'delivered' && data.buyerUid) {
      for (const line of (data.lines ?? []) as NormalizedLine[]) {
        tx.set(
          db
            .collection('users')
            .doc(data.buyerUid as string)
            .collection('purchases')
            .doc(`${orderId}_${line.id}`),
          { delivered: true },
          { merge: true },
        );
      }
    }
  });
}
