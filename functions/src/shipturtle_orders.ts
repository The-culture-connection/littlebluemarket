import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions';

import { SHIPTURTLE_API_KEY, SHIPTURTLE_AUTH_HEADER, SHIPTURTLE_BASE_URL } from './config.ts';
import { recordFulfillment } from './orders.ts';
import { normalizeVendorName } from './sellers.ts';
import { mapShipmentState } from './shipturtle.ts';
import { authHeaders } from './shipturtle_api.ts';

/**
 * Shipturtle's orders, pulled.
 *
 * Their merchant API has no fulfilment *push* and no payout endpoint, but
 * `GET /api/v1/orders` lists every per-vendor sub-order with the courier's
 * tracking code, the tracking status, and the reconciliation state of the
 * vendor's payment. So the app pulls: a vendor who ships from the Shipturtle
 * dashboard shows up on the buyer's Receiving tab within a sync, and the
 * seller's sales card can say whether Shipturtle has settled with them —
 * as Shipturtle's own words, never a figure computed here.
 */

export interface ShipturtleOrder {
  id: number;
  order_id: number | string;
  name?: string;
  company_id?: number | string;
  unique_name?: string;
  tracking_code?: string | null;
  tracking_link?: string | null;
  tracking_status?: string | null;
  shipping_provider?: string | null;
  awb_custom_courier_name?: string | null;
  status?: string | null;
  payment_reconciliation_status?: string | null;
  credited?: number | string | null;
  total_amount_including_taxes?: number | string | null;
  updated_at?: string;
}

export interface VendorShipment {
  orderId: string;
  companyId: string;
  vendorName: string;
  trackingNumber: string;
  trackingUrl: string | null;
  carrier: string;
  state: string;
  shipturtleStatus: string;
  payoutStatus: string;
  credited: boolean;
}

/** The vendor string Shipturtle bakes into `unique_name`: "#1001_Vendor_physical". */
export function vendorFromUniqueName(uniqueName: string | undefined): string {
  if (!uniqueName) return '';
  const parts = uniqueName.split('_');
  if (parts.length < 3) return '';
  return parts.slice(1, -1).join('_').trim();
}

/** Pure: one Shipturtle sub-order → what the app records, or null without tracking. */
export function shipmentFromOrder(order: ShipturtleOrder): VendorShipment | null {
  const orderId = String(order.order_id ?? '');
  const tracking = String(order.tracking_code ?? '').trim();
  if (!orderId || !tracking) return null;
  return {
    orderId,
    companyId: String(order.company_id ?? ''),
    vendorName: vendorFromUniqueName(order.unique_name),
    trackingNumber: tracking,
    trackingUrl: order.tracking_link ? String(order.tracking_link) : null,
    carrier: String(order.shipping_provider ?? order.awb_custom_courier_name ?? 'Courier'),
    state: mapShipmentState(order.tracking_status),
    shipturtleStatus: String(order.status ?? ''),
    payoutStatus: String(order.payment_reconciliation_status ?? 'pending'),
    credited: String(order.credited ?? '0') !== '0',
  };
}

/** Pure: the per-vendor settlement facts every sub-order carries, tracked or not. */
export function settlementFromOrder(order: ShipturtleOrder): {
  orderId: string;
  companyId: string;
  vendorName: string;
  status: string;
  payoutStatus: string;
  credited: boolean;
  amount: string | null;
} | null {
  const orderId = String(order.order_id ?? '');
  const companyId = String(order.company_id ?? '');
  if (!orderId || !companyId) return null;
  return {
    orderId,
    companyId,
    vendorName: vendorFromUniqueName(order.unique_name),
    status: String(order.status ?? ''),
    payoutStatus: String(order.payment_reconciliation_status ?? 'pending'),
    credited: String(order.credited ?? '0') !== '0',
    amount: order.total_amount_including_taxes == null ? null : String(order.total_amount_including_taxes),
  };
}

function config() {
  let key = '';
  try {
    key = SHIPTURTLE_API_KEY.value();
  } catch {
    key = '';
  }
  return {
    key,
    base: SHIPTURTLE_BASE_URL.value().replace(/\/$/, ''),
    header: SHIPTURTLE_AUTH_HEADER.value() || 'Authorization',
  };
}

/** Every sub-order Shipturtle holds, newest first, up to `max`. */
export async function listShipturtleOrders(
  max = 500,
  fetchImpl: typeof fetch = fetch,
): Promise<ShipturtleOrder[]> {
  const { key, base, header } = config();
  if (!key) return [];
  const out: ShipturtleOrder[] = [];
  for (let page = 1; out.length < max && page <= 20; page++) {
    const res = await fetchImpl(`${base}/api/v1/orders?limit=100&page=${page}`, {
      headers: { Accept: 'application/json', ...authHeaders(key, header) },
    });
    if (!res.ok) {
      logger.warn('Shipturtle orders request failed', { status: res.status, page });
      break;
    }
    const json = (await res.json()) as { data?: ShipturtleOrder[]; count?: number };
    const rows = Array.isArray(json.data) ? json.data : [];
    out.push(...rows);
    if (rows.length < 100) break;
  }
  return out.slice(0, max);
}

/**
 * Applies what Shipturtle knows onto our orders: tracked sub-orders become
 * shipments (idempotent by tracking number), and every sub-order's
 * settlement facts are stored under the order for the seller's sales card.
 */
export async function syncShipturtleOrders(
  fetchImpl: typeof fetch = fetch,
): Promise<{ seen: number; shipments: number; settlements: number }> {
  const orders = await listShipturtleOrders(500, fetchImpl);
  const db = getFirestore();
  let shipments = 0;
  let settlements = 0;

  for (const order of orders) {
    const settlement = settlementFromOrder(order);
    if (settlement) {
      const ref = db.collection('orders').doc(settlement.orderId);
      if ((await ref.get()).exists) {
        // Also keyed by the seller's uid, which is what the app can look up.
        const reserved = settlement.vendorName
          ? (await db.collection('vendorNames').doc(normalizeVendorName(settlement.vendorName)).get()).data()
          : undefined;
        const sellerUid = typeof reserved?.uid === 'string' ? reserved.uid : null;
        if (sellerUid) {
          await ref.set(
            {
              shipturtleBySeller: {
                [sellerUid]: {
                  status: settlement.status,
                  payoutStatus: settlement.payoutStatus,
                  credited: settlement.credited,
                  amount: settlement.amount,
                  syncedAt: FieldValue.serverTimestamp(),
                },
              },
            },
            { merge: true },
          );
        }
        await ref.set(
          {
            shipturtle: {
              [settlement.companyId]: {
                vendorName: settlement.vendorName,
                status: settlement.status,
                payoutStatus: settlement.payoutStatus,
                credited: settlement.credited,
                amount: settlement.amount,
                syncedAt: FieldValue.serverTimestamp(),
              },
            },
          },
          { merge: true },
        );
        settlements += 1;
      }
    }
    const shipment = shipmentFromOrder(order);
    if (shipment) {
      await recordFulfillment(shipment.orderId, {
        trackingNumber: shipment.trackingNumber,
        carrier: shipment.carrier,
        state: shipment.state,
        counterpartyName: shipment.vendorName || undefined,
        verified: true,
      });
      shipments += 1;
    }
  }

  logger.info('Synced Shipturtle orders', { seen: orders.length, shipments, settlements });
  return { seen: orders.length, shipments, settlements };
}
