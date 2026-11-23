import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions';
import { HttpsError } from 'firebase-functions/v2/https';

/**
 * Products a directory business sells on its own website (Stage 13).
 *
 * A business listed on littlebluecart.com has no Shopify shop, so its
 * products live here rather than in the catalog mirror, and the Buy button
 * opens its website instead of the cart. Written only through the two
 * callables below, which refuse anyone not joined to the directory: the
 * link (`directory/{uid}`) is the grant, the same way `sellers/{uid}` is for
 * the Market. Everyone reads them; each one also posts itself to the feed as
 * a listing whose product id carries the `dp_` prefix the phone recognises.
 */

export const TITLE_MAX = 80;
export const DESCRIPTION_MAX = 600;
export const PHOTOS_MAX = 6;
export const PRODUCT_ID_PREFIX = 'dp_';

export interface DirectoryProductInput {
  title: string;
  description: string;
  priceCents: number;
  imageUrls: string[];
  buyUrl: string;
  tags: string[];
}

function str(v: unknown): string {
  return v === null || v === undefined ? '' : String(v).trim();
}

function httpsUrl(value: string): string | null {
  try {
    const url = new URL(value.startsWith('http') ? value : `https://${value}`);
    if (url.protocol !== 'https:' && url.protocol !== 'http:') return null;
    return url.toString();
  } catch {
    return null;
  }
}

/** The request as a clean product, or an error the person can act on. Pure. */
export function validateProduct(data: Record<string, unknown>, fallbackBuyUrl: string): DirectoryProductInput {
  const title = str(data.title);
  if (!title) throw new HttpsError('invalid-argument', 'Give the product a name.');
  if (title.length > TITLE_MAX) throw new HttpsError('invalid-argument', `Keep the name under ${TITLE_MAX} characters.`);
  const description = str(data.description);
  if (description.length > DESCRIPTION_MAX) {
    throw new HttpsError('invalid-argument', `Keep the description under ${DESCRIPTION_MAX} characters.`);
  }
  const price = Number(data.priceCents ?? 0);
  if (!Number.isInteger(price) || price < 0 || price > 100_000_000) {
    throw new HttpsError('invalid-argument', 'The price does not look right.');
  }
  const images = Array.isArray(data.imageUrls) ? data.imageUrls.map(str).filter(Boolean) : [];
  if (images.length > PHOTOS_MAX) throw new HttpsError('invalid-argument', `Up to ${PHOTOS_MAX} photos.`);
  for (const url of images) {
    if (!/^https:\/\//.test(url)) throw new HttpsError('invalid-argument', 'A photo link must start with https://');
  }
  const buyRaw = str(data.buyUrl) || fallbackBuyUrl;
  const buyUrl = buyRaw ? httpsUrl(buyRaw) : null;
  if (!buyUrl) {
    throw new HttpsError(
      'invalid-argument',
      'Add the web address where people buy this (or put a website on your directory listing).',
    );
  }
  const tags = [...new Set((Array.isArray(data.tags) ? data.tags.map(str) : []).filter(Boolean))].slice(0, 12);
  return { title, description, priceCents: price, imageUrls: images, buyUrl, tags };
}

async function requireDirectoryLink(uid: string): Promise<Record<string, unknown>> {
  const link = (await getFirestore().collection('directory').doc(uid).get()).data();
  if (!link || link.status !== 'linked') {
    throw new HttpsError(
      'failed-precondition',
      'Only businesses in the Little Blue Cart directory can add products this way. Link your directory account first (Edit profile -> Little Blue Cart directory).',
    );
  }
  return link;
}

/**
 * Pure: may this account put products on the app as a directory business?
 *
 * Linked is not enough. A link is made for anyone the website knows, which
 * includes a shopper who once bought something there, and a business whose
 * listing is still waiting for approval. Grace, 2026-11-23: "unauthorized
 * listings for businesses that are not approved". So it takes a listing the
 * website has published, owned by this account, on a link whose ownership
 * was not refused or locked by an admin.
 */
export function isApprovedBusiness(
  link: Record<string, unknown> | undefined,
  listingStatuses: readonly unknown[],
): boolean {
  if (!link || link.status !== 'linked') return false;
  if (link.ownsListings === false || link.ownershipLocked === true) return false;
  return listingStatuses.some((s) => s === 'publish');
}

/** The status of every directory listing this account owns. */
async function listingStatusesOf(uid: string): Promise<unknown[]> {
  const listings = await getFirestore().collection('directoryListings').where('ownerUid', '==', uid).get();
  return listings.docs.map((d) => d.data().status);
}

export const NOT_APPROVED_MESSAGE =
  'Products can be added once your Little Blue Cart directory listing has been approved. ' +
  'If it was approved today, open Edit profile, then Little Blue Cart directory, and tap Refresh.';

async function requireApprovedBusiness(uid: string): Promise<void> {
  const link = await requireDirectoryLink(uid);
  if (!isApprovedBusiness(link, await listingStatusesOf(uid))) {
    throw new HttpsError('failed-precondition', NOT_APPROVED_MESSAGE);
  }
}

export interface UnapprovedOwner {
  uid: string;
  name: string;
  handle: string;
  products: string[];
}

/**
 * Admin: every directory product whose owner is not an approved business.
 * With `remove`, deletes them and their feed posts. Clears what was added
 * before the check above existed. The collection is small (one read of it),
 * so one call does the lot.
 */
export async function sweepUnapprovedDirectoryProducts(
  remove: boolean,
): Promise<{ checked: number; owners: UnapprovedOwner[]; removed: number }> {
  const db = getFirestore();
  const all = await db.collection('directoryProducts').get();
  const byOwner = new Map<string, { id: string; title: string }[]>();
  for (const doc of all.docs) {
    const owner = str(doc.data().ownerUid);
    const list = byOwner.get(owner) ?? [];
    list.push({ id: doc.id, title: str(doc.data().title) });
    byOwner.set(owner, list);
  }
  const owners: UnapprovedOwner[] = [];
  let removed = 0;
  for (const [uid, products] of byOwner) {
    const link = uid ? (await db.collection('directory').doc(uid).get()).data() : undefined;
    if (uid && isApprovedBusiness(link, await listingStatusesOf(uid))) continue;
    const user = uid ? ((await db.collection('users').doc(uid).get()).data() ?? {}) : {};
    owners.push({ uid, name: str(user.name), handle: str(user.handle), products: products.map((p) => p.title || p.id) });
    if (!remove) continue;
    // Two deletes per product, so 200 products stay under a batch's 500.
    for (let i = 0; i < products.length; i += 200) {
      const chunk = products.slice(i, i + 200);
      const batch = db.batch();
      for (const p of chunk) {
        batch.delete(db.collection('directoryProducts').doc(p.id));
        batch.delete(db.collection('posts').doc(`dirproduct_${p.id}`));
      }
      await batch.commit();
      removed += chunk.length;
    }
  }
  logger.info('Swept unapproved directory products', { checked: all.size, owners: owners.length, removed, remove });
  return { checked: all.size, owners, removed };
}

/** The website on the owner's listing, for a product that names none. */
async function listingWebsite(uid: string): Promise<string> {
  const listings = await getFirestore().collection('directoryListings').where('ownerUid', '==', uid).get();
  for (const doc of listings.docs) {
    const site = str(doc.data().website);
    if (site) return site;
  }
  return '';
}

export async function saveDirectoryProduct(
  uid: string,
  data: Record<string, unknown>,
  id?: string,
): Promise<{ id: string }> {
  await requireApprovedBusiness(uid);
  const db = getFirestore();
  const products = db.collection('directoryProducts');
  const ref = id ? products.doc(id) : products.doc();
  const existing = id ? (await ref.get()).data() : undefined;
  if (id && !existing) throw new HttpsError('not-found', 'That product is gone.');
  if (existing && existing.ownerUid !== uid) throw new HttpsError('permission-denied', 'That product is not yours.');

  const input = validateProduct(data, await listingWebsite(uid));
  const owner = (await db.collection('users').doc(uid).get()).data() ?? {};
  const now = FieldValue.serverTimestamp();
  const batch = db.batch();
  batch.set(
    ref,
    {
      ownerUid: uid,
      title: input.title,
      description: input.description,
      priceCents: input.priceCents,
      imageUrls: input.imageUrls,
      buyUrl: input.buyUrl,
      tags: input.tags,
      // Where the business is, so Near me can measure to it later.
      cityState: str(owner.cityState),
      lat: typeof owner.lat === 'number' ? owner.lat : null,
      lng: typeof owner.lng === 'number' ? owner.lng : null,
      updatedAt: now,
      ...(existing ? {} : { createdAt: now, saveCount: 0, inCartsCount: 0, commentCount: 0 }),
    },
    { merge: true },
  );
  // The feed entry: a listing post whose product lives here, not in the
  // catalog. Created once; edits keep its place in the feed.
  const postRef = db.collection('posts').doc(`dirproduct_${ref.id}`);
  batch.set(
    postRef,
    {
      kind: 'listing',
      authorId: uid,
      productId: `${PRODUCT_ID_PREFIX}${ref.id}`,
      caption: input.description.split('\n')[0]?.slice(0, 140) ?? '',
      tags: input.tags,
      likeCount: FieldValue.increment(0),
      commentCount: FieldValue.increment(0),
      ...(existing ? {} : { createdAt: now }),
    },
    { merge: true },
  );
  await batch.commit();
  logger.info(existing ? 'Directory product edited' : 'Directory product added', { uid, id: ref.id });
  return { id: ref.id };
}

/**
 * "Did you buy it?" A purchase made on a directory business's own website is
 * invisible to the app, so the buyer says so when they come back. It lands
 * under Bought (delivered, since nothing here can track it), counts toward
 * "new from a shop you bought from", and can be reviewed. Marked
 * self-reported, never a sale figure.
 */
export async function reportDirectoryPurchase(
  uid: string,
  productId: string,
): Promise<{ purchaseId: string }> {
  if (!productId.startsWith(PRODUCT_ID_PREFIX)) {
    throw new HttpsError('invalid-argument', 'Only website-link products can be reported this way.');
  }
  const docId = productId.slice(PRODUCT_ID_PREFIX.length);
  const db = getFirestore();
  const product = (await db.collection('directoryProducts').doc(docId).get()).data();
  if (!product) throw new HttpsError('not-found', 'That product is gone.');
  const sellerId = str(product.ownerUid);
  const purchaseId = `website_${docId}_${Date.now()}`;
  const now = FieldValue.serverTimestamp();
  const images = Array.isArray(product.imageUrls) ? product.imageUrls.map(str) : [];
  const batch = db.batch();
  batch.set(db.collection('users').doc(uid).collection('purchases').doc(purchaseId), {
    orderId: 'website',
    productId,
    title: str(product.title) || 'Untitled',
    sellerId,
    imageUrl: images[0] ?? null,
    purchasedAt: now,
    delivered: true,
    reviewed: false,
    selfReported: true,
    buyUrl: str(product.buyUrl),
  });
  batch.set(db.collection('users').doc(uid), { purchaseCount: FieldValue.increment(1) }, { merge: true });
  if (sellerId && sellerId !== uid) {
    batch.set(
      db.collection('sellers').doc(sellerId).collection('buyers').doc(uid),
      { lastOrderId: 'website', lastPurchaseAt: now, count: FieldValue.increment(1) },
      { merge: true },
    );
  }
  await batch.commit();
  logger.info('Website purchase reported', { uid, productId });
  return { purchaseId };
}

/**
 * The owner removes their own product. No approval or link needed: a
 * business that lost its listing must still be able to take its products
 * down, and ownership is checked below.
 */
export async function deleteDirectoryProduct(uid: string, id: string): Promise<void> {
  const db = getFirestore();
  const ref = db.collection('directoryProducts').doc(id);
  const existing = (await ref.get()).data();
  if (!existing) return;
  if (existing.ownerUid !== uid) throw new HttpsError('permission-denied', 'That product is not yours.');
  const batch = db.batch();
  batch.delete(ref);
  batch.delete(db.collection('posts').doc(`dirproduct_${id}`));
  await batch.commit();
  logger.info('Directory product removed', { uid, id });
}
