import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions';

import { ensureOnAppChannel, productCollectionHandles, publishToAllChannels } from './collections.ts';
import { geohash } from './geohash.ts';
import { toCents } from './orders.ts';
import { normalizeVendorName } from './sellers.ts';
import { forgetVendorCache, resolveSellerUid } from './vendors.ts';

/**
 * The catalog mirror.
 *
 * This is the piece that makes the storefront replaceable. Every product is
 * copied into Firestore under *our* field names, so the feed, the grids and
 * search are one cheap query that works offline -- and on the day the
 * storefront goes away, the mirror already is the catalog.
 *
 * Nothing here is the source of truth for price or stock at the moment of
 * sale; the cart re-reads those live. The mirror is for browsing.
 *
 * Two roads lead here and must produce the same document: the REST-shaped
 * product webhook, and the GraphQL-shaped catalog backfill. `productFromGraphQL`
 * turns the second into the first, and `catalogDocFor` is pure so a test can
 * prove the two arrive at byte-identical fields.
 */

/** The REST-shaped product payload, as Shopify's product webhooks send it. */
export interface RestProduct {
  id: string | number;
  title?: string;
  body_html?: string;
  vendor?: string;
  product_type?: string;
  tags?: string;
  status?: string;
  created_at?: string;
  /** Null until the product is on at least one sales channel. */
  published_at?: string | null;
  images?: Array<{ src: string }>;
  variants?: Array<{
    id: string | number;
    title?: string;
    price?: string | number;
    available?: boolean;
    inventory_quantity?: number;
    /** "deny" or "continue": whether it sells past zero. */
    inventory_policy?: string;
    /** Null when stock is not tracked at all. */
    inventory_management?: string | null;
  }>;
  /** Not on webhooks; the backfill carries it, the webhook path fetches it. */
  collectionHandles?: string[];
}

/** One product as the Admin GraphQL `products` query returns it. */
export interface GraphQLProduct {
  id: string;
  title: string;
  descriptionHtml: string;
  vendor: string;
  productType: string;
  tags: string[];
  status: string;
  createdAt: string;
  publishedAt?: string | null;
  images: { nodes: Array<{ url: string }> };
  variants: {
    nodes: Array<{
      id: string;
      title: string;
      price: string;
      availableForSale: boolean;
      inventoryQuantity: number | null;
      inventoryPolicy?: string;
    }>;
  };
  collections: { nodes: Array<{ handle: string }> };
}

/**
 * Whether a variant can be bought right now, from what a webhook carries.
 * The REST payload has no `available` flag; it has the stock count and the
 * policy, and that is what the storefront decides from too.
 */
export function variantAvailable(variant: {
  available?: boolean;
  inventory_quantity?: number;
  inventory_policy?: string;
  inventory_management?: string | null;
}): boolean {
  if (typeof variant.available === 'boolean') return variant.available;
  if (String(variant.inventory_policy ?? '').toLowerCase() === 'continue') return true;
  if (variant.inventory_management === null) return true; // untracked
  if (typeof variant.inventory_quantity !== 'number') return true;
  return variant.inventory_quantity > 0;
}

const tail = (gid: string) => gid.split('/').pop() ?? gid;

/** Tags the app uses for its own bookkeeping; never shown as product tags. */
const INTERNAL_TAG = /^lbm[:-]/i;

/** The listing a store product came from, if the app created it. */
export function listingIdFromTags(tags: string[]): string | null {
  const tag = tags.find((t) => /^lbm:/i.test(t));
  return tag ? tag.slice(4) : null;
}

/** The shape adapter: GraphQL in, the webhook's REST shape out. */
export function productFromGraphQL(node: GraphQLProduct): RestProduct {
  return {
    id: tail(node.id),
    title: node.title,
    body_html: node.descriptionHtml,
    vendor: node.vendor,
    product_type: node.productType,
    tags: node.tags.join(', '),
    status: node.status.toLowerCase(),
    created_at: node.createdAt,
    published_at: node.publishedAt ?? null,
    images: node.images.nodes.map((i) => ({ src: i.url })),
    variants: node.variants.nodes.map((v) => ({
      id: tail(v.id),
      title: v.title,
      price: v.price,
      available: v.availableForSale,
      inventory_quantity: v.inventoryQuantity ?? undefined,
      inventory_policy: v.inventoryPolicy?.toLowerCase(),
    })),
    collectionHandles: node.collections.nodes.map((c) => c.handle),
  };
}

export interface SellerFacts {
  uid: string;
  cityState?: string;
  handleLower?: string;
  lat?: number;
  lng?: number;
}

/**
 * The two documents the mirror writes for a product, computed from the
 * payload alone. Pure, so the webhook and backfill paths are provably equal.
 */
export function catalogDocFor(
  payload: RestProduct,
  seller: SellerFacts | undefined,
  collectionHandles: string[],
): { doc: Record<string, unknown>; spec: Record<string, unknown> } {
  const id = String(payload.id);
  const title = String(payload.title ?? 'Untitled');
  const variants = payload.variants ?? [];
  const first = variants[0];

  // Tags arrive as a comma-separated string. The hashtag-shaped ones are
  // initiative tags, which the post/search vocabulary uses; every tag is
  // kept as `productTags`, because real store tags ("feminist gift") are
  // how sellers describe things and none of them start with '#'.
  const allTags = String(payload.tags ?? '')
    .split(',')
    .map((t) => t.trim())
    .filter((t) => t && !INTERNAL_TAG.test(t));
  const initiativeTags = allTags.filter((t) => t.startsWith('#'));

  const lat = seller?.lat;
  const lng = seller?.lng;

  return {
    doc: {
      title,
      description: stripHtml(String(payload.body_html ?? '')),
      priceCents: first ? toCents(first.price) : 0,
      sellerId: seller?.uid ?? '',
      // The raw Shopify vendor string, and its normalised form. This is the
      // join key: when a vendor claims their shop later, every product
      // carrying their name is re-attributed by `backfillSellerForVendor`.
      vendorName: String(payload.vendor ?? ''),
      vendorKey: normalizeVendorName(String(payload.vendor ?? '')),
      type: String(payload.product_type ?? ''),
      typeSlug: slug(String(payload.product_type ?? '')),
      tags: initiativeTags,
      productTags: allTags,
      // The store's real taxonomy. `product_type` is "physical" across the
      // live store and categorises nothing.
      collectionHandles: [...collectionHandles].sort(),
      imageUrls: (payload.images ?? []).map((image) => String(image.src)).filter(Boolean),
      cityState: seller?.cityState ?? '',
      // Copied from the seller so the radius search has something to scan;
      // a listing with no coordinates is simply not in a radius result.
      lat: lat ?? null,
      lng: lng ?? null,
      geohash: lat !== undefined && lng !== undefined ? geohash(lat, lng) : null,
      sellerHandleLower: seller?.handleLower ?? '',
      titleLower: title.toLowerCase(),
      // One entry per word, so "snowboard" finds "The Complete Snowboard".
      titleWords: titleWords(title),
      // Every word of the title, description and type, so search finds a
      // product by what it says about itself, not only by its name.
      searchWords: titleWords(
        `${title} ${stripHtml(String(payload.body_html ?? ''))} ${String(payload.product_type ?? '')}`,
      ).slice(0, 300),
      active: payload.status === 'active',
      shopifyProductId: id,
      createdAt: payload.created_at ? new Date(payload.created_at) : null,
    },
    spec: {
      subtitle: String(payload.product_type ?? ''),
      lead: '',
      rows: [],
      shipping: [],
      returns: '',
      variants: variants.map((variant) => ({
        name: String(variant.title ?? 'Default'),
        variantId: String(variant.id ?? ''),
        priceCents: toCents(variant.price),
        availableForSale: variantAvailable(variant),
        quantityAvailable:
          typeof variant.inventory_quantity === 'number' ? variant.inventory_quantity : null,
      })),
    },
  };
}

/**
 * The feed entry a live product makes for itself.
 *
 * The feed is a stream of posts, and a marketplace whose sellers have not
 * posted yet is an empty screen. So a product that is active on the store
 * and attributed to a seller posts itself, once, as that seller. The id is
 * derived from the product, so a re-mirror updates rather than duplicates,
 * and the counters are left to the social functions.
 */
export function autoPostFor(
  productId: string,
  sellerUid: string,
  doc: Record<string, unknown>,
): Record<string, unknown> {
  return {
    kind: 'listing',
    authorId: sellerUid,
    productId,
    tags: Array.isArray(doc.tags) ? doc.tags : [],
    auto: true,
    createdAt: doc.createdAt instanceof Date ? doc.createdAt : FieldValue.serverTimestamp(),
    likeCount: FieldValue.increment(0),
    commentCount: FieldValue.increment(0),
  };
}

/** Mirrors one product. Webhook and backfill both end here. */
export async function mirrorProduct(payload: RestProduct): Promise<void> {
  const db = getFirestore();
  const id = String(payload.id);

  const sellerUid = await resolveSellerUid({ vendor: payload.vendor, productId: id });
  const sellerData = sellerUid
    ? (await db.collection('users').doc(sellerUid).get()).data()
    : undefined;
  const seller: SellerFacts | undefined = sellerUid
    ? {
        uid: sellerUid,
        cityState: sellerData?.cityState as string | undefined,
        handleLower: sellerData?.handleLower as string | undefined,
        lat: sellerData?.lat as number | undefined,
        lng: sellerData?.lng as number | undefined,
      }
    : undefined;

  // Webhooks do not carry collections; the backfill does.
  let handles = payload.collectionHandles;
  if (!handles) {
    try {
      handles = await productCollectionHandles(id);
    } catch (error) {
      logger.warn("Could not read a product's collections", { id, error: String(error) });
      handles = [];
    }
  }

  const { doc, spec } = catalogDocFor(payload, seller, handles);
  const ref = db.collection('catalog').doc(id);
  await ref.set(
    {
      ...doc,
      createdAt: doc.createdAt ?? FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
  // The spec table is a subdocument so a feed read does not carry it.
  await ref.collection('spec').doc('detail').set(spec, { merge: true });

  // A live, attributed product is a feed entry. One that is no longer live
  // keeps its post: comments on it are still real, and the card reads the
  // product's own state.
  if (doc.active === true && sellerUid) {
    await db
      .collection('posts')
      .doc(`listing_${id}`)
      .set(autoPostFor(id, sellerUid, doc), { merge: true });
  }

  // Every active product must be on the app's channel, or the storefront
  // refuses it at checkout however visible it is in the app.
  if (doc.active === true) {
    try {
      await ensureOnAppChannel(id);
    } catch (error) {
      logger.warn("Could not put a product on the app's channel", { id, error: String(error) });
    }
  }

  // Approval, push side. A product the app created carries its listing id;
  // the merchant approving it (DRAFT -> ACTIVE in the store) is what flips
  // the seller's chip from Under review to Live.
  const listingId = listingIdFromTags(
    String(payload.tags ?? '').split(',').map((t) => t.trim()),
  );
  if (listingId) {
    const listingRef = db.collection('listings').doc(listingId);
    const listing = (await listingRef.get()).data();
    if (listing) {
      const active = payload.status === 'active';
      // Approval is the merchant setting it Active. That alone leaves it on
      // no sales channel, and the storefront cannot sell what is on no
      // channel; so an approved app product is published everywhere here.
      if (active && payload.published_at == null) {
        try {
          await publishToAllChannels(id);
        } catch (error) {
          logger.warn('Could not publish an approved product to the channels', {
            id,
            error: String(error),
          });
        }
      }
      const wasLive = listing.status === 'live';
      if (active && !wasLive) {
        await listingRef.set(
          { status: 'live', approvedAt: FieldValue.serverTimestamp(), shopifyProductId: id, updatedAt: FieldValue.serverTimestamp() },
          { merge: true },
        );
      } else if (!active && wasLive) {
        await listingRef.set(
          { status: 'submitted', updatedAt: FieldValue.serverTimestamp() },
          { merge: true },
        );
      }
    }
  }

  logger.info('Mirrored a product', { id, sellerUid: sellerUid || '(none)' });
}

/**
 * Re-attributes every mirrored product carrying a vendor name to the account
 * that now holds it — or to nobody, when the grant was revoked.
 *
 * Runs from the Firestore trigger on `sellers/{uid}`, so a seller who claims
 * their shop sees their existing products on their profile within seconds,
 * without anyone re-touching the catalog.
 */
export async function backfillSellerForVendor(
  uid: string,
  vendorName: string,
  active: boolean,
): Promise<number> {
  const db = getFirestore();
  const key = normalizeVendorName(vendorName);
  if (!key) return 0;

  const snapshot = await db.collection('catalog').where('vendorKey', '==', key).get();
  const sellerId = active ? uid : '';
  let updated = 0;
  // Firestore batches cap at 500 writes; 400 leaves room.
  for (let i = 0; i < snapshot.docs.length; i += 400) {
    const batch = db.batch();
    for (const doc of snapshot.docs.slice(i, i + 400)) {
      if (doc.data().sellerId === sellerId) continue;
      batch.set(doc.ref, { sellerId }, { merge: true });
      updated += 1;
    }
    await batch.commit();
  }

  forgetVendorCache();
  logger.info("Re-attributed a vendor's products", {
    uid,
    vendorName,
    active,
    matched: snapshot.size,
    updated,
  });
  return updated;
}

/**
 * A deleted product is deactivated, not removed.
 *
 * Posts, reviews and past orders reference it, and deleting the document would
 * turn every one of those into a broken card.
 */
export async function removeMirroredProduct(id: string): Promise<void> {
  await getFirestore()
    .collection('catalog')
    .doc(id)
    .set(
      { active: false, deletedAt: FieldValue.serverTimestamp() },
      { merge: true },
    );
}

/**
 * The distinct words of a title, lowercased, letters and digits only, in
 * order. "The Complete Snowboard!" -> ["the", "complete", "snowboard"].
 */
export function titleWords(title: string): string[] {
  const seen = new Set<string>();
  for (const word of title.toLowerCase().split(/[^a-z0-9]+/)) {
    if (word) seen.add(word);
  }
  return [...seen];
}

function slug(value: string): string {
  return value.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
}

/** Product descriptions arrive as HTML; the app renders plain text. */
function stripHtml(html: string): string {
  return html
    .replace(/<br\s*\/?>/gi, '\n')
    .replace(/<\/p>/gi, '\n\n')
    .replace(/<[^>]+>/g, '')
    .replace(/&nbsp;/g, ' ')
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/\n{3,}/g, '\n\n')
    .trim();
}
