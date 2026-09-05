import { FieldValue, getFirestore } from 'firebase-admin/firestore';

/**
 * The cart as a public signal.
 *
 * On Little Blue Market there is no like. Adding something to your cart is
 * how you show a maker you love their work, and the product carries two
 * numbers because of it:
 *
 *  - `saveCount`    — how many people have ever added it. Monotonic; the
 *                     "N added" a seller reads as interest.
 *  - `inCartsCount` — how many carts hold it right now. Rises on add, falls
 *                     on remove and on checkout.
 *
 * Both are written only here, from the commerce functions, never by a
 * client: the count is something sellers read, so it has to be true. The
 * per-person marker lives at `catalog/{productId}/carted/{uid}` so a second
 * add by the same person is not a second save.
 */

export interface CartLineLike {
  productId: string;
}

/** Which products gained or lost their last line between two carts. Pure. */
export function markerChanges(
  before: CartLineLike[],
  after: CartLineLike[],
): { added: string[]; removed: string[] } {
  const was = new Set(before.map((l) => l.productId));
  const now = new Set(after.map((l) => l.productId));
  return {
    added: [...now].filter((id) => !was.has(id)),
    removed: [...was].filter((id) => !now.has(id)),
  };
}

/**
 * Applies the markers and counters for a cart change. `saveCount` moves only
 * the first time this person adds a product; `inCartsCount` moves every time
 * the product enters or leaves their cart.
 */
export async function applyMarkerChanges(
  uid: string,
  changes: { added: string[]; removed: string[] },
): Promise<void> {
  if (changes.added.length === 0 && changes.removed.length === 0) return;
  const db = getFirestore();
  const batch = db.batch();

  for (const productId of changes.added) {
    const product = db.collection('catalog').doc(productId);
    const marker = product.collection('carted').doc(uid);
    const existed = (await marker.get()).exists;
    batch.set(marker, { uid, productId, addedAt: FieldValue.serverTimestamp(), active: true }, { merge: true });
    batch.set(
      product,
      {
        inCartsCount: FieldValue.increment(1),
        ...(existed ? {} : { saveCount: FieldValue.increment(1) }),
      },
      { merge: true },
    );
  }
  for (const productId of changes.removed) {
    const product = db.collection('catalog').doc(productId);
    const marker = product.collection('carted').doc(uid);
    const snap = await marker.get();
    // Only a live marker decrements; a stale double-remove cannot drive the
    // count negative.
    if (!snap.exists || snap.data()?.active === false) continue;
    batch.set(marker, { active: false, removedAt: FieldValue.serverTimestamp() }, { merge: true });
    batch.set(product, { inCartsCount: FieldValue.increment(-1) }, { merge: true });
  }
  await batch.commit();
}
