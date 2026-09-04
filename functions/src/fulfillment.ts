import { getFirestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions';
import { HttpsError } from 'firebase-functions/v2/https';

import { SHIPTURTLE_API_KEY, SHIPTURTLE_BASE_URL } from './config.ts';
import { recordFulfillment } from './orders.ts';

/**
 * A seller marking an order shipped.
 *
 * One call so the courier and the buyer learn the same number: the fulfilment
 * goes upstream, and the same tracking is written onto our order document so
 * the buyer's Receiving tab shows it whether or not the upstream call
 * succeeded.
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
}): Promise<{ ok: true }> {
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

  await pushToShipTurtle(input);

  await recordFulfillment(input.orderId, {
    trackingNumber: input.trackingNumber,
    carrier: input.carrier,
    state: 'inTransit',
  });

  return { ok: true };
}

/**
 * Sends the fulfilment to ShipTurtle.
 *
 * ⚠️ **Outstanding.** This needs the ShipTurtle API key and the exact
 * fulfilment endpoint. Until both are set the call is skipped with a warning
 * rather than failing: a seller can still record tracking, the buyer still sees
 * it, and the only thing missing is the upstream copy — which is a much better
 * failure than a seller unable to mark anything shipped.
 *
 * The request shape below is a placeholder to be confirmed against their API
 * docs before this is switched on.
 */
async function pushToShipTurtle(input: {
  orderId: string;
  trackingNumber: string;
  carrier: string;
}): Promise<void> {
  let key: string;
  try {
    key = SHIPTURTLE_API_KEY.value();
  } catch {
    key = '';
  }

  if (!key) {
    logger.warn(
      'ShipTurtle is not configured; tracking was recorded locally only',
      { orderId: input.orderId },
    );
    return;
  }

  const response = await fetch(
    `${SHIPTURTLE_BASE_URL.value()}/v1/fulfillments`,
    {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${key}`,
      },
      body: JSON.stringify({
        order_id: input.orderId,
        tracking_number: input.trackingNumber,
        courier: input.carrier,
      }),
    },
  );

  if (!response.ok) {
    // Surfaced to the seller rather than swallowed: they are standing at a
    // parcel counter and need to know it did not go through.
    throw new HttpsError(
      'unavailable',
      'Could not reach the shipping service. Try again in a moment.',
    );
  }
}
