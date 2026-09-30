import { FieldPath, getFirestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions';
import { HttpsError } from 'firebase-functions/v2/https';

import { removeMirroredProduct } from './catalog.ts';
import { adminGraphQL } from './shopify/token.ts';

/**
 * Retiring mirror rows for products the store no longer has.
 *
 * Why: a product deleted or replaced in Shopify whose delete webhook never
 * reached the app stayed in the mirror forever. It showed in search at $0,
 * and checkout refused it as "not available in the app's shop". The
 * Birdhive's old v-necks were the ones Grace found on 2026-09-30; all 46 of
 * their live products were priced. The catalogue backfill cannot fix this,
 * because it only visits products that still exist.
 *
 * So this walks the mirror instead, a page at a time, and asks the store
 * about every id on the page in one `nodes` query. A null answer means the
 * store has no such product. Nothing is guessed from timestamps, and a
 * product that exists in any status (active, draft, archived) is left alone.
 *
 * `apply: false` counts without writing, for the admin page's Check first.
 */

/** Ids per call: the most one Admin `nodes` query accepts. */
export const SWEEP_PAGE = 250;

export interface SweepPage {
  checked: number;
  leftovers: number;
  removed: number;
  /** A few titles from this page, so Check first shows what it found. */
  samples: string[];
  cursor: string | null;
  done: boolean;
}

/** The mirror ids on a page the store did not recognise. */
export function missingFrom(ids: string[], nodes: Array<{ id?: string } | null>): string[] {
  const found = new Set(
    nodes.filter((n): n is { id: string } => !!n?.id).map((n) => n.id.split('/').pop()),
  );
  return ids.filter((id) => !found.has(id));
}

/**
 * A page on which the store recognised nothing at all is far more likely to
 * be the wrong shop or a broken token than fifty genuine deletions in a row,
 * so it stops the run rather than emptying the Market.
 */
export function pageLooksWrong(asked: number, missing: number): boolean {
  return asked >= 50 && missing === asked;
}

export async function sweepCatalogPage({
  after,
  apply,
}: {
  after: string | null;
  apply: boolean;
}): Promise<SweepPage> {
  const db = getFirestore();
  let query = db.collection('catalog').orderBy(FieldPath.documentId()).limit(SWEEP_PAGE);
  if (after) query = query.startAfter(after);
  const snapshot = await query.get();

  // Already retired rows, and ids that are not store product ids, are not
  // asked about.
  const live = snapshot.docs.filter(
    (doc) => doc.data().status !== 'deleted' && /^\d+$/.test(doc.id),
  );
  const ids = live.map((doc) => doc.id);

  let missing: string[] = [];
  if (ids.length) {
    const data: { nodes: Array<{ id?: string } | null> } = await adminGraphQL(
      `query Exists($ids: [ID!]!) { nodes(ids: $ids) { ... on Product { id } } }`,
      { ids: ids.map((id) => `gid://shopify/Product/${id}`) },
    );
    missing = missingFrom(ids, data.nodes ?? []);
    if (pageLooksWrong(ids.length, missing.length)) {
      logger.error('Catalog sweep stopped: the store recognised none of a page', {
        after,
        asked: ids.length,
      });
      throw new HttpsError(
        'failed-precondition',
        `Shopify did not recognise any of the ${ids.length} products on this page, which ` +
          'points to the wrong shop or a login problem rather than real deletions. ' +
          'Stopped without removing anything.',
      );
    }
  }

  const byId = new Map(live.map((doc) => [doc.id, doc.data()]));
  if (apply) {
    for (const id of missing) await removeMirroredProduct(id);
  }

  const last = snapshot.docs.at(-1)?.id ?? null;
  const done = snapshot.size < SWEEP_PAGE;
  logger.info('Catalog sweep page', {
    apply,
    checked: ids.length,
    leftovers: missing.length,
    done,
  });
  return {
    checked: ids.length,
    leftovers: missing.length,
    removed: apply ? missing.length : 0,
    samples: missing.slice(0, 5).map((id) => String(byId.get(id)?.title ?? id)),
    cursor: done ? null : last,
    done,
  };
}
