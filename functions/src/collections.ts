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
 * Puts a product on every sales channel the store has.
 *
 * "Active" and "published" are two different switches on Shopify. A product
 * the app created is Active once the merchant approves it, but it is on no
 * channel until something publishes it, and a product on no channel cannot
 * be sold through the storefront API ("the merchandise does not exist").
 * Idempotent: publishing to a channel it is already on is a no-op.
 */
export async function publishToAllChannels(productId: string): Promise<number> {
  const pubs = await adminGraphQL<{ publications: { nodes: Array<{ id: string }> } }>(
    `{ publications(first: 20) { nodes { id } } }`,
  );
  const input = pubs.publications.nodes.map((p) => ({ publicationId: p.id }));
  if (input.length === 0) return 0;
  const data = await adminGraphQL<{
    publishablePublish: { userErrors: Array<{ message: string }> };
  }>(
    `mutation Publish($id: ID!, $input: [PublicationInput!]!) {
      publishablePublish(id: $id, input: $input) { userErrors { field message } }
    }`,
    { id: `gid://shopify/Product/${productId}`, input },
  );
  const errors = data.publishablePublish.userErrors;
  if (errors.length) {
    throw new Error(`publishablePublish: ${errors.map((e) => e.message).join('; ')}`);
  }
  logger.info('Published a product to every channel', { productId, channels: input.length });
  return input.length;
}

/**
 * The app's own sales channel, by name.
 *
 * The Storefront token belongs to the headless channel Shopify created for
 * the app, and the storefront can only sell what is published to it. A
 * product on the Online Store alone is invisible to checkout. Pure, so the
 * choice is testable: the headless publication if there is one, else null.
 */
export function pickAppPublication(
  publications: Array<{ id: string; name: string }>,
): string | null {
  const headless = publications.find((p) => /headless/i.test(p.name));
  return headless?.id ?? null;
}

let appPublicationCache: string | null | undefined;

async function appPublicationId(): Promise<string | null> {
  if (appPublicationCache !== undefined) return appPublicationCache;
  const data = await adminGraphQL<{ publications: { nodes: Array<{ id: string; name: string }> } }>(
    `{ publications(first: 20) { nodes { id name } } }`,
  );
  appPublicationCache = pickAppPublication(data.publications.nodes);
  if (!appPublicationCache) {
    logger.warn('No headless publication found; products cannot be sold through the app', {
      publications: data.publications.nodes.map((p) => p.name),
    });
  }
  return appPublicationCache;
}

/**
 * Makes sure a product is on the app's channel. Every active product goes
 * through here on mirror; a merchant creating a product in the Shopify admin
 * publishes it to the Online Store and never thinks about the app's channel,
 * and the checkout then says the merchandise does not exist.
 */
export async function ensureOnAppChannel(productId: string): Promise<boolean> {
  const publicationId = await appPublicationId();
  if (!publicationId) return false;
  const gid = `gid://shopify/Product/${productId}`;
  const check = await adminGraphQL<{ product: { publishedOnPublication: boolean } | null }>(
    `query OnChannel($id: ID!, $pub: ID!) { product(id: $id) { publishedOnPublication(publicationId: $pub) } }`,
    { id: gid, pub: publicationId },
  );
  if (!check.product || check.product.publishedOnPublication) return false;
  const data = await adminGraphQL<{ publishablePublish: { userErrors: Array<{ message: string }> } }>(
    `mutation Publish($id: ID!, $input: [PublicationInput!]!) {
      publishablePublish(id: $id, input: $input) { userErrors { field message } }
    }`,
    { id: gid, input: [{ publicationId }] },
  );
  const errors = data.publishablePublish.userErrors;
  if (errors.length) throw new Error(`publishablePublish: ${errors.map((e) => e.message).join('; ')}`);
  logger.info("Published a product to the app's channel", { productId });
  return true;
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

/**
 * The collections whose membership the mirror re-reads from the store on a
 * schedule, by handle.
 *
 * A product's `collectionHandles` is written when the product itself
 * changes. Putting a product into a collection does not change the product,
 * so Shopify sends no webhook, and a collection built by adding existing
 * products to it (which is exactly how the Holiday Gift Guide is made) came
 * out empty or half full in the app while the website showed all of it.
 * These are the ones the app opens by name: the gift guide, and the rows on
 * the Market screen. Must match `kGiftGuide` and `kMarketShelves` in
 * lib/models/gift_guide.dart (test/gift_guide_test.dart reads this file).
 */
export const CURATED_COLLECTIONS = [
  // Holiday Gift Guide, 2026
  'for-the-book-lover',
  'doomscroll-detox',
  'for-the-friend-who-runs-the-group-chat',
  'for-the-garden-variety-optimist',
  'gifts-hopescrolling',
  'for-the-host',
  'custom-personalized-gifts',
  'gifts-kids-and-baby',
  'gifts-toys-and-games',
  'for-the-pet-parents',
  'gift-small-biz-besties',
  'gifts-for-teachers',
  'for-a-teen-picked-by-a-teen',
  'wear-it-loud',
  'market-sellers-picks',
  'sandees-picks-home',
  'sandees-picks-self-care',
  'sandees-picks-wear',
  'saras-half-helpful-haul-do',
  'saras-half-hopeful-haul-dogs',
  'saras-half-hopeful-haul-wear',
  'gifts-under-25',
  'gifts-under-50',
  'gifts-under-100',
  'splurge-with-purpose',
  'thanksgiving-decor',
  'hanukkah-cards-decor',
  'christmas-decor',
  'erins-holiday-picks',
  'kates-holiday-wishlist',
  // The Market screen
  'new-arrivals',
] as const;

/** Every product id in one collection, by handle, paginated. */
async function collectionProductIds(handle: string): Promise<string[] | null> {
  const ids: string[] = [];
  let after: string | null = null;
  for (;;) {
    const data: {
      collections: {
        nodes: Array<{
          handle: string;
          products: {
            pageInfo: { hasNextPage: boolean; endCursor: string | null };
            nodes: Array<{ id: string }>;
          };
        }>;
      };
    } = await adminGraphQL(
      // A search rather than collectionByHandle, which newer API versions
      // retire. The exact-handle check below guards against a near match.
      `query Members($query: String!, $after: String) {
        collections(first: 5, query: $query) {
          nodes {
            handle
            products(first: 250, after: $after) {
              pageInfo { hasNextPage endCursor }
              nodes { id }
            }
          }
        }
      }`,
      { query: `handle:${handle}`, after },
    );
    const page = data.collections.nodes.find((c) => c.handle === handle)?.products;
    if (!page) return ids.length ? ids : null;
    ids.push(...page.nodes.map((n) => n.id.split('/').pop() ?? n.id));
    if (!page.pageInfo.hasNextPage) return ids;
    after = page.pageInfo.endCursor;
  }
}

/**
 * What has to change for the mirror to agree with the store about one
 * collection: the products to add the handle to, and the ones to take it
 * off. Only products the mirror already holds are added to; one it has never
 * mirrored is the product webhook's business, not this. Pure.
 */
export function membershipDiff(
  storeIds: readonly string[],
  mirrorMemberIds: readonly string[],
  mirrorHas: (id: string) => boolean,
): { add: string[]; remove: string[] } {
  const store = new Set(storeIds);
  const mirror = new Set(mirrorMemberIds);
  return {
    add: [...store].filter((id) => !mirror.has(id) && mirrorHas(id)),
    remove: [...mirror].filter((id) => !store.has(id)),
  };
}

/**
 * Re-reads [CURATED_COLLECTIONS] from the store and corrects the mirror's
 * `collectionHandles` where they disagree. A collection the store no longer
 * has is left alone rather than emptied: a renamed handle should cost a
 * stale row, not every product's membership.
 */
export async function syncCollectionMembership(
  handles: readonly string[] = CURATED_COLLECTIONS,
): Promise<{ collections: number; added: number; removed: number; missing: string[] }> {
  const db = getFirestore();
  const catalog = db.collection('catalog');
  let added = 0;
  let removed = 0;
  const missing: string[] = [];

  for (const handle of handles) {
    const storeIds = await collectionProductIds(handle);
    if (storeIds === null) {
      missing.push(handle);
      continue;
    }
    const members = await catalog.where('collectionHandles', 'array-contains', handle).select().get();
    const memberIds = members.docs.map((d) => d.id);

    // Which of the store's products the mirror holds at all.
    const unknown = storeIds.filter((id) => !memberIds.includes(id));
    const held = new Set<string>();
    for (let i = 0; i < unknown.length; i += 300) {
      const refs = unknown.slice(i, i + 300).map((id) => catalog.doc(id));
      const snaps = await db.getAll(...refs, { fieldMask: [] });
      for (const snap of snaps) if (snap.exists) held.add(snap.id);
    }

    const diff = membershipDiff(storeIds, memberIds, (id) => held.has(id));
    const writes = [
      ...diff.add.map((id) => ({ id, change: FieldValue.arrayUnion(handle) })),
      ...diff.remove.map((id) => ({ id, change: FieldValue.arrayRemove(handle) })),
    ];
    for (let i = 0; i < writes.length; i += 400) {
      const batch = db.batch();
      for (const w of writes.slice(i, i + 400)) {
        batch.update(catalog.doc(w.id), { collectionHandles: w.change });
      }
      await batch.commit();
    }
    added += diff.add.length;
    removed += diff.remove.length;
  }

  const tally = { collections: handles.length, added, removed, missing };
  logger.info('Synced collection membership', tally);
  return tally;
}
