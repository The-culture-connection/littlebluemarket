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
  });

  return 'recorded';
}
