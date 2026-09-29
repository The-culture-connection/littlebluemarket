import { getFirestore, FieldValue, Timestamp } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions';

import { applyMarkerChanges, markerChanges } from './carted.ts';

import {
  donationCentsIn,
  fundingMonth,
  isDonationItem,
} from './donation_lines.ts';
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

  /**
   * A gift to Little Blue Market rather than a purchase from a maker.
   *
   * Everything downstream reads this one flag: no vendor is credited, no
   * product counts a sale, and the buyer gets no purchase document for it,
   * because there is nothing to review and nothing to be delivered.
   */
  donation?: boolean;
}

export interface NormalizedOrder {
  id: string;
  number: string;
  placedAt: Date;
  status: string;
  buyerUid: string | null;
  /** A Buy-now checkout: one item on its own, so the person's cart is not the thing that was paid for. */
  buyNow: boolean;
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
  // The configured donation products, for recognising a gift bought on the
  // website. A donation line the app made says so itself and needs none.
  donationProductIds: ReadonlySet<string> = new Set<string>(),
): Promise<NormalizedOrder> {
  const noteAttributes = payload.note_attributes as
    | Array<{ name?: string; value?: string }>
    | undefined;

  const lines: NormalizedLine[] = [];
  for (const item of (payload.line_items ?? []) as Array<Record<string, any>>) {
    const donation = isDonationItem(item, donationProductIds);
    // Per-line, because a multi-vendor order credits each seller only for
    // their own lines. A gift is not asked about at all: the store itself
    // is the vendor on it, and resolving that would hand somebody's
    // donation to whoever the store resolves to.
    const sellerUid = donation
      ? ''
      : await resolve({
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
      donation,
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
    buyNow: attribute(noteAttributes, 'app_buy_now') === 'true',
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
  // Read before the transaction so the markers the cart held can be
  // converted once it is cleared: the product leaves "in carts" and the
  // purchase document is what remains.
  const cartBefore = order.buyerUid
    ? (await db.collection('carts').doc(order.buyerUid).get()).data()
    : undefined;
  let clearedCart: Array<{ productId: string }> = [];
  // What of this order was a gift, and which month it belongs to.
  const donationCents = donationCentsIn(order.lines);
  const month = fundingMonth(order.placedAt);

  const outcome = await db.runTransaction(async (tx) => {
    const existing = await tx.get(orderRef);
    if (existing.exists) {
      // The retry case. Not an error, and not worth a second write.
      logger.info('Ignoring a replayed order webhook', { orderId: order.id });
      return 'duplicate' as const;
    }

    // Before the first write, because a transaction may not read after one.
    // Counting donors needs to know whether this person has already given
    // this month, and the answer must be the answer inside this
    // transaction or two simultaneous gifts both count as a new donor.
    const donorRef =
      donationCents > 0 && buyerUid
        ? db.collection('funding').doc(month).collection('donors').doc(buyerUid)
        : null;
    const firstGiftThisMonth = donorRef
      ? !(await tx.get(donorRef)).exists
      : false;

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
      // A gift is not a sale. It reaches no vendor total, which is the
      // property Gate 2 checks on the Shopify side.
      if (line.donation) continue;
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
        // "Gross sales" is what this number is: the sum of what buyers paid
        // for this seller's lines. Not a payout; that comes from Shipturtle.
        // `revenueCents` is kept in step until cutover, then dropped.
        {
          grossSalesCents: FieldValue.increment(cents),
          revenueCents: FieldValue.increment(cents),
        },
        { merge: true },
      );
    }

    // What has actually sold, per listing. The catalogue already carried
    // "how many added it" and "how many hold it now"; neither is a sale, so
    // "Best sellers" had nothing honest to sort on (Grace, 2026-09-23).
    // Counted from the paid order, like every other money-shaped number.
    const soldByProduct = new Map<string, number>();
    for (const line of order.lines) {
      if (line.donation) continue;
      if (!line.productId) continue;
      soldByProduct.set(
        line.productId,
        (soldByProduct.get(line.productId) ?? 0) + line.quantity,
      );
    }
    for (const [productId, quantity] of soldByProduct) {
      tx.set(
        db.collection('catalog').doc(productId),
        { soldCount: FieldValue.increment(quantity) },
        { merge: true },
      );
    }

    // An order the app started from the cart is the app's cart, paid for.
    // Empty the cart now, or the person comes back from checkout to the
    // things they just bought. Website orders carry no app_uid and touch no
    // cart; a Buy-now order was one item on its own and leaves the cart too.
    if (order.buyerUid && !order.buyNow) {
      tx.set(
        db.collection('carts').doc(order.buyerUid),
        { lines: [], clearedByOrder: order.id, updatedAt: FieldValue.serverTimestamp() },
        { merge: true },
      );
    }
    clearedCart = order.buyerUid && !order.buyNow
      ? ((cartBefore?.lines ?? []) as Array<{ productId: string }>)
      : [];

    // What was given, this month, from the store. `raisedCents` stays the
    // Shopify-side number and `sources` carries the same figure under its
    // own name, so the monthly membership can be added as a second source
    // in Phase 10 without migrating anything (addendum, 2026-09-29).
    if (donationCents > 0) {
      tx.set(
        db.collection('funding').doc(month),
        {
          raisedCents: FieldValue.increment(donationCents),
          sources: { shopify: FieldValue.increment(donationCents) },
          lastGiftAt: FieldValue.serverTimestamp(),
          // Once per person per month. An anonymous gift, from a website
          // order whose email matches no account, still raises the money
          // and counts nobody: a donor we cannot name is not a donor we
          // can count once.
          ...(firstGiftThisMonth ? { donors: FieldValue.increment(1) } : {}),
        },
        { merge: true },
      );
      if (donorRef && firstGiftThisMonth) {
        tx.set(donorRef, {
          firstGiftAt: Timestamp.fromDate(order.placedAt),
          orderId: order.id,
        });
      }
      if (buyerUid) {
        // The one thing the app reads to stop asking: the feed nudge and
        // the You row both go quiet on it.
        tx.set(
          db.collection('users').doc(buyerUid),
          { chippedInAt: Timestamp.fromDate(order.placedAt) },
          { merge: true },
        );
      }
    }

    if (buyerUid) {
      // Gifts are not things you bought, so they move no purchase count.
      const itemCount = order.lines.reduce(
        (sum, l) => (l.donation ? sum : sum + l.quantity),
        0,
      );
      tx.set(
        db.collection('users').doc(buyerUid),
        { purchaseCount: FieldValue.increment(itemCount) },
        { merge: true },
      );

      // Stage 12: who bought from whom, for "new from a shop you bought
      // from". One entry per seller on this order, never readable by a phone.
      for (const sellerUid of revenueBySeller.keys()) {
        tx.set(
          db.collection('sellers').doc(sellerUid).collection('buyers').doc(buyerUid),
          {
            lastOrderId: order.id,
            lastPurchaseAt: Timestamp.fromDate(order.placedAt),
            count: FieldValue.increment(1),
          },
          { merge: true },
        );
      }

      // One purchase document per line, because that is how they are used:
      // the profile grid lists them and the review composer picks one.
      // Not for a gift: there is nothing to deliver and nothing to review.
      for (const line of order.lines) {
        if (line.donation) continue;
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

  // Checkout converts the markers: the products leave "in carts" and the
  // purchase documents are what remain. Outside the transaction, like the
  // cart writes themselves.
  if (outcome === 'recorded' && order.buyerUid && clearedCart.length) {
    await applyMarkerChanges(order.buyerUid, markerChanges(clearedCart, []));
  }
  return outcome;
}

/** Marks the lines of an order delivered when a fulfilment reports it. */
export async function recordFulfillment(
  orderId: string,
  shipment: {
    trackingNumber: string;
    carrier: string;
    state: string;
    counterpartyName?: string;
    /**
     * False when the report could not be authenticated — currently only
     * ShipTurtle, whose signing secret may not exist. Stamped on the shipment
     * so that once it can be verified, the rows that never were are findable.
     */
    verified?: boolean;
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
      verified: shipment.verified !== false,
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
