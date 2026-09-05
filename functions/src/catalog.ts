import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions';

import { resolveSellerUid } from './vendors.ts';
import { geohash } from './geohash.ts';
import { toCents } from './orders.ts';

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
 */
export async function mirrorProduct(payload: Record<string, any>): Promise<void> {
  const db = getFirestore();
  const id = String(payload.id);

  const sellerUid = await resolveSellerUid({
    vendor: payload.vendor,
    productId: id,
  });

  const variants = (payload.variants ?? []) as Array<Record<string, any>>;
  const first = variants[0];
  const images = (payload.images ?? []) as Array<Record<string, any>>;

  // Tags arrive as a comma-separated string. Only the hashtag-shaped ones are
  // initiative tags; the rest are the seller's own housekeeping.
  const allTags = String(payload.tags ?? '')
    .split(',')
    .map((t) => t.trim())
    .filter(Boolean);
  const initiativeTags = allTags.filter((t) => t.startsWith('#'));

  const seller = sellerUid
    ? (await db.collection('users').doc(sellerUid).get()).data()
    : undefined;

  const lat = seller?.lat as number | undefined;
  const lng = seller?.lng as number | undefined;

  await db.collection('catalog').doc(id).set(
    {
      title: String(payload.title ?? 'Untitled'),
      description: stripHtml(String(payload.body_html ?? '')),
      priceCents: first ? toCents(first.price) : 0,
      sellerId: sellerUid,
      type: String(payload.product_type ?? ''),
      typeSlug: slug(String(payload.product_type ?? '')),
      tags: initiativeTags,
      imageUrls: images.map((image) => String(image.src)).filter(Boolean),
      cityState: (seller?.cityState as string | undefined) ?? '',
      // Copied from the seller so the radius search has something to scan;
      // a listing with no coordinates is simply not in a radius result.
      lat: lat ?? null,
      lng: lng ?? null,
      geohash: lat !== undefined && lng !== undefined ? geohash(lat, lng) : null,
      sellerHandleLower: (seller?.handleLower as string | undefined) ?? '',
      titleLower: String(payload.title ?? '').toLowerCase(),
      // One entry per word, so "snowboard" finds "The Complete Snowboard".
      // Firestore has no substring match; array-contains on words is the
      // closest honest thing.
      titleWords: titleWords(String(payload.title ?? '')),
      active: payload.status === 'active',
      shopifyProductId: id,
      updatedAt: FieldValue.serverTimestamp(),
      createdAt: payload.created_at
        ? new Date(payload.created_at)
        : FieldValue.serverTimestamp(),
    },
    { merge: true },
  );

  // The spec table is a subdocument so a feed read does not carry it.
  await db
    .collection('catalog')
    .doc(id)
    .collection('spec')
    .doc('detail')
    .set(
      {
        subtitle: String(payload.product_type ?? ''),
        lead: '',
        rows: [],
        shipping: [],
        returns: '',
        variants: variants.map((variant) => ({
          name: String(variant.title ?? 'Default'),
          variantId: String(variant.id ?? ''),
          priceCents: toCents(variant.price),
          availableForSale: variant.available !== false,
          quantityAvailable:
            typeof variant.inventory_quantity === 'number'
              ? variant.inventory_quantity
              : null,
        })),
      },
      { merge: true },
    );

  logger.info('Mirrored a product', { id, sellerUid: sellerUid || '(none)' });
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
