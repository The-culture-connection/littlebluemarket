import { FieldValue, getFirestore, Timestamp } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions';

import { adminGraphQL } from './shopify/token.ts';

/**
 * The weekly stock check (Grace, 2026-10-05: "just making sure the
 * inventory was updated").
 *
 * Stock already arrives within seconds: Shipturtle updates Shopify, and
 * Shopify's `products/update` webhook re-mirrors the product. This is the
 * safety net under that. Once a week it reads every variant's stock from the
 * store and corrects any the mirror has wrong, so a webhook that never
 * arrived costs at most a week of a wrong "in stock", not forever.
 *
 * It touches stock only: `availableForSale` and `quantityAvailable` on
 * `catalog/{id}/spec/detail`. Titles, prices and photos stay the webhook's
 * and the backfill's business.
 *
 * Sixteen thousand products do not fit in one run, so it is resumable like
 * the backfills (see `backfill.ts`): a run works for a few minutes, saves
 * its cursor in `_internal/weeklyStockCheck`, and the next quarter-hour tick
 * carries on. A new pass starts when the last one started a week ago. The
 * counts at the end of a pass are in that document and in the log.
 */

export const STOCK_CHECK_DOC = '_internal/weeklyStockCheck';

export const WEEK_MS = 7 * 24 * 60 * 60 * 1000;

/** Variants per store call: the most one connection page returns. */
export const VARIANT_PAGE = 250;

/** Time a run works before saving and leaving the rest to the next tick. */
export const RUN_BUDGET_MS = 6 * 60 * 1000;

export interface StoreVariant {
  /** The bare numeric id, as the mirror stores `variantId`. */
  variantId: string;
  productId: string;
  availableForSale: boolean;
  quantityAvailable: number | null;
}

export interface StockCheckState {
  active?: boolean;
  cursor?: string | null;
  lastStartedAt?: Timestamp | null;
}

/** Whether a new pass should begin. Pure. */
export function passDue(state: StockCheckState | undefined, now: number): boolean {
  if (state?.active) return false;
  const last = state?.lastStartedAt?.toMillis?.() ?? 0;
  return now - last >= WEEK_MS;
}

/**
 * The stored variants with the store's stock written over them, and how
 * many changed. Pure. A variant the store did not mention this page is left
 * exactly as it was.
 */
export function correctedVariants(
  stored: Array<Record<string, unknown>>,
  store: StoreVariant[],
): { variants: Array<Record<string, unknown>>; changed: number } {
  const byId = new Map(store.map((v) => [v.variantId, v]));
  let changed = 0;
  const variants = stored.map((variant) => {
    const fresh = byId.get(String(variant.variantId ?? ''));
    if (!fresh) return variant;
    if (
      variant.availableForSale === fresh.availableForSale &&
      (variant.quantityAvailable ?? null) === fresh.quantityAvailable
    ) {
      return variant;
    }
    changed += 1;
    return {
      ...variant,
      availableForSale: fresh.availableForSale,
      quantityAvailable: fresh.quantityAvailable,
    };
  });
  return { variants, changed };
}

const tail = (gid: string) => gid.split('/').pop() ?? gid;

const QUERY = `
  query Stock($after: String, $first: Int!) {
    productVariants(first: $first, after: $after, sortKey: ID) {
      pageInfo { hasNextPage endCursor }
      nodes { id availableForSale inventoryQuantity product { id } }
    }
  }
`;

interface StockPage {
  productVariants: {
    pageInfo: { hasNextPage: boolean; endCursor: string | null };
    nodes: Array<{
      id: string;
      availableForSale: boolean;
      inventoryQuantity: number | null;
      product: { id: string };
    }>;
  };
}

/** One page, waiting out Shopify's rate limit rather than failing on it. */
async function fetchPage(after: string | null): Promise<StockPage> {
  for (let attempt = 1; ; attempt++) {
    try {
      return await adminGraphQL<StockPage>(QUERY, { after, first: VARIANT_PAGE });
    } catch (error) {
      if (attempt >= 5 || !/throttled/i.test(String(error))) throw error;
      await new Promise((resolve) => setTimeout(resolve, 2000 * attempt));
    }
  }
}

export interface StockCheckRun {
  started: boolean;
  pages: number;
  done: boolean;
}

export async function runStockCheck(now = Date.now()): Promise<StockCheckRun | null> {
  const db = getFirestore();
  const stateRef = db.doc(STOCK_CHECK_DOC);
  const state = (await stateRef.get()).data() as StockCheckState | undefined;

  const starting = passDue(state, now);
  if (!state?.active && !starting) return null;

  if (starting) {
    await stateRef.set({
      active: true,
      cursor: null,
      lastStartedAt: Timestamp.fromMillis(now),
      variantsChecked: 0,
      variantsCorrected: 0,
      productsCorrected: 0,
      notInApp: 0,
      completedAt: null,
    });
    logger.info('Weekly stock check: a new pass has started');
  }

  let after: string | null = starting ? null : (state?.cursor ?? null);
  let pages = 0;
  let done = false;

  while (Date.now() - now < RUN_BUDGET_MS) {
    const data = await fetchPage(after);
    const nodes = data.productVariants.nodes;

    const byProduct = new Map<string, StoreVariant[]>();
    for (const node of nodes) {
      const productId = tail(node.product.id);
      const list = byProduct.get(productId) ?? [];
      list.push({
        variantId: tail(node.id),
        productId,
        availableForSale: node.availableForSale,
        quantityAvailable: typeof node.inventoryQuantity === 'number' ? node.inventoryQuantity : null,
      });
      byProduct.set(productId, list);
    }

    const ids = [...byProduct.keys()];
    const specs = ids.length
      ? await db.getAll(...ids.map((id) => db.doc(`catalog/${id}/spec/detail`)))
      : [];

    const batch = db.batch();
    let variantsCorrected = 0;
    let productsCorrected = 0;
    let notInApp = 0;
    specs.forEach((spec, i) => {
      if (!spec.exists) {
        notInApp += 1;
        return;
      }
      const stored = (spec.data()?.variants ?? []) as Array<Record<string, unknown>>;
      const { variants, changed } = correctedVariants(stored, byProduct.get(ids[i]!)!);
      if (!changed) return;
      variantsCorrected += changed;
      productsCorrected += 1;
      batch.set(spec.ref, { variants }, { merge: true });
    });

    after = data.productVariants.pageInfo.endCursor;
    done = !data.productVariants.pageInfo.hasNextPage;
    batch.set(
      stateRef,
      {
        cursor: done ? null : after,
        active: !done,
        variantsChecked: FieldValue.increment(nodes.length),
        variantsCorrected: FieldValue.increment(variantsCorrected),
        productsCorrected: FieldValue.increment(productsCorrected),
        notInApp: FieldValue.increment(notInApp),
        ...(done ? { completedAt: FieldValue.serverTimestamp() } : {}),
      },
      { merge: true },
    );
    await batch.commit();
    pages += 1;
    if (done) break;
  }

  if (done) {
    const totals = (await stateRef.get()).data();
    logger.info('Weekly stock check: pass finished', {
      variantsChecked: totals?.variantsChecked,
      variantsCorrected: totals?.variantsCorrected,
      productsCorrected: totals?.productsCorrected,
      notInApp: totals?.notInApp,
    });
  } else {
    logger.info('Weekly stock check: saved, carrying on next run', { pages });
  }
  return { started: starting, pages, done };
}
