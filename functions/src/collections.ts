import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions';

import { adminGraphQL } from './shopify/token.ts';

/**
 * The store's collections, mirrored.
 *
 * Collections are the real taxonomy of the store — `Adult Apparel`, `Bath,
 * Beauty & Wellness`, and the identity ones (`BIPOC Owned`, `Woman Owned`,
 * `Ally Owned`) that the app renders as initiatives. `product_type` is
 * literally "physical" across the live store, so it categorises nothing.
 *
 * Mirrored by handle, so a product's `collectionHandles` and a collection
 * document join without an id lookup.
 */

export interface CollectionDoc {
  id: string;
  handle: string;
  title: string;
  imageUrl: string | null;
  productCount: number;
}

interface CollectionNode {
  id: string;
  handle: string;
  title: string;
  image: { url: string } | null;
  productsCount: { count: number } | null;
}

export function collectionDocFor(node: CollectionNode): CollectionDoc {
  return {
    id: node.id.split('/').pop() ?? node.id,
    handle: node.handle,
    title: node.title,
    imageUrl: node.image?.url ?? null,
    productCount: node.productsCount?.count ?? 0,
  };
}

/** Every collection on the store, paginated. */
export async function fetchCollections(): Promise<CollectionDoc[]> {
  const out: CollectionDoc[] = [];
  let after: string | null = null;
  for (;;) {
    const data: {
      collections: {
        pageInfo: { hasNextPage: boolean; endCursor: string | null };
        nodes: CollectionNode[];
      };
    } = await adminGraphQL(
      `query Collections($after: String) {
        collections(first: 250, after: $after) {
          pageInfo { hasNextPage endCursor }
          nodes { id handle title image { url } productsCount { count } }
        }
      }`,
      { after },
    );
    out.push(...data.collections.nodes.map(collectionDocFor));
    if (!data.collections.pageInfo.hasNextPage) break;
    after = data.collections.pageInfo.endCursor;
  }
  return out;
}

/** Writes `collections/{handle}` for every collection; returns the count. */
export async function syncCollections(): Promise<number> {
  const docs = await fetchCollections();
  const db = getFirestore();
  for (let i = 0; i < docs.length; i += 400) {
    const batch = db.batch();
    for (const doc of docs.slice(i, i + 400)) {
      batch.set(
        db.collection('collections').doc(doc.handle),
        { ...doc, updatedAt: FieldValue.serverTimestamp() },
        { merge: true },
      );
    }
    await batch.commit();
  }
  logger.info('Synced collections', { count: docs.length });
  return docs.length;
}

/**
 * The collection handles one product belongs to. Product webhooks do not
 * carry collections, so the mirror asks once per update.
 */
export async function productCollectionHandles(productId: string): Promise<string[]> {
  const data: {
    product: { collections: { nodes: Array<{ handle: string }> } } | null;
  } = await adminGraphQL(
    `query ProductCollections($id: ID!) {
      product(id: $id) { collections(first: 50) { nodes { handle } } }
    }`,
    { id: `gid://shopify/Product/${productId}` },
  );
  return data.product?.collections.nodes.map((n) => n.handle) ?? [];
}
