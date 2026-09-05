import * as crypto from 'node:crypto';

import { logger } from 'firebase-functions';

import { recordFulfillment } from './orders.ts';

/**
 * ShipTurtle's side of fulfilment.
 *
 * It is the system that breaks a multi-vendor order into per-vendor shipments,
 * so it is where a tracking number usually appears first — a vendor who ships
 * from their own dashboard never touches our app. This endpoint is what keeps
 * the buyer's Receiving tab honest in that case.
 *
 * ⚠️ **The payload shape below is a best guess and must be checked against
 * their webhook docs before this is switched on.** It is written defensively —
 * every field has a fallback and nothing assumes a shape — so a mismatch shows
 * up as an ignored webhook in the logs rather than a crash, but "ignored" is
 * still wrong. The signature scheme in particular needs confirming: if
 * ShipTurtle signs differently, [verifyShipTurtleSignature] is what changes.
 */

/** Their delivery states, flattened onto ours. */
export function mapShipmentState(value: unknown): string {
  const state = String(value ?? '').toLowerCase();
  if (state.includes('deliver') && !state.includes('out')) return 'delivered';
  if (state.includes('out for delivery')) return 'outForDelivery';
  if (state.includes('transit') || state.includes('shipped')) return 'inTransit';
  return 'labelCreated';
}

/**
 * Whether a ShipTurtle webhook is genuine.
 *
 * Same reasoning as the Shopify one: this is a public URL that writes to order
 * documents, so an unverified endpoint lets anyone mark anything shipped.
 * Timing-safe, and over the raw bytes.
 */
export function verifyShipTurtleSignature(
  rawBody: Buffer | string,
  signature: string | undefined,
  secret: string | undefined,
): boolean {
  if (!signature || !secret) return false;

  const body = Buffer.isBuffer(rawBody) ? rawBody : Buffer.from(rawBody, 'utf8');
  const expected = crypto
    .createHmac('sha256', secret)
    .update(body)
    .digest('hex');

  const a = crypto.createHash('sha256').update(expected).digest();
  const b = crypto.createHash('sha256').update(signature).digest();
  return crypto.timingSafeEqual(a, b);
}

/**
 * Records a shipment reported by ShipTurtle.
 *
 * Idempotent through [recordFulfillment], which keys shipments by tracking
 * number — so a status update replaces its shipment rather than appending a
 * second copy of the same parcel.
 */
export async function handleShipTurtleWebhook(
  payload: Record<string, any>,
  verified = true,
): Promise<'recorded' | 'ignored'> {
  const orderId = String(
    payload.order_id ?? payload.marketplace_order_id ?? payload.orderId ?? '',
  );
  const tracking = String(
    payload.tracking_number ?? payload.trackingNumber ?? '',
  );

  if (!orderId || !tracking) {
    // Not an error: ShipTurtle sends events we do not act on. Logged so a
    // payload-shape mismatch is visible rather than silent.
    logger.info('Ignoring a ShipTurtle event with no order or tracking', {
      keys: Object.keys(payload),
    });
    return 'ignored';
  }

  await recordFulfillment(orderId, {
    trackingNumber: tracking,
    carrier: String(payload.courier ?? payload.carrier ?? 'Other'),
    state: mapShipmentState(payload.status ?? payload.shipment_status),
    counterpartyName: payload.vendor_name
      ? String(payload.vendor_name)
      : undefined,
    verified,
  });

  return 'recorded';
}

/**
 * Header names that look like they carry a signature.
 *
 * Deliberately broad. `x-shipturtle-signature` is a *guess* — nobody has seen a
 * real ShipTurtle webhook yet — so this matches anything plausible and reports
 * what it found. Live traffic is what tells us the real name.
 */
function signatureHeaders(
  headers: Record<string, string | string[] | undefined>,
): Array<{ name: string; value: string }> {
  const found: Array<{ name: string; value: string }> = [];
  for (const [name, raw] of Object.entries(headers)) {
    const lower = name.toLowerCase();
    if (!lower.startsWith('x-')) continue;
    if (
      !lower.startsWith('x-shipturtle') &&
      !/sign|hmac|digest|secret|token/.test(lower)
    ) {
      continue;
    }
    const value = Array.isArray(raw) ? raw[0] : raw;
    if (value) found.push({ name: lower, value });
  }
  return found;
}

/** The outcome of authenticating a ShipTurtle webhook. */
export type ShipTurtleAuth =
  | {
      ok: true;
      /** False when we accepted a request we could not actually verify. */
      verified: boolean;
      /** Set only when the caller must shout: they sign, and we are not checking. */
      alarm?: string;
      /** Signature-ish header *names* seen. Never values — those are credentials. */
      sawHeaders: string[];
    }
  | { ok: false; reason: string };

/**
 * Whether to act on a ShipTurtle webhook, and how loudly to complain about it.
 *
 * ShipTurtle's "Register webhook" dialog asks only for a topic and a URL — it
 * offers no signing secret and reveals none afterwards — so we cannot assume one
 * exists. Failing closed on a secret that may not be obtainable would mean this
 * endpoint rejects 100% of traffic forever, and vendor-side shipments would
 * never reach the app at all.
 *
 * So: **an unset secret accepts, and says so.** The important case is the third
 * one. If a signature header arrives while we hold no secret, that is proof a
 * secret exists somewhere in their settings — and the alarm carries the exact
 * command to fix it. Real traffic answers the question no documentation has.
 *
 * ⚠️ This accepts unverified writes to order documents. The blast radius is a
 * forged shipment — a wrong tracking number, a Receiving tab showing a parcel
 * that does not exist. It cannot move money, create products or grant seller
 * status. That is a dev-project trade, not a production one; see the
 * `TODO(prod)` at the call site.
 */
export function authenticateShipTurtleWebhook(
  rawBody: Buffer | string,
  headers: Record<string, string | string[] | undefined>,
  secret: string | undefined,
): ShipTurtleAuth {
  const candidates = signatureHeaders(headers);
  const sawHeaders = candidates.map((h) => h.name);

  if (secret) {
    const signed = candidates.some((h) =>
      verifyShipTurtleSignature(rawBody, h.value, secret),
    );
    return signed
      ? { ok: true, verified: true, sawHeaders }
      : { ok: false, reason: 'bad signature' };
  }

  if (candidates.length > 0) {
    return {
      ok: true,
      verified: false,
      sawHeaders,
      alarm:
        'SHIPTURTLE SIGNS ITS WEBHOOKS AND WE ARE NOT VERIFYING THEM. ' +
        `A signature header (${sawHeaders.join(', ')}) arrived but ` +
        'SHIPTURTLE_WEBHOOK_SECRET is empty, so this endpoint is accepting ' +
        'unverified writes to order documents — anyone who guesses this URL ' +
        'can mark any order shipped. Find the secret in ShipTurtle ' +
        '(Settings -> API Integration, or the webhook list after creating one), then: ' +
        'firebase functions:secrets:set SHIPTURTLE_WEBHOOK_SECRET --project dev',
    };
  }

  return { ok: true, verified: false, sawHeaders };
}
