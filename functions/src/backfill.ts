import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions';

import { mirrorProduct, productFromGraphQL, type GraphQLProduct } from './catalog.ts';
import { adminGraphQL } from './shopify/token.ts';

/**
 * The one-time catalog import, in resumable pages.
 *
 * The plan sketched a bulk operation; cursor pages do the same job with far
 * less machinery, because each call handles a bounded slice and hands back a
 * cursor. The app (or the doctor) keeps calling until `done`. Progress lives
 * in `_internal/catalogBackfill`, so an interrupted run resumes from where
 * it stopped rather than starting over — and a second full run is a no-op
 * on content, because the mirror writes are `merge`.
 */

export const PROGRESS_DOC = '_internal/catalogBackfill';

/** Products per call. Two Admin pages of 50, comfortably inside a timeout. */
export const PAGE = 50;
export const PAGES_PER_CALL = 2;

export interface BackfillResult {
  processed: number;
  total: number;
  nextCursor: string | null;
  done: boolean;
}

const QUERY = `
  query Products($after: String, $first: Int!) {
    products(first: $first, after: $after, sortKey: ID) {
      pageInfo { hasNextPage endCursor }
      nodes {
        id title descriptionHtml vendor productType tags status createdAt
        images(first: 20) { nodes { url } }
        variants(first: 100) { nodes { id title price availableForSale inventoryQuantity } }
        collections(first: 50) { nodes { handle } }
      }
    }
  }
`;

export async function backfillCatalogPage(
  cursor: string | null,
  { reset = false }: { reset?: boolean } = {},
): Promise<BackfillResult> {
  const db = getFirestore();
  const progressRef = db.doc(PROGRESS_DOC);
  const stored = reset ? {} : ((await progressRef.get()).data() ?? {});
  // A finished run has nothing to resume: the next call starts over, and
  // counts from zero rather than on top of the last run.
  const progress = stored.done === true && !cursor ? {} : stored;

  let after: string | null = cursor ?? (progress.nextCursor as string | null) ?? null;
  let total = Number(progress.total ?? 0);
  let processed = 0;
  let done = false;

  for (let page = 0; page < PAGES_PER_CALL; page++) {
    const data: {
      products: {
        pageInfo: { hasNextPage: boolean; endCursor: string | null };
        nodes: GraphQLProduct[];
      };
    } = await adminGraphQL(QUERY, { after, first: PAGE });

    for (const node of data.products.nodes) {
      await mirrorProduct(productFromGraphQL(node));
      processed += 1;
    }
    total += data.products.nodes.length;

    if (!data.products.pageInfo.hasNextPage) {
      done = true;
      after = null;
      break;
    }
    after = data.products.pageInfo.endCursor;
  }

  await progressRef.set(
    {
      nextCursor: after,
      total,
      done,
      updatedAt: FieldValue.serverTimestamp(),
      ...(done ? { completedAt: FieldValue.serverTimestamp() } : {}),
    },
    { merge: true },
  );

  logger.info('Catalog backfill page', { processed, total, done });
  return { processed, total, nextCursor: after, done };
}
