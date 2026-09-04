import { initializeApp } from 'firebase-admin/app';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions';
import { onRequest } from 'firebase-functions/v2/https';
import { HttpsError, onCall } from 'firebase-functions/v2/https';

import {
  ALL_SECRETS,
  SHOPIFY_CLIENT_SECRET,
  SHOPIFY_STOREFRONT_PRIVATE_TOKEN,
  SHOPIFY_WEBHOOK_SECRET,
  SHIPTURTLE_WEBHOOK_SECRET,
} from './config.ts';
import { mirrorProduct, removeMirroredProduct } from './catalog.ts';
import {
  addLine,
  beginCheckout,
  clearCart,
  liveVariants,
  removeLine,
  updateLine,
} from './cart.ts';
import { normalizeOrder, recordFulfillment, recordPaidOrder } from './orders.ts';
import { addTracking } from './fulfillment.ts';
import { linkStoreAccounts } from './linking.ts';
import { verifyShopifyHmac, webhookHmacHeader, webhookTopic } from './webhooks.ts';
import {
  handleShipTurtleWebhook,
  verifyShipTurtleSignature,
} from './shipturtle.ts';

initializeApp();

/** Every callable needs a real account behind it. */
function requireUid(auth: { uid?: string } | undefined): string {
  const uid = auth?.uid;
  if (!uid) {
    throw new HttpsError('unauthenticated', 'Sign in to do that.');
  }
  return uid;
}

// -------------------------------------------------------------- the commerce
//
// The app holds no storefront credential. These are the only doors, and each
// one knows who is calling from the Firebase ID token rather than from
// anything the client sends.

const commerceOptions = {
  secrets: [SHOPIFY_CLIENT_SECRET, SHOPIFY_STOREFRONT_PRIVATE_TOKEN],
};

export const commerceAddLine = onCall(commerceOptions, async (request) => {
  const uid = requireUid(request.auth);
  const { productId, variantId, quantity } = request.data ?? {};
  if (typeof productId !== 'string') {
    throw new HttpsError('invalid-argument', 'A product is required.');
  }
  // Priced server-side. A client-supplied price is the obvious thing to tamper
  // with, so none is accepted.
  return addLine(uid, {
    productId,
    variantId: typeof variantId === 'string' ? variantId : undefined,
    quantity: Number(quantity ?? 1),
  });
});

export const commerceUpdateLine = onCall(commerceOptions, async (request) => {
  const uid = requireUid(request.auth);
  const { lineId, quantity } = request.data ?? {};
  if (typeof lineId !== 'string') {
    throw new HttpsError('invalid-argument', 'A line is required.');
  }
  return updateLine(uid, lineId, Number(quantity ?? 1));
});

export const commerceRemoveLine = onCall(commerceOptions, async (request) => {
  const uid = requireUid(request.auth);
  const { lineId } = request.data ?? {};
  if (typeof lineId !== 'string') {
    throw new HttpsError('invalid-argument', 'A line is required.');
  }
  return removeLine(uid, lineId);
});

export const commerceClearCart = onCall(commerceOptions, async (request) =>
  clearCart(requireUid(request.auth)),
);

export const commerceBeginCheckout = onCall(
  commerceOptions,
  async (request) => beginCheckout(requireUid(request.auth)),
);

export const commerceLiveVariants = onCall(commerceOptions, async (request) => {
  requireUid(request.auth);
  const { productId } = request.data ?? {};
  if (typeof productId !== 'string') {
    throw new HttpsError('invalid-argument', 'A product is required.');
  }
  return { variants: await liveVariants(productId) };
});

export const fulfillmentAddTracking = onCall(
  { secrets: ALL_SECRETS },
  async (request) => {
    const uid = requireUid(request.auth);
    const { orderId, trackingNumber, carrier } = request.data ?? {};
    if (typeof orderId !== 'string' || typeof trackingNumber !== 'string') {
      throw new HttpsError('invalid-argument', 'An order and a number are required.');
    }
    return addTracking({
      sellerUid: uid,
      orderId,
      trackingNumber,
      carrier: String(carrier ?? 'Other'),
    });
  },
);

// --------------------------------------------------------------- the linking

/**
 * Links a new account to whatever already exists in the store.
 *
 * The security point: the email comes from the verified token claim, never
 * from the request. Accepting a client-supplied address would let anyone type
 * a stranger's email and inherit their order history and revenue.
 */
export const linkAccounts = onCall({ secrets: ALL_SECRETS }, async (request) => {
  const uid = requireUid(request.auth);
  const email = request.auth?.token?.email;
  const verified = request.auth?.token?.email_verified;

  if (typeof email !== 'string' || !verified) {
    throw new HttpsError(
      'failed-precondition',
      'Verify your email before linking your store account.',
    );
  }
  return linkStoreAccounts(uid, email);
});

// -------------------------------------------------------------- the webhooks
//
// A public URL that moves money data, so nothing happens before the signature
// is checked. `onRequest` gives access to the raw body, which is what the HMAC
// is actually over -- a re-serialised JSON body does not match.

export const shopifyWebhook = onRequest(
  { secrets: [SHOPIFY_CLIENT_SECRET, SHOPIFY_WEBHOOK_SECRET] },
  async (request, response) => {
    const raw = request.rawBody;
    const valid = verifyShopifyHmac(raw, webhookHmacHeader(request.headers), [
      // A webhook the app registered is signed with the client secret; one
      // created in the Shopify admin has its own. A store can have both.
      SHOPIFY_CLIENT_SECRET.value(),
      SHOPIFY_WEBHOOK_SECRET.value(),
    ]);

    if (!valid) {
      logger.warn('Rejected a webhook with a bad signature');
      response.status(401).send('bad signature');
      return;
    }

    const topic = webhookTopic(request.headers);
    const payload = JSON.parse(raw.toString('utf8')) as Record<string, any>;

    try {
      switch (topic) {
        case 'orders/paid':
        case 'orders/create': {
          const order = await normalizeOrder(payload);
          const outcome = await recordPaidOrder(order);
          logger.info('Handled an order webhook', { topic, id: order.id, outcome });
          break;
        }

        case 'orders/fulfilled':
        case 'fulfillments/create':
        case 'fulfillments/update': {
          const orderId = String(payload.order_id ?? payload.id);
          await recordFulfillment(orderId, {
            trackingNumber: String(payload.tracking_number ?? ''),
            carrier: String(payload.tracking_company ?? 'Other'),
            state: payload.shipment_status === 'delivered'
              ? 'delivered'
              : 'inTransit',
          });
          break;
        }

        case 'products/create':
        case 'products/update':
          await mirrorProduct(payload);
          break;

        case 'products/delete':
          await removeMirroredProduct(String(payload.id));
          break;

        default:
          logger.debug('Ignoring an unhandled webhook topic', { topic });
      }

      // 200 even for an ignored topic: anything else makes Shopify retry a
      // webhook we have deliberately chosen not to act on.
      response.status(200).send('ok');
    } catch (error) {
      // A 500 asks Shopify to retry, which is right for a transient failure
      // and harmless for a permanent one because the writes are idempotent.
      logger.error('A webhook handler threw', { topic, error });
      response.status(500).send('retry');
    }
  },
);

// ----------------------------------------------------------------- hashtags

/**
 * Keeps the hashtag counts the search screen reads.
 *
 * A counter per tag rather than a count query, because Firestore charges for
 * every document a count reads and this is on the first screen of the app.
 */
export const onPostWritten = require('firebase-functions/v2/firestore').onDocumentWritten(
  'posts/{postId}',
  async (event: any) => {
    const before = event.data?.before?.data() as { tags?: string[] } | undefined;
    const after = event.data?.after?.data() as { tags?: string[] } | undefined;

    const previous = new Set(before?.tags ?? []);
    const next = new Set(after?.tags ?? []);

    const db = getFirestore();
    const batch = db.batch();

    for (const tag of next) {
      if (previous.has(tag)) continue;
      batch.set(
        db.collection('hashtags').doc(tag.replace(/^#/, '')),
        { tag, postCount: FieldValue.increment(1) },
        { merge: true },
      );
    }
    for (const tag of previous) {
      if (next.has(tag)) continue;
      batch.set(
        db.collection('hashtags').doc(tag.replace(/^#/, '')),
        { tag, postCount: FieldValue.increment(-1) },
        { merge: true },
      );
    }
    await batch.commit();
  },
);

/**
 * ShipTurtle's fulfilment webhook.
 *
 * A vendor who ships from their own ShipTurtle dashboard never touches this
 * app, so this is how the buyer's Receiving tab learns their parcel moved.
 */
export const shipturtleWebhook = onRequest(
  { secrets: [SHIPTURTLE_WEBHOOK_SECRET] },
  async (request, response) => {
    const raw = request.rawBody;
    const signature = request.get('x-shipturtle-signature');

    let secret: string | undefined;
    try {
      secret = SHIPTURTLE_WEBHOOK_SECRET.value();
    } catch {
      secret = undefined;
    }

    if (!verifyShipTurtleSignature(raw, signature, secret)) {
      // Same reasoning as the Shopify endpoint: a public URL that writes to
      // order documents cannot take an unverified request.
      logger.warn('Rejected a ShipTurtle webhook with a bad signature');
      response.status(401).send('bad signature');
      return;
    }

    try {
      const payload = JSON.parse(raw.toString('utf8')) as Record<string, any>;
      const outcome = await handleShipTurtleWebhook(payload);
      logger.info('Handled a ShipTurtle webhook', { outcome });
      response.status(200).send('ok');
    } catch (error) {
      logger.error('A ShipTurtle webhook handler threw', { error });
      response.status(500).send('retry');
    }
  },
);
