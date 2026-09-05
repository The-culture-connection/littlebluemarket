import { getFirestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions';
import { HttpsError } from 'firebase-functions/v2/https';

import { recordFulfillment } from './orders.ts';
import { adminGraphQL } from './shopify/token.ts';

/**
 * A seller marking an order shipped.
 *
 * One call so the courier and the buyer learn the same number: the fulfilment
 * is created on the store (which Shipturtle mirrors), and the same tracking
 * is written onto our order document so the buyer's Receiving tab shows it
 * whether or not the store call succeeded.
 *
 * Order matters here. The upstream write happens first, because if it fails the
 * seller needs to know now — showing the buyer a tracking number the courier
 * has never heard of is worse than an error message.
 */
export async function addTracking(input: {
  sellerUid: string;
  orderId: string;
  trackingNumber: string;
  carrier: string;
}): Promise<{ ok: true; upstream: 'created' | 'nothing-open' | 'unavailable' }> {
  const db = getFirestore();
  const orderRef = db.collection('orders').doc(input.orderId);
  const order = await orderRef.get();

  if (!order.exists) {
    throw new HttpsError('not-found', 'No order with that number.');
  }

  // A seller may only ship their own lines. Without this check any signed-in
  // account could write tracking onto anyone's order.
  const sellerUids = (order.data()?.sellerUids ?? []) as string[];
  if (!sellerUids.includes(input.sellerUid)) {
    throw new HttpsError('permission-denied', 'That is not your order.');
  }

  const upstream = await fulfillInShopify(input);

  await recordFulfillment(input.orderId, {
    trackingNumber: input.trackingNumber,
    carrier: input.carrier,
    state: 'inTransit',
  });

  return { ok: true, upstream };
}

/**
 * Creates the fulfilment on the store.
 *
 * Shipturtle mirrors Shopify, so a fulfilment created here reaches the
 * vendor's Shipturtle dashboard on its next sync, and Shopify's own
 * `fulfillments/update` webhook records it back onto our order. Their API
 * has no fulfilment endpoint of its own; the guessed URL that lived here
 * is gone.
 *
 * Needs the merchant-managed fulfilment order scopes. Without them the
 * fulfilment is recorded locally only and the result says so, rather than
 * a seller at a parcel counter being told nothing went through.
 */
async function fulfillInShopify(input: {
  orderId: string;
  trackingNumber: string;
  carrier: string;
}): Promise<'created' | 'nothing-open' | 'unavailable'> {
  let orders;
  try {
    orders = await adminGraphQL<{
      order: { fulfillmentOrders: { nodes: Array<{ id: string; status: string }> } } | null;
    }>(
      `query Open($id: ID!) { order(id: $id) { fulfillmentOrders(first: 10) { nodes { id status } } } }`,
      { id: `gid://shopify/Order/${input.orderId}` },
    );
  } catch (error) {
    logger.warn('Could not read fulfilment orders; tracking recorded locally only', {
      orderId: input.orderId,
      error: String(error).slice(0, 200),
      fix: 'grant read_merchant_managed_fulfillment_orders and write_merchant_managed_fulfillment_orders',
    });
    return 'unavailable';
  }
  const open = (orders.order?.fulfillmentOrders.nodes ?? []).filter((n) =>
    ['OPEN', 'IN_PROGRESS', 'SCHEDULED'].includes(n.status),
  );
  if (open.length === 0) return 'nothing-open';

  const data = await adminGraphQL<{
    fulfillmentCreate: { fulfillment: { id: string } | null; userErrors: Array<{ message: string }> };
  }>(
    `mutation Ship($fulfillment: FulfillmentInput!) {
      fulfillmentCreate(fulfillment: $fulfillment) { fulfillment { id } userErrors { field message } }
    }`,
    {
      fulfillment: {
        lineItemsByFulfillmentOrder: open.map((o) => ({ fulfillmentOrderId: o.id })),
        trackingInfo: { number: input.trackingNumber, company: input.carrier },
        notifyCustomer: true,
      },
    },
  );
  const errors = data.fulfillmentCreate.userErrors;
  if (errors.length) {
    throw new HttpsError('failed-precondition', `The store refused the shipment: ${errors.map((e) => e.message).join('; ')}`);
  }
  return 'created';
}
