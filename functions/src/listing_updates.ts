import { randomUUID } from 'node:crypto';

import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions';
import { HttpsError } from 'firebase-functions/v2/https';

import {
  collectionIdsFor,
  draftTag,
  validateDraft,
  type GraphQL,
  type PublishDeps,
} from './listings.ts';
import { requireSeller } from './sellers.ts';
import { adminGraphQL } from './shopify/token.ts';

/**
 * Stage 6: after the product exists.
 *
 * Two things a seller does to a product that is already on the store, and
 * one thing the store does to it:
 *
 *  - **Refresh** (pull side of approval): ask the store what status each
 *    submitted listing has now. The webhook normally answers first; this is
 *    the fallback for the day it does not.
 *  - **Update**: title, description, price, stock, tags, category and
 *    collections. Never `productSet`: on an existing product it deletes
 *    every variant and option you omit. `productUpdate`,
 *    `productVariantsBulkUpdate` and `inventorySetQuantities` touch only
 *    what they name.
 */

// ---------------------------------------------------------------- refresh

/** Store status → listing status. Null means the product is gone. */
export function statusFromStore(storeStatus: string | null): 'live' | 'submitted' | 'rejected' {
  switch (storeStatus) {
    case 'ACTIVE':
      return 'live';
    case 'DRAFT':
      return 'submitted';
    default:
      return 'rejected';
  }
}

/** One refresh per listing per minute; the store is not a polling target. */
export const REFRESH_MIN_MS = 60_000;

export async function refreshListings(
  uid: string,
  claims: Record<string, unknown> | undefined,
  deps: PublishDeps = {},
): Promise<{ checked: number; changed: number }> {
  const graphql = deps.graphql ?? adminGraphQL;
  const gate = deps.requireSeller ?? requireSeller;
  await gate(uid, claims);

  const db = getFirestore();
  const snapshot = await db
    .collection('listings')
    .where('sellerUid', '==', uid)
    .where('status', 'in', ['submitted', 'live'])
    .limit(50)
    .get();

  const now = Date.now();
  const due = snapshot.docs.filter((doc) => {
    const data = doc.data();
    if (!data.shopifyProductId) return false;
    const last = data.refreshedAt?.toMillis?.() ?? 0;
    return now - last >= REFRESH_MIN_MS;
  });
  if (due.length === 0) return { checked: 0, changed: 0 };

  // One query for the lot.
  const ids = due.map((doc) => `gid://shopify/Product/${doc.data().shopifyProductId}`);
  const data = await graphql<{ nodes: Array<{ id: string; status: string } | null> }>(
    `query Statuses($ids: [ID!]!) { nodes(ids: $ids) { ... on Product { id status } } }`,
    { ids },
  );

  let changed = 0;
  const batch = db.batch();
  due.forEach((doc, i) => {
    const node = data.nodes[i];
    const next = statusFromStore(node?.status ?? null);
    const current = doc.data().status;
    const patch: Record<string, unknown> = { refreshedAt: FieldValue.serverTimestamp() };
    if (next !== current) {
      changed += 1;
      patch.status = next;
      patch.updatedAt = FieldValue.serverTimestamp();
      if (next === 'live') patch.approvedAt = FieldValue.serverTimestamp();
      if (next === 'rejected') {
        patch.error = node
          ? 'The store archived this product.'
          : 'The store no longer has this product.';
      }
    }
    batch.set(doc.ref, patch, { merge: true });
  });
  await batch.commit();

  logger.info('Refreshed listings', { uid, checked: due.length, changed });
  return { checked: due.length, changed };
}

// ----------------------------------------------------------------- update
//
// Since API 2026-07 the inventory mutations must carry an @idempotent key.
// A fresh one per call: a retried edit that reaches the store twice with the
// same key would be treated as one, which is the opposite of what a second,
// deliberate save means.

export interface StoreProduct {
  id: string;
  variants: {
    nodes: Array<{
      id: string;
      inventoryItem: {
        id: string;
        /** Present when the product was fetched with a location. */
        inventoryLevel?: { quantities: Array<{ name: string; quantity: number }> } | null;
      };
    }>;
  };
  collections: { nodes: Array<{ id: string }> };
}

export interface Mutation {
  name: string;
  query: string;
  variables: Record<string, unknown>;
}

const dollars = (cents: number) => (cents / 100).toFixed(2);

/**
 * The mutations an edit needs, in order. Pure, so a test can assert that
 * `productSet` is not among them and that stock goes through
 * `inventorySetQuantities`.
 */
export function updateMutations(
  listingId: string,
  draft: Record<string, unknown>,
  product: StoreProduct,
  locationId: string | null,
  collectionIds: string[],
): Mutation[] {
  const productId = `gid://shopify/Product/${product.id.split('/').pop()}`;
  const tags = Array.isArray(draft.tags) ? draft.tags.map(String).filter(Boolean) : [];
  const out: Mutation[] = [];

  out.push({
    name: 'productUpdate',
    query: `mutation Update($product: ProductUpdateInput!) {
      productUpdate(product: $product) { product { id } userErrors { field message } }
    }`,
    variables: {
      product: {
        id: productId,
        title: String(draft.title).trim(),
        descriptionHtml: escapeHtml(String(draft.description ?? '')).replace(/\n/g, '<br>'),
        // Tags are replaced wholesale, so the bookkeeping tag rides along.
        tags: [...tags, draftTag(listingId)],
        ...(typeof draft.categoryId === 'string' &&
        draft.categoryId.startsWith('gid://shopify/TaxonomyCategory/')
          ? { category: draft.categoryId }
          : {}),
      },
    },
  });

  // Per-variant edits from the form, matched to the store's variants by
  // id. Without them the top-level price and quantity apply to the first
  // variant, as before.
  const edits = Array.isArray(draft.variants)
    ? (draft.variants as Array<Record<string, unknown>>).filter((v) => typeof v.variantId === 'string')
    : [];
  if (edits.length) {
    const byId = new Map(product.variants.nodes.map((v) => [v.id.split('/').pop() ?? v.id, v]));
    const bulk: Array<Record<string, unknown>> = [];
    const stock: Array<Record<string, unknown>> = [];
    for (const edit of edits) {
      const node = byId.get(String(edit.variantId));
      if (!node) continue;
      bulk.push({
        id: node.id,
        ...(typeof edit.priceCents === 'number' ? { price: dollars(edit.priceCents) } : {}),
        ...(typeof edit.sku === 'string' ? { inventoryItem: { sku: edit.sku } } : {}),
      });
      if (locationId && typeof edit.quantity === 'number') {
        // The store requires the current count on every line (a
        // compare-and-set). A variant never stocked at this location has no
        // count to compare against, so its stock is left for the store's
        // own screen and the result says stock was not fully set.
        const current = node.inventoryItem.inventoryLevel?.quantities.find((q) => q.name === 'available')?.quantity;
        if (typeof current === 'number') {
          stock.push({
            inventoryItemId: node.inventoryItem.id,
            locationId,
            quantity: edit.quantity,
            changeFromQuantity: current,
          });
        }
      }
    }
    if (bulk.length) {
      out.push({
        name: 'productVariantsBulkUpdate',
        query: `mutation Variants($productId: ID!, $variants: [ProductVariantsBulkInput!]!) {
          productVariantsBulkUpdate(productId: $productId, variants: $variants) {
            productVariants { id } userErrors { field message }
          }
        }`,
        variables: { productId, variants: bulk },
      });
    }
    if (stock.length) {
      out.push({
        name: 'inventorySetQuantities',
        query: `mutation Stock($input: InventorySetQuantitiesInput!) {
          inventorySetQuantities(input: $input) @idempotent(key: "${randomUUID()}") {
            inventoryAdjustmentGroup { id } userErrors { field message }
          }
        }`,
        variables: { input: { name: 'available', reason: 'correction', quantities: stock } },
      });
    }
  }

  const variant = edits.length ? undefined : product.variants.nodes[0];
  if (variant) {
    out.push({
      name: 'productVariantsBulkUpdate',
      query: `mutation Variants($productId: ID!, $variants: [ProductVariantsBulkInput!]!) {
        productVariantsBulkUpdate(productId: $productId, variants: $variants) {
          productVariants { id } userErrors { field message }
        }
      }`,
      variables: {
        productId,
        variants: [
          {
            id: variant.id,
            price: dollars(Number(draft.priceCents)),
            compareAtPrice:
              typeof draft.compareAtCents === 'number' && draft.compareAtCents > 0
                ? dollars(draft.compareAtCents)
                : null,
            ...(draft.sku !== undefined ? { inventoryItem: { sku: String(draft.sku ?? '') } } : {}),
          },
        ],
      },
    });

    if (locationId && typeof draft.quantity === 'number' && draft.trackQuantity !== false) {
      // A compare-and-set when the current figure is known: if the store's
      // count moved since the seller looked, the store refuses rather than
      // silently overwriting a sale that landed in between.
      const current = variant.inventoryItem.inventoryLevel?.quantities.find(
        (q) => q.name === 'available',
      )?.quantity;
      if (typeof current === 'number') out.push({
        name: 'inventorySetQuantities',
        query: `mutation Stock($input: InventorySetQuantitiesInput!) {
          inventorySetQuantities(input: $input) @idempotent(key: "${randomUUID()}") {
            inventoryAdjustmentGroup { id } userErrors { field message }
          }
        }`,
        variables: {
          input: {
            name: 'available',
            reason: 'correction',
            quantities: [
              {
                inventoryItemId: variant.inventoryItem.id,
                locationId,
                quantity: draft.quantity,
                changeFromQuantity: current,
              },
            ],
          },
        },
      });
    }
  }

  // Collections: add the new ones, remove the dropped ones, leave the rest.
  const have = new Set(product.collections.nodes.map((c) => c.id));
  const want = new Set(collectionIds);
  for (const id of want) {
    if (have.has(id)) continue;
    out.push({
      name: 'collectionAddProducts',
      query: `mutation Add($id: ID!, $productIds: [ID!]!) {
        collectionAddProducts(id: $id, productIds: $productIds) { userErrors { field message } }
      }`,
      variables: { id, productIds: [productId] },
    });
  }
  for (const id of have) {
    if (want.has(id)) continue;
    out.push({
      name: 'collectionRemoveProducts',
      query: `mutation Remove($id: ID!, $productIds: [ID!]!) {
        collectionRemoveProducts(id: $id, productIds: $productIds) { userErrors { field message } }
      }`,
      variables: { id, productIds: [productId] },
    });
  }

  return out;
}

async function fetchStoreProduct(
  graphql: GraphQL,
  productId: string,
  locationId: string | null,
): Promise<StoreProduct | null> {
  const level = locationId
    ? `inventoryLevel(locationId: $loc) { quantities(names: ["available"]) { name quantity } }`
    : '';
  const data = await graphql<{ product: StoreProduct | null }>(
    `query Product($id: ID!${locationId ? ', $loc: ID!' : ''}) {
      product(id: $id) {
        id
        variants(first: 100) { nodes { id inventoryItem { id ${level} } } }
        collections(first: 50) { nodes { id } }
      }
    }`,
    { id: `gid://shopify/Product/${productId}`, ...(locationId ? { loc: locationId } : {}) },
  );
  return data.product;
}

async function defaultLocationId(graphql: GraphQL): Promise<string | null> {
  try {
    const data = await graphql<{ locations: { nodes: Array<{ id: string }> } }>(
      `{ locations(first: 1, query: "active:true") { nodes { id } } }`,
    );
    return data.locations.nodes[0]?.id ?? null;
  } catch (error) {
    logger.warn('Could not read the shop location; stock left as is', { error: String(error) });
    return null;
  }
}

export async function updateListing(
  uid: string,
  claims: Record<string, unknown> | undefined,
  listingId: string,
  deps: PublishDeps = {},
): Promise<{ shopifyProductId: string; stockSet: boolean }> {
  const graphql = deps.graphql ?? adminGraphQL;
  const gate = deps.requireSeller ?? requireSeller;
  if (!listingId) throw new HttpsError('invalid-argument', 'Which listing?');

  await gate(uid, claims);
  const db = getFirestore();
  const ref = db.collection('listings').doc(listingId);

  const draft = await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const data = snap.data();
    if (!snap.exists || !data) throw new HttpsError('not-found', 'That draft no longer exists.');
    if (data.sellerUid !== uid) throw new HttpsError('permission-denied', 'That draft is not yours.');
    if (!data.shopifyProductId) {
      throw new HttpsError('failed-precondition', 'That product has not been added to the store yet.');
    }
    if (data.status === 'submitting') {
      throw new HttpsError('failed-precondition', 'That product is still being sent. Try again in a moment.');
    }
    const problem = validateDraft(data);
    if (problem) {
      tx.set(ref, { status: 'failed', error: problem, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
      throw new HttpsError('failed-precondition', problem);
    }
    tx.set(ref, { previousStatus: data.status === 'failed' ? (data.previousStatus ?? 'submitted') : data.status, status: 'submitting', error: null, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
    return data;
  });

  const productId = String(draft.shopifyProductId);
  const restoreTo = draft.status === 'failed' ? (draft.previousStatus ?? 'submitted') : draft.status;
  try {
    const locationId = await defaultLocationId(graphql);
    const product = await fetchStoreProduct(graphql, productId, locationId);
    if (!product) {
      throw new HttpsError('failed-precondition', 'The store no longer has this product.');
    }
    const collectionIds = await collectionIdsFor(draft.collectionHandles);
    const mutations = updateMutations(listingId, draft, product, locationId, collectionIds);

    for (const m of mutations) {
      const data = await graphql<Record<string, { userErrors?: Array<{ message: string }> }>>(m.query, m.variables);
      const errors = data[m.name]?.userErrors ?? [];
      if (errors.length) {
        throw new HttpsError(
          'failed-precondition',
          `The store refused the change (${m.name}): ${errors.map((e) => e.message).join('; ')}`,
        );
      }
    }

    const stockSet = mutations.some((m) => m.name === 'inventorySetQuantities');
    await ref.set(
      { status: restoreTo, error: null, previousStatus: FieldValue.delete(), stockSet, updatedAt: FieldValue.serverTimestamp() },
      { merge: true },
    );
    logger.info('Updated a listing on the store', { uid, listingId, productId, mutations: mutations.map((m) => m.name) });
    return { shopifyProductId: productId, stockSet };
  } catch (error) {
    const message = error instanceof HttpsError ? error.message : `Updating failed: ${String((error as Error)?.message ?? error)}`;
    await ref.set({ status: 'failed', error: message, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
    if (error instanceof HttpsError) throw error;
    throw new HttpsError('internal', message);
  }
}

function escapeHtml(text: string): string {
  return text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}
