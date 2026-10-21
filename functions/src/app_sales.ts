import { getFirestore, type Timestamp } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions';

import { attribute } from './orders.ts';
import { adminGraphQL } from './shopify/token.ts';

/**
 * The admin page's "App sales" card: how many paid purchases were made in
 * the app, and what they were worth (Grace, 2026-10-21).
 *
 * Every stored order is a paid one, because only `orders/paid` is
 * registered. What a stored order did not say until now is which front door
 * it came through, and `buyerUid` cannot tell, because a website order is
 * matched to an account by email as well. So `normalizeOrder` now records
 * `source`, and orders stored before that are sorted here, once, by asking
 * Shopify whether the checkout carried the app's `app_uid` attribute.
 *
 * Money is integer cents throughout, like every other money figure.
 */

export type SalesSource = 'app' | 'website' | 'unknown';

/** Ids per call: the most one Admin `nodes` query accepts. */
export const SORT_PAGE = 250;

/**
 * Statuses that mean the money went back. Stored orders are almost always
 * `paid` or `fulfilled`, but a sale that was undone is not a sale.
 */
const UNDONE = new Set(['refunded', 'voided', 'cancelled']);

export interface SalesLine {
  unitPriceCents?: number;
  quantity?: number;
  donation?: boolean;
}

export interface SalesOrder {
  source?: string;
  placedAt: Date | null;
  status?: string;
  lines?: SalesLine[];
}

export interface GoodsTotals {
  /** Orders with at least one thing bought from a maker. A gift alone is not a purchase. */
  orders: number;
  itemsSold: number;
  goodsCents: number;
}

export interface AppTotals extends GoodsTotals {
  /** Round-ups and chip-ins: gifts to Little Blue Market, not sales. */
  giftsCents: number;
}

export interface MonthTotals extends AppTotals {
  /** UTC month, `YYYY-MM`. */
  month: string;
}

export interface SalesSummary {
  app: AppTotals;
  website: GoodsTotals;
  thisMonth: MonthTotals;
  last30Days: AppTotals;
  /** The last six months for app orders, newest first, this month included. */
  months: MonthTotals[];
  /** Orders Shopify could not tell us about, so neither side counts them. */
  unknownOrders: number;
  /** Orders not yet sorted into app or website. */
  unsorted: number;
  /** Refunded, voided or cancelled orders left out of every figure. */
  excluded: number;
}

const DAY_MS = 24 * 60 * 60 * 1000;

function empty(): AppTotals {
  return { orders: 0, itemsSold: 0, goodsCents: 0, giftsCents: 0 };
}

/** `YYYY-MM` in UTC, so a month means the same thing wherever it is read. */
export function monthKey(date: Date): string {
  return `${date.getUTCFullYear()}-${String(date.getUTCMonth() + 1).padStart(2, '0')}`;
}

/** What one order adds: goods from makers, and gifts, kept apart. */
export function orderFigures(lines: SalesLine[] | undefined): AppTotals {
  const totals = empty();
  for (const line of lines ?? []) {
    const quantity = Number(line.quantity ?? 0);
    const cents = Math.round(Number(line.unitPriceCents ?? 0)) * quantity;
    if (line.donation) {
      totals.giftsCents += cents;
    } else {
      totals.itemsSold += quantity;
      totals.goodsCents += cents;
    }
  }
  totals.orders = (lines ?? []).some((l) => !l.donation) ? 1 : 0;
  return totals;
}

function add(into: AppTotals, figures: AppTotals): void {
  into.orders += figures.orders;
  into.itemsSold += figures.itemsSold;
  into.goodsCents += figures.goodsCents;
  into.giftsCents += figures.giftsCents;
}

/** The whole card, from the stored orders. Pure, so it is tested without Firestore. */
export function summariseSales(orders: SalesOrder[], now: Date): SalesSummary {
  const app = empty();
  const website = empty();
  const last30Days = empty();
  const thisMonthKey = monthKey(now);
  const since = now.getTime() - 30 * DAY_MS;

  const months: MonthTotals[] = [];
  for (let back = 0; back < 6; back++) {
    const first = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() - back, 1));
    months.push({ month: monthKey(first), ...empty() });
  }
  const byMonth = new Map(months.map((m) => [m.month, m]));

  let unknownOrders = 0;
  let unsorted = 0;
  let excluded = 0;

  for (const order of orders) {
    if (UNDONE.has(String(order.status ?? '').toLowerCase())) {
      excluded++;
      continue;
    }
    if (order.source === 'unknown') {
      unknownOrders++;
      continue;
    }
    if (order.source !== 'app' && order.source !== 'website') {
      unsorted++;
      continue;
    }
    const figures = orderFigures(order.lines);
    if (order.source === 'website') {
      add(website, figures);
      continue;
    }
    add(app, figures);
    if (!order.placedAt) continue;
    const month = byMonth.get(monthKey(order.placedAt));
    if (month) add(month, figures);
    const at = order.placedAt.getTime();
    if (at >= since && at <= now.getTime()) add(last30Days, figures);
  }

  return {
    app,
    // Goods only: a gift made on the website is not what this compares.
    website: {
      orders: website.orders,
      itemsSold: website.itemsSold,
      goodsCents: website.goodsCents,
    },
    thisMonth: byMonth.get(thisMonthKey) ?? { month: thisMonthKey, ...empty() },
    last30Days,
    months,
    unknownOrders,
    unsorted,
    excluded,
  };
}

interface OrderNode {
  id?: string;
  customAttributes?: Array<{ key?: string; value?: string }>;
}

/**
 * What Shopify's answer says about each order asked about, in the order
 * asked. A null node is an order Shopify will not show us: deleted, or older
 * than 60 days without the read_all_orders scope. It is `unknown` rather
 * than a guess, because a guess would move it into one total or the other.
 */
export function sourcesFromNodes(
  ids: string[],
  nodes: Array<OrderNode | null>,
): Map<string, SalesSource> {
  if (nodes.length !== ids.length) {
    throw new Error(`Shopify answered ${nodes.length} orders for ${ids.length} asked about.`);
  }
  const out = new Map<string, SalesSource>();
  ids.forEach((id, i) => {
    const node = nodes[i];
    if (!node) {
      out.set(id, 'unknown');
      return;
    }
    out.set(id, attribute(node.customAttributes, 'app_uid') ? 'app' : 'website');
  });
  return out;
}

export interface AppSalesResult extends SalesSummary {
  asOf: string;
  /** Older orders sorted into app or website on this call. */
  sortedNow: number;
  /** Why older orders could not be sorted this time, in Shopify's words. */
  sortError: string | null;
}

export async function appSales(now = new Date()): Promise<AppSalesResult> {
  const db = getFirestore();
  const snapshot = await db
    .collection('orders')
    .select('source', 'placedAt', 'lines', 'totalCents', 'status')
    .get();

  const orders = new Map<string, SalesOrder>();
  for (const doc of snapshot.docs) {
    const data = doc.data();
    const placedAt = (data.placedAt as Timestamp | undefined)?.toDate?.() ?? null;
    orders.set(doc.id, {
      source: typeof data.source === 'string' ? data.source : undefined,
      placedAt,
      status: typeof data.status === 'string' ? data.status : undefined,
      lines: Array.isArray(data.lines) ? (data.lines as SalesLine[]) : [],
    });
  }

  // One page of the older, unsorted orders per call, so a call stays well
  // inside the 70 seconds the page waits. Pressing Refresh again sorts the
  // next page, and a sorted order is never asked about twice.
  const ids = [...orders.entries()]
    .filter(([id, o]) => !o.source && /^\d+$/.test(id))
    .map(([id]) => id)
    .slice(0, SORT_PAGE);

  let sortedNow = 0;
  let sortError: string | null = null;
  if (ids.length) {
    try {
      const data = await adminGraphQL<{ nodes: Array<OrderNode | null> }>(
        `query OrderSource($ids: [ID!]!) {
          nodes(ids: $ids) { ... on Order { id customAttributes { key value } } }
        }`,
        { ids: ids.map((id) => `gid://shopify/Order/${id}`) },
      );
      const sources = sourcesFromNodes(ids, data.nodes ?? []);
      const batch = db.batch();
      for (const [id, source] of sources) {
        batch.update(db.collection('orders').doc(id), { source });
        const order = orders.get(id);
        if (order) order.source = source;
      }
      await batch.commit();
      sortedNow = sources.size;
    } catch (error) {
      // Nothing is stamped on a failure: an order wrongly marked is
      // counted wrongly forever, an unsorted one is just asked about again.
      sortError = error instanceof Error ? error.message : String(error);
      for (const id of ids) {
        const order = orders.get(id);
        if (order) order.source = undefined;
      }
      logger.error('App sales: could not sort older orders', { asked: ids.length, error: sortError });
    }
  }

  const summary = summariseSales([...orders.values()], now);
  logger.info('App sales', {
    orders: snapshot.size,
    appOrders: summary.app.orders,
    sortedNow,
    unsorted: summary.unsorted,
    unknown: summary.unknownOrders,
  });
  return { ...summary, asOf: now.toISOString(), sortedNow, sortError };
}
