import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { HttpsError } from 'firebase-functions/v2/https';

import { applyMarkerChanges, markerChanges } from './carted.ts';
import { adminGraphQL } from './shopify/token.ts';
import { storefrontGraphQL } from './shopify/storefront.ts';
import { toCents } from './orders.ts';

/**
 * The cart.
 *
 * Lines live in our own Firestore, which is what lets the cart render instantly
 * and offline and survive the storefront being swapped. Only the final handoff
 * — turning those lines into something that can take money — goes to the
 * provider.
 *
 * Prices are read server-side on every mutation. A client-supplied price is the
 * single most obvious thing to tamper with in a commerce app.
 */

interface CartLine {
  id: string;
  productId: string;
  variantId: string;
  title: string;
  variantTitle: string;
  unitPriceCents: number;
  quantity: number;
  sellerUid: string;
  imageUrl?: string | null;
}

interface CartDoc {
  id: string;
  lines: CartLine[];
  shippingCents?: number | null;
  taxCents?: number | null;
  currencyCode: string;
}

function cartRef(uid: string) {
  return getFirestore().collection('carts').doc(uid);
}

async function readCart(uid: string): Promise<CartDoc> {
  const snapshot = await cartRef(uid).get();
  const data = snapshot.data();
  return {
    id: uid,
    lines: (data?.lines ?? []) as CartLine[],
    // Null rather than zero: not knowing shipping yet is different from
    // shipping being free, and showing zero is a lie checkout then corrects.
    shippingCents: (data?.shippingCents ?? null) as number | null,
    taxCents: (data?.taxCents ?? null) as number | null,
    currencyCode: (data?.currencyCode ?? 'USD') as string,
  };
}

async function writeCart(uid: string, lines: CartLine[]): Promise<CartDoc> {
  // The public signal moves with the cart: a product's first line in adds a
  // marker and a count; its last line out removes them.
  const before = await readCart(uid);
  await applyMarkerChanges(uid, markerChanges(before.lines, lines));
  await cartRef(uid).set(
    {
      lines,
      // Any change invalidates the quote. A stale total is worse than none.
      shippingCents: null,
      taxCents: null,
      currencyCode: 'USD',
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
  return readCart(uid);
}

/** The authoritative variant, from the mirror's spec subdocument. */
async function resolveVariant(
  productId: string,
  variantId: string | undefined,
): Promise<{
  variantId: string;
  title: string;
  variantTitle: string;
  unitPriceCents: number;
  available: boolean;
  imageUrl?: string;
}> {
  const db = getFirestore();
  const spec = await db
    .collection('catalog')
    .doc(productId)
    .collection('spec')
    .doc('detail')
    .get();

  const variants = (spec.data()?.variants ?? []) as Array<Record<string, any>>;
  if (variants.length === 0) {
    throw new HttpsError('not-found', 'That listing has no options.');
  }

  // A null variant means the default, which is what the feed's add-to-cart
  // has: a product, and no variant picker in sight.
  const chosen = variantId
    ? variants.find((v) => v.variantId === variantId || v.name === variantId)
    : variants[0];

  if (!chosen) {
    throw new HttpsError('not-found', 'That option is no longer listed.');
  }

  const product = await db.collection('catalog').doc(productId).get();
  const images = (product.data()?.imageUrls ?? []) as string[];

  return {
    variantId: String(chosen.variantId ?? chosen.name),
    title: String(product.data()?.title ?? ''),
    variantTitle: String(chosen.name ?? 'Default'),
    unitPriceCents: Number(chosen.priceCents ?? 0),
    available: chosen.availableForSale !== false,
    imageUrl: images[0],
  };
}

export async function addLine(
  uid: string,
  input: { productId: string; variantId?: string; quantity: number },
): Promise<CartDoc> {
  const variant = await resolveVariant(input.productId, input.variantId);
  if (!variant.available) {
    throw new HttpsError(
      'failed-precondition',
      `${variant.variantTitle} is sold out.`,
    );
  }

  const product = await getFirestore()
    .collection('catalog')
    .doc(input.productId)
    .get();
  if (!product.exists) {
    throw new HttpsError('not-found', 'That listing is gone.');
  }

  const cart = await readCart(uid);
  const existing = cart.lines.find(
    (line) => line.variantId === variant.variantId,
  );
  const quantity = Math.max(1, Math.floor(input.quantity));

  const lines = existing
    ? cart.lines.map((line) =>
        line.variantId === variant.variantId
          ? { ...line, quantity: line.quantity + quantity }
          : line,
      )
    : [
        ...cart.lines,
        {
          id: `${input.productId}_${variant.variantId}`,
          productId: input.productId,
          variantId: variant.variantId,
          title: variant.title,
          variantTitle: variant.variantTitle,
          // The variant's price, never the product's.
          unitPriceCents: variant.unitPriceCents,
          quantity,
          sellerUid: String(product.data()?.sellerId ?? ''),
          imageUrl: variant.imageUrl ?? null,
        },
      ];

  return writeCart(uid, lines);
}

export async function updateLine(
  uid: string,
  lineId: string,
  quantity: number,
): Promise<CartDoc> {
  if (quantity <= 0) return removeLine(uid, lineId);
  const cart = await readCart(uid);
  return writeCart(
    uid,
    cart.lines.map((line) =>
      line.id === lineId ? { ...line, quantity: Math.floor(quantity) } : line,
    ),
  );
}

export async function removeLine(
  uid: string,
  lineId: string,
): Promise<CartDoc> {
  const cart = await readCart(uid);
  return writeCart(
    uid,
    cart.lines.filter((line) => line.id !== lineId),
  );
}

export async function clearCart(uid: string): Promise<CartDoc> {
  return writeCart(uid, []);
}

export interface AddManyResult {
  cart: CartDoc;
  added: string[];
  skipped: Array<{ productId: string; reason: string }>;
}

/**
 * "Add all" from a cart post: every product's default variant, priced
 * server-side, in one write. Items that are gone or sold out are skipped and
 * reported, never silently dropped.
 */
export async function addManyLines(uid: string, productIds: string[]): Promise<AddManyResult> {
  const unique = [...new Set(productIds.map(String).filter(Boolean))].slice(0, 24);
  const cart = await readCart(uid);
  const lines = [...cart.lines];
  const added: string[] = [];
  const skipped: Array<{ productId: string; reason: string }> = [];
  const db = getFirestore();

  for (const productId of unique) {
    try {
      const variant = await resolveVariant(productId, undefined);
      if (!variant.available) {
        skipped.push({ productId, reason: 'sold out' });
        continue;
      }
      const product = await db.collection('catalog').doc(productId).get();
      if (!product.exists || product.data()?.active === false) {
        skipped.push({ productId, reason: 'no longer listed' });
        continue;
      }
      const existing = lines.find((line) => line.variantId === variant.variantId);
      if (existing) {
        existing.quantity += 1;
      } else {
        lines.push({
          id: `${productId}_${variant.variantId}`,
          productId,
          variantId: variant.variantId,
          title: variant.title,
          variantTitle: variant.variantTitle,
          unitPriceCents: variant.unitPriceCents,
          quantity: 1,
          sellerUid: String(product.data()?.sellerId ?? ''),
          imageUrl: variant.imageUrl ?? null,
        });
      }
      added.push(productId);
    } catch (error) {
      skipped.push({
        productId,
        reason: error instanceof HttpsError ? error.message : 'could not be added',
      });
    }
  }

  const next = added.length ? await writeCart(uid, lines) : cart;
  return { cart: next, added, skipped };
}

/**
 * Hands the cart to the storefront and returns where to finish.
 *
 * The attributes are the whole attribution mechanism: `app_uid` on the cart and
 * `app_seller_uid` per line make the resulting order self-identifying, so the
 * paid webhook can credit the right people without guessing from an email.
 */
export async function beginCheckout(
  uid: string,
): Promise<{ cartId: string; checkoutUrl: string }> {
  const cart = await readCart(uid);
  if (cart.lines.length === 0) {
    throw new HttpsError('failed-precondition', 'Your cart is empty.');
  }

  const mutation = [
    'mutation CreateCart($input: CartInput!) {',
    '  cartCreate(input: $input) {',
    '    cart { id checkoutUrl }',
    '    userErrors { message }',
    '  }',
    '}',
  ].join('\n');

  const result = await storefrontGraphQL<{
    cartCreate: {
      cart: { id: string; checkoutUrl: string } | null;
      userErrors: Array<{ message: string }>;
    };
  }>(mutation, {
    input: {
      lines: cart.lines.map((line) => ({
        merchandiseId: `gid://shopify/ProductVariant/${line.variantId}`,
        quantity: line.quantity,
        attributes: [{ key: 'app_seller_uid', value: line.sellerUid }],
      })),
      attributes: [{ key: 'app_uid', value: uid }],
    },
  });

  const errors = result.cartCreate.userErrors;
  if (errors?.length) {
    throw new HttpsError(
      'failed-precondition',
      errors[0]?.message ?? 'Checkout failed.',
    );
  }
  const created = result.cartCreate.cart;
  if (!created) {
    throw new HttpsError('internal', 'Checkout did not return a cart.');
  }

  await cartRef(uid).set(
    {
      providerCartId: created.id,
      checkoutStartedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );

  // Nothing here says the purchase happened. It has not: the person has not
  // reached the checkout page yet, let alone paid.
  return { cartId: cart.id, checkoutUrl: created.checkoutUrl };
}

/**
 * Authoritative stock, live.
 *
 * The one read that must not come from the mirror: being a few minutes stale on
 * stock is how you sell the same thing twice.
 */
export async function liveVariants(productId: string): Promise<
  Array<{
    variantId: string;
    name: string;
    sku: string | null;
    priceCents: number;
    availableForSale: boolean;
    quantityAvailable: number | null;
  }>
> {
  const query = [
    'query Variants($id: ID!) {',
    '  product(id: $id) {',
    '    variants(first: 50) {',
    '      nodes { id title sku price availableForSale inventoryQuantity }',
    '    }',
    '  }',
    '}',
  ].join('\n');

  const result = await adminGraphQL<{
    product: {
      variants: {
        nodes: Array<{
          id: string;
          title: string;
          sku: string | null;
          price: string;
          availableForSale: boolean;
          inventoryQuantity: number | null;
        }>;
      };
    } | null;
  }>(query, { id: `gid://shopify/Product/${productId}` });

  if (!result.product) {
    throw new HttpsError('not-found', 'That listing is gone.');
  }

  return result.product.variants.nodes.map((variant) => ({
    // The seller's edit screen needs the id to change each one in place.
    variantId: variant.id.split('/').pop() ?? variant.id,
    name: variant.title,
    sku: variant.sku ?? null,
    priceCents: toCents(variant.price),
    availableForSale: variant.availableForSale,
    quantityAvailable: variant.inventoryQuantity,
  }));
}
