import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions';
import { HttpsError } from 'firebase-functions/v2/https';

import { catalogDocFor, type RestProduct } from './catalog.ts';
import { stockLocationId } from './locations.ts';
import { requireSeller } from './sellers.ts';
import { adminGraphQL } from './shopify/token.ts';

/**
 * Journey B: a seller adds a product from the app.
 *
 * The app writes a draft to `listings/{id}` (its own document, by rules) and
 * then sends *only the id* here. Every value is re-read from the draft, so a
 * tampered price never reaches the store. The vendor name goes to Shopify from
 * `sellers/{uid}` and never from the request: that string assigns every
 * future sale.
 *
 * The product is created as DRAFT and never published here. Shipturtle's
 * merchant approval queue is the control the merchant relies on; publishing
 * straight to ACTIVE would delete it.
 *
 * Idempotency, in three layers: a `submitting` guard set in a transaction, the
 * `shopifyProductId` stamped on the draft, and a search of the store for the
 * `lbm:<listingId>` tag that every product created here carries. A retry
 * after a crash at any point adopts the product that already exists rather
 * than making a second one.
 */

export type GraphQL = <T>(query: string, variables?: Record<string, unknown>) => Promise<T>;

export interface PublishDeps {
  graphql?: GraphQL;
  requireSeller?: typeof requireSeller;
}

export interface PublishResult {
  shopifyProductId: string;
  adopted: boolean;
  stockSet: boolean;
}

/** The tag that ties a store product back to the draft it came from. */
export function draftTag(listingId: string): string {
  return `lbm:${listingId}`;
}

const MAX_TITLE = 255;

/** The validation the rules cannot do: shape and sense, in plain words. */
export function validateDraft(draft: Record<string, unknown>): string | null {
  const title = String(draft.title ?? '').trim();
  if (!title) return 'Give it a title.';
  if (title.length > MAX_TITLE) return `Keep the title under ${MAX_TITLE} characters.`;
  const price = draft.priceCents;
  if (typeof price !== 'number' || !Number.isInteger(price) || price <= 0) {
    return 'Set a price above $0.';
  }
  const images = Array.isArray(draft.imageUrls) ? draft.imageUrls.filter(Boolean) : [];
  if (images.length === 0) return 'Add at least one photo.';
  const quantity = draft.quantity;
  if (quantity !== undefined && (typeof quantity !== 'number' || quantity < 0 || !Number.isInteger(quantity))) {
    return 'Quantity must be a whole number, zero or more.';
  }
  return null;
}

const dollars = (cents: number) => (cents / 100).toFixed(2);

/** Builds the one `productSet` input from a validated draft. Pure. */
export function productSetInput(
  listingId: string,
  draft: Record<string, unknown>,
  vendorName: string,
  locationId: string | null,
  /** Shopify collection GIDs; the draft holds handles, which Shopify does not take. */
  collectionIds: string[] = [],
): Record<string, unknown> {
  const tags = Array.isArray(draft.tags) ? draft.tags.map(String).filter(Boolean) : [];
  const quantity = typeof draft.quantity === 'number' ? draft.quantity : 0;
  const trackQuantity = draft.trackQuantity !== false;
  const weightGrams = typeof draft.weightGrams === 'number' ? draft.weightGrams : 0;

  return {
    title: String(draft.title).trim(),
    descriptionHtml: escapeHtml(String(draft.description ?? '')).replace(/\n/g, '<br>'),
    vendor: vendorName,
    productType: String(draft.productType ?? 'physical'),
    status: 'DRAFT',
    tags: [...tags, draftTag(listingId)],
    productOptions: [{ name: 'Title', values: [{ name: 'Default Title' }] }],
    variants: [
      {
        optionValues: [{ optionName: 'Title', name: 'Default Title' }],
        price: dollars(Number(draft.priceCents)),
        ...(typeof draft.compareAtCents === 'number' && draft.compareAtCents > 0
          ? { compareAtPrice: dollars(draft.compareAtCents) }
          : {}),
        ...(draft.sku ? { sku: String(draft.sku) } : {}),
        ...(draft.barcode ? { barcode: String(draft.barcode) } : {}),
        taxable: draft.chargeTax !== false,
        inventoryPolicy: draft.continueSellingOOS === true ? 'CONTINUE' : 'DENY',
        inventoryItem: {
          tracked: trackQuantity,
          ...(typeof draft.costCents === 'number' && draft.costCents > 0
            ? { cost: dollars(draft.costCents) }
            : {}),
          ...(weightGrams > 0
            ? { measurement: { weight: { unit: 'GRAMS', value: weightGrams } } }
            : {}),
        },
        ...(locationId && trackQuantity
          ? { inventoryQuantities: [{ locationId, name: 'available', quantity }] }
          : {}),
      },
    ],
    files: (draft.imageUrls as string[]).filter(Boolean).map((url) => ({
      originalSource: url,
      contentType: 'IMAGE',
    })),
    ...(collectionIds.length ? { collections: collectionIds } : {}),
    // Shopify's standard product taxonomy ("Apparel & Accessories > Clothing >
    // Shirts & Tops"). Picked from a search on the form; the id is a GID.
    ...(typeof draft.categoryId === 'string' && draft.categoryId.startsWith('gid://shopify/TaxonomyCategory/')
      ? { category: draft.categoryId }
      : {}),
    metafields: [
      {
        namespace: 'lbm',
        key: 'draft_id',
        type: 'single_line_text_field',
        value: listingId,
      },
    ],
  };
}

/** Looks for a product this listing already created, by its tag. */
export async function findExistingProduct(
  graphql: GraphQL,
  listingId: string,
): Promise<string | null> {
  const data = await graphql<{ products: { nodes: Array<{ id: string }> } }>(
    `query FindDraft($q: String!) { products(first: 2, query: $q) { nodes { id } } }`,
    { q: `tag:'${draftTag(listingId)}'` },
  );
  const first = data.products.nodes[0];
  return first ? first.id.split('/').pop() ?? null : null;
}

export interface CategoryHit {
  id: string;
  name: string;
  fullName: string;
  isLeaf: boolean;
}

/** Shopify's product taxonomy, searched by name. Any signed-in seller. */
export async function searchCategories(
  rawQuery: string,
  graphql: GraphQL = adminGraphQL,
): Promise<CategoryHit[]> {
  const query = rawQuery.trim();
  if (query.length < 2) return [];
  const data = await graphql<{
    taxonomy: { categories: { nodes: CategoryHit[] } };
  }>(
    `query Categories($q: String!) {
      taxonomy { categories(first: 8, search: $q) { nodes { id name fullName isLeaf } } }
    }`,
    { q: query },
  );
  return data.taxonomy.categories.nodes;
}

/** The mirrored collections' Shopify ids for the handles a draft picked. */
export async function collectionIdsFor(handles: unknown): Promise<string[]> {
  if (!Array.isArray(handles) || handles.length === 0) return [];
  const db = getFirestore();
  const ids: string[] = [];
  for (const handle of handles.map(String)) {
    const doc = await db.collection('collections').doc(handle).get();
    const id = doc.data()?.id;
    if (id) ids.push(`gid://shopify/Collection/${id}`);
  }
  return ids;
}

/** The location opening stock goes to; see locations.ts. */
async function defaultLocationId(graphql: GraphQL): Promise<string | null> {
  return stockLocationId(graphql);
}

export async function publishListing(
  uid: string,
  claims: Record<string, unknown> | undefined,
  listingId: string,
  deps: PublishDeps = {},
): Promise<PublishResult> {
  const graphql = deps.graphql ?? adminGraphQL;
  const gate = deps.requireSeller ?? requireSeller;

  if (!listingId) throw new HttpsError('invalid-argument', 'Which listing?');
  const db = getFirestore();
  const ref = db.collection('listings').doc(listingId);

  // The three-fact check. Nothing below runs for a revoked seller, however
  // fresh their token.
  const { vendorName } = await gate(uid, claims);

  // Claim the draft for this attempt, or find out why not.
  const draft = await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const data = snap.data();
    if (!snap.exists || !data) {
      throw new HttpsError('not-found', 'That draft no longer exists.');
    }
    if (data.sellerUid !== uid) {
      throw new HttpsError('permission-denied', 'That draft is not yours.');
    }
    if (data.status === 'live' || data.status === 'submitted') {
      throw new HttpsError(
        'failed-precondition',
        'That product has already been sent for review.',
      );
    }
    const problem = validateDraft(data);
    if (problem) {
      tx.set(ref, { status: 'failed', error: problem, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
      throw new HttpsError('failed-precondition', problem);
    }
    tx.set(
      ref,
      { status: 'submitting', error: null, attempts: FieldValue.increment(1), updatedAt: FieldValue.serverTimestamp() },
      { merge: true },
    );
    return data;
  });

  try {
    // Layer two and three of idempotency: the stamp, then the tag search.
    let productId: string | null = draft.shopifyProductId ? String(draft.shopifyProductId) : null;
    let adopted = Boolean(productId);
    if (!productId) {
      productId = await findExistingProduct(graphql, listingId);
      adopted = Boolean(productId);
    }

    let stockSet = false;
    if (!productId) {
      const locationId = await defaultLocationId(graphql);
      const collectionIds = await collectionIdsFor(draft.collectionHandles);
      const input = productSetInput(listingId, draft, vendorName, locationId, collectionIds);
      stockSet = Boolean(locationId);

      const data = await graphql<{
        productSet: {
          product: { id: string } | null;
          userErrors: Array<{ field: string[] | null; message: string }>;
        };
      }>(
        `mutation Create($input: ProductSetInput!) {
          productSet(input: $input, synchronous: true) {
            product { id }
            userErrors { field message }
          }
        }`,
        { input },
      );
      const errors = data.productSet.userErrors;
      if (errors.length || !data.productSet.product) {
        throw new HttpsError(
          'failed-precondition',
          errors.length
            ? `The store refused it: ${errors.map((e) => e.message).join('; ')}`
            : 'The store did not return a product.',
        );
      }
      productId = data.productSet.product.id.split('/').pop() ?? data.productSet.product.id;
    }

    // Seed the mirror now; the products/create webhook rewrites it canonically
    // within a minute. `active: false` because it is a DRAFT under review.
    const seed: RestProduct = {
      id: productId,
      title: String(draft.title),
      body_html: String(draft.description ?? ''),
      vendor: vendorName,
      product_type: String(draft.productType ?? 'physical'),
      tags: (Array.isArray(draft.tags) ? draft.tags.map(String) : []).join(', '),
      status: 'draft',
      created_at: new Date().toISOString(),
      images: (draft.imageUrls as string[]).map((src) => ({ src })),
      variants: [
        {
          id: '',
          title: 'Default Title',
          price: dollars(Number(draft.priceCents)),
          available: true,
          inventory_quantity: typeof draft.quantity === 'number' ? draft.quantity : 0,
        },
      ],
      collectionHandles: Array.isArray(draft.collectionHandles) ? draft.collectionHandles.map(String) : [],
    };
    const { doc, spec } = catalogDocFor(seed, { uid }, seed.collectionHandles ?? []);
    const catalogRef = db.collection('catalog').doc(productId);
    await catalogRef.set(
      { ...doc, createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp(), listingId },
      { merge: true },
    );
    await catalogRef.collection('spec').doc('detail').set(spec, { merge: true });

    await ref.set(
      {
        status: 'submitted',
        shopifyProductId: productId,
        submittedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
        error: null,
        stockSet,
      },
      { merge: true },
    );

    logger.info('Submitted a listing for review', { uid, listingId, productId, adopted, stockSet });
    return { shopifyProductId: productId, adopted, stockSet };
  } catch (error) {
    // Human-readable, and left on the draft so the retry button can show it.
    const message = error instanceof HttpsError ? error.message : `Publishing failed: ${String((error as Error)?.message ?? error)}`;
    await ref.set(
      { status: 'failed', error: message, updatedAt: FieldValue.serverTimestamp() },
      { merge: true },
    );
    if (error instanceof HttpsError) throw error;
    throw new HttpsError('internal', message);
  }
}

function escapeHtml(text: string): string {
  return text
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');
}
