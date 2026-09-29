import { HttpsError } from 'firebase-functions/v2/https';

import { DONATION_CHIP_IN_HANDLE, DONATION_ROUND_UP_HANDLE } from './config.ts';
import { toCents } from './orders.ts';
import {
  DONATION_ATTRIBUTE,
  numericId,
  type DonationLine,
} from './donation_lines.ts';
import { storefrontGraphQL } from './shopify/storefront.ts';

/**
 * Chipping in, and rounding up.
 *
 * Both are ordinary Shopify lines through the same Storefront checkout the
 * app already uses, which is what keeps this the store's business rather
 * than an in-app charge the app stores would have something to say about.
 *
 * Its own file, not `cart.ts`, for two reasons: this phase is built in a
 * parallel worktree and `cart.ts` is money, so the smaller the footprint
 * there the better; and none of this touches a cart the buyer owns.
 *
 * **Why not `buyNow`.** The plan assumed Chip in could reuse it, because it
 * "already takes any variant". It does not, quite: `buyNow` resolves the
 * variant out of the Firestore catalogue mirror and throws when the product
 * is not in it. Mirroring the donation products would put them in the app's
 * own search and browse, which is precisely what a hidden donation product
 * must not be in. So these ask the Storefront API for the product by handle
 * and never touch the mirror (Grace, 2026-09-29: "go with 2").
 */

/** A donation product's variant, as the Storefront API gives it. */
export interface DonationVariant {
  /** The full `gid://shopify/ProductVariant/...`, which is what a cart wants. */
  id: string;
  priceCents: number;
}

/** Round a subtotal up to the next whole dollar. Pure. */
export function roundUpCentsFor(subtotalCents: number): number {
  if (!Number.isFinite(subtotalCents) || subtotalCents <= 0) return 0;
  const remainder = Math.round(subtotalCents) % 100;
  // A subtotal already on a dollar rounds up a whole one rather than giving
  // nothing: "round up" with a zero line is a switch that appears to do
  // nothing, which reads as broken.
  return remainder === 0 ? 100 : 100 - remainder;
}

/**
 * Whether a round-up is one this code is willing to send. Pure.
 *
 * 1 to 100 inclusive: the top of the range is a whole dollar, which is what
 * a subtotal already on a dollar produces. Anything else is a bug upstream
 * and is refused rather than charged.
 */
export function isValidRoundUpCents(cents: unknown): cents is number {
  return (
    typeof cents === 'number' &&
    Number.isInteger(cents) &&
    cents >= 1 &&
    cents <= 100
  );
}

/** The variant whose price is exactly this amount, or null. Pure. */
export function pickAmountVariant(
  variants: DonationVariant[],
  amountCents: number,
): DonationVariant | null {
  return variants.find((v) => v.priceCents === amountCents) ?? null;
}

const VARIANTS_QUERY = [
  'query DonationProduct($handle: String!) {',
  '  product(handle: $handle) {',
  '    variants(first: 50) { nodes { id price { amount } } }',
  '  }',
  '}',
].join('\n');

/**
 * A donation product's variants, straight from the storefront.
 *
 * Read live rather than mirrored, so the price the buyer is charged is the
 * price in Shopify and there is no second copy to drift. These are two
 * products read a handful of times a day, not a catalogue.
 */
export async function donationVariants(handle: string): Promise<DonationVariant[]> {
  if (!handle) return [];
  const result = await storefrontGraphQL<{
    product: { variants: { nodes: Array<{ id: string; price: { amount: string } }> } } | null;
  }>(VARIANTS_QUERY, { handle });

  const nodes = result.product?.variants?.nodes ?? [];
  return nodes.map((node) => ({ id: node.id, priceCents: toCents(node.price.amount) }));
}

const PRODUCT_ID_QUERY =
  'query DonationId($handle: String!) { product(handle: $handle) { id } }';

/** Cached per instance: two products, and a webhook should not ask twice. */
let productIds: { ids: Set<string>; at: number } | null = null;

/** Long enough that a busy day asks once, short enough that a fix lands. */
const PRODUCT_ID_TTL_MS = 6 * 60 * 60 * 1000;

/**
 * The donation products' Shopify ids, for recognising a gift bought on the
 * website.
 *
 * Empty when the handles are not configured, which is also how the whole
 * feature stays invisible in production until Grace sets them.
 */
export async function donationProductIds(): Promise<Set<string>> {
  const { chipIn, roundUp } = donationHandles();
  if (!chipIn && !roundUp) return new Set<string>();
  if (productIds && Date.now() - productIds.at < PRODUCT_ID_TTL_MS) {
    return productIds.ids;
  }

  const ids = new Set<string>();
  for (const handle of [chipIn, roundUp]) {
    if (!handle) continue;
    const result = await storefrontGraphQL<{ product: { id: string } | null }>(
      PRODUCT_ID_QUERY,
      { handle },
    );
    const gid = result.product?.id;
    if (gid) ids.add(numericId(gid));
  }
  productIds = { ids, at: Date.now() };
  return ids;
}

/** Forgets the cached ids. Tests only. */
export function resetDonationProductIds(): void {
  productIds = null;
}
/** The configured handles, trimmed. Empty means the feature is off. */
export function donationHandles(): { chipIn: string; roundUp: string } {
  return {
    chipIn: DONATION_CHIP_IN_HANDLE.value().trim(),
    roundUp: DONATION_ROUND_UP_HANDLE.value().trim(),
  };
}

/**
 * The cart line for a round-up, or null when it is not configured.
 *
 * One variant at a penny, bought `cents` times, so Shopify does the
 * arithmetic and there is one price to get wrong instead of ninety-nine.
 */
export async function roundUpLine(cents: number): Promise<DonationLine | null> {
  const { roundUp } = donationHandles();
  if (!roundUp) return null;
  if (!isValidRoundUpCents(cents)) {
    throw new HttpsError('invalid-argument', `A round-up of ${cents} is not between 1 and 100.`);
  }
  const variants = await donationVariants(roundUp);
  const penny = variants[0];
  if (!penny) {
    throw new HttpsError('failed-precondition', `No variant on ${roundUp}.`);
  }
  if (penny.priceCents !== 1) {
    // Guarded because the quantity *is* the amount: a variant priced at
    // anything but a penny would charge a multiple of the intended sum.
    throw new HttpsError(
      'failed-precondition',
      `${roundUp} must have a single one-cent variant; found ${penny.priceCents}.`,
    );
  }
  // It says what it is, so the paid webhook needs no lookup for anything
  // the app itself sent.
  return {
    merchandiseId: penny.id,
    quantity: cents,
    attributes: [{ key: DONATION_ATTRIBUTE, value: 'round-up' }],
  };
}

/**
 * A checkout for one chip-in, on its own. The buyer's cart is untouched:
 * giving something is not shopping, and it must not empty a basket.
 */
export async function chipInCheckout(
  uid: string,
  amountCents: number,
): Promise<{ cartId: string; checkoutUrl: string }> {
  const { chipIn } = donationHandles();
  if (!chipIn) {
    throw new HttpsError('failed-precondition', 'Chipping in is not switched on yet.');
  }
  const variants = await donationVariants(chipIn);
  const variant = pickAmountVariant(variants, amountCents);
  if (!variant) {
    const offered = variants.map((v) => v.priceCents).join(', ');
    throw new HttpsError(
      'invalid-argument',
      `No ${chipIn} variant at ${amountCents} cents. It has: ${offered || 'none'}.`,
    );
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
      lines: [
        {
          merchandiseId: variant.id,
          quantity: 1,
          attributes: [{ key: DONATION_ATTRIBUTE, value: 'chip-in' }],
        },
      ],
      // The same attribution the rest of checkout uses, so the paid webhook
      // knows whose gift this was without guessing from an email.
      attributes: [{ key: 'app_uid', value: uid }],
    },
  });

  const errors = result.cartCreate.userErrors;
  if (errors?.length) {
    throw new HttpsError('failed-precondition', errors[0]?.message ?? 'Checkout refused that.');
  }
  const created = result.cartCreate.cart;
  if (!created) throw new HttpsError('internal', 'Checkout did not return a cart.');
  return { cartId: created.id, checkoutUrl: created.checkoutUrl };
}
