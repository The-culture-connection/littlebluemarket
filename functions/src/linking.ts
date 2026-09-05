import { getFirestore, FieldValue, Timestamp } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions';

import { adminGraphQL } from './shopify/token.ts';
import { listVendorUsers } from './shipturtle_api.ts';
import { resolveSellerUid, type VendorHints } from './vendors.ts';

/**
 * Links a new app account to whatever already exists in the store.
 *
 * This is what makes the two front doors one product: someone who has been
 * buying on the website for a year signs in with the same email and finds their
 * order history already there. To them it is logging in, not signing up.
 *
 * The security constraint that governs everything here: **the email is taken
 * from the verified auth token, never from the request.** The caller of this
 * module must pass a claim, not a parameter. Accepting a client-supplied
 * address would let anyone type a stranger's email and inherit their order
 * history and their revenue.
 *
 * Buyers and sellers are two independent lookups, because they are two
 * different records in two different systems: a buyer is a Shopify *customer*,
 * a seller is a Shipturtle *vendor*. Matching a seller against the customer
 * table would silently fail and hand them an empty buyer profile.
 *
 * Idempotent. The app calls this whenever it sees a verified, unlinked
 * account, and a retry must not double the purchase count: the order backfill
 * runs once per account, and the webhook path uses the same purchase document
 * ids, so the two can never disagree about one order.
 */

export interface LinkResult {
  linkedCustomer: boolean;
  linkedVendor: boolean;
  backfilledOrders: number;
  backfilledItems: number;
  /** True when nothing new happened: already linked, already backfilled. */
  alreadyLinked: boolean;
}

type GraphQL = <T>(query: string, variables?: Record<string, unknown>) => Promise<T>;
type Resolve = (hints: VendorHints) => Promise<string>;

export interface LinkDeps {
  graphql?: GraphQL;
  resolve?: Resolve;
}

export async function linkStoreAccounts(
  uid: string,
  verifiedEmail: string,
  deps: LinkDeps = {},
): Promise<LinkResult> {
  const graphql = deps.graphql ?? adminGraphQL;
  const resolve = deps.resolve ?? resolveSellerUid;

  const email = verifiedEmail.trim().toLowerCase();
  const db = getFirestore();
  const user = db.collection('users').doc(uid);
  const existing = (await user.get()).data() ?? {};
  const alreadyLinked = Boolean(existing.linkedAt);

  // Stored so the order pipeline can attribute a website order by email.
  //  is stamped at the end, after the lookups: a failed attempt
  // must not look linked, or the app stops retrying.
  await user.set({ emailLower: email }, { merge: true });

  let customerId =
    typeof existing.shopifyCustomerId === 'string' ? existing.shopifyCustomerId : null;
  if (!customerId) {
    customerId = await findShopifyCustomer(email, graphql);
    if (customerId) {
      await user.set({ shopifyCustomerId: customerId }, { merge: true });
    }
  }

  // Once per account. The webhook path increments purchaseCount; this path
  // sets it. Running twice would overwrite webhook increments with a stale
  // total, so it never runs twice.
  let backfilled = { orders: 0, items: 0 };
  if (customerId && !existing.backfilledAt) {
    backfilled = await backfillOrders(uid, customerId, { graphql, resolve });
  }

  let vendorId =
    typeof existing.shipturtleVendorId === 'string' ? existing.shipturtleVendorId : null;
  if (!vendorId) {
    vendorId = await findVendor(email);
    if (vendorId) {
      // Deliberately not `isSeller`. Seller status is a grant, written to
      // `sellers/{uid}` by `sellerClaimVendor` and mirrored into a custom
      // claim; see Planning/backend-architecture.md §8. The vendor id is what
      // the roster path will grant against.
      await user.set({ shipturtleVendorId: vendorId }, { merge: true });
    }
  }

  await user.set({ linkedAt: FieldValue.serverTimestamp() }, { merge: true });

  logger.info('Linked a store account', {
    uid,
    linkedCustomer: Boolean(customerId),
    linkedVendor: Boolean(vendorId),
    backfilledOrders: backfilled.orders,
    alreadyLinked,
  });

  return {
    linkedCustomer: Boolean(customerId),
    linkedVendor: Boolean(vendorId),
    backfilledOrders: backfilled.orders,
    backfilledItems: backfilled.items,
    alreadyLinked,
  };
}

async function findShopifyCustomer(
  email: string,
  graphql: GraphQL,
): Promise<string | null> {
  const query = [
    'query FindCustomer($query: String!) {',
    '  customers(first: 2, query: $query) {',
    '    nodes { id email }',
    '  }',
    '}',
  ].join('\n');

  let result: { customers: { nodes: Array<{ id: string; email: string | null }> } };
  try {
    result = await graphql(query, { query: `email:${email}` });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    if (/protected customer data|not approved to use/i.test(message)) {
      throw new Error(
        'Shopify will not show customer emails to this app yet. Fix: Dev ' +
          'Dashboard -> the app -> Configuration -> Protected customer data ' +
          'access -> request the Name, Email, Phone and Address fields, save, ' +
          'then try again. (' + message + ')',
      );
    }
    throw error;
  }

  const matches = result.customers.nodes.filter(
    (node) => node.email?.toLowerCase() === email,
  );

  // Two customers on one email should not happen; if it does, linking the
  // wrong one is worse than linking neither.
  if (matches.length !== 1) {
    if (matches.length > 1) {
      logger.error('Two store customers share an email', { email });
    }
    return null;
  }
  return matches[0]?.id ?? null;
}

// ------------------------------------------------------------- the backfill

export interface BackfilledOrder {
  id: string;
  name: string;
  processedAt: string;
  lineItems: {
    nodes: Array<{
      id: string;
      title: string;
      quantity: number;
      product: { id: string } | null;
      vendor: string | null;
      image: { url: string } | null;
    }>;
  };
}

/** The tail of a Shopify GID: `gid://shopify/LineItem/123` -> `123`. */
export function gidTail(gid: string): string {
  return gid.split('/').pop() ?? gid;
}

/**
 * The purchase document id, shared with the webhook path (`orders.ts`), so
 * an order seen by both writes one document rather than two.
 */
export function purchaseDocId(orderId: string, lineId: string): string {
  return `${orderId}_${lineId}`;
}

/**
 * Turns past orders into the purchase documents the profile grid reads.
 * Pure apart from the seller lookup, which is injected, so it is testable
 * without Firestore or Shopify.
 */
export async function purchaseDocsFor(
  orders: BackfilledOrder[],
  resolve: Resolve,
): Promise<Array<{ id: string; data: Record<string, unknown> }>> {
  const docs: Array<{ id: string; data: Record<string, unknown> }> = [];
  for (const order of orders) {
    const orderId = gidTail(order.id);
    for (const line of order.lineItems.nodes) {
      const productId = line.product ? gidTail(line.product.id) : '';
      // The vendor string is what ties a past purchase to a seller's profile;
      // the previous version threw it away and every backfilled purchase
      // dead-ended with no seller.
      const sellerId = await resolve({
        vendor: line.vendor ?? undefined,
        productId: productId || undefined,
      });
      docs.push({
        id: purchaseDocId(orderId, gidTail(line.id)),
        data: {
          orderId,
          productId,
          title: line.title,
          sellerId,
          imageUrl: line.image?.url ?? null,
          quantity: line.quantity,
          purchasedAt: Timestamp.fromDate(new Date(order.processedAt)),
          // A historical order is assumed delivered; nothing here can tell,
          // and showing it as in transit would be worse.
          delivered: true,
          reviewed: false,
          backfilled: true,
        },
      });
    }
  }
  return docs;
}

/**
 * Pulls an existing customer's order history into the app.
 *
 * Without this, someone with three years of purchases sees an empty profile on
 * their first sign-in, which is exactly the moment they decide whether the app
 * is worth keeping.
 */
export async function backfillOrders(
  uid: string,
  customerId: string,
  deps: { graphql: GraphQL; resolve: Resolve },
): Promise<{ orders: number; items: number }> {
  const query = [
    'query CustomerOrders($id: ID!) {',
    '  customer(id: $id) {',
    '    orders(first: 50, sortKey: PROCESSED_AT, reverse: true) {',
    '      nodes {',
    '        id',
    '        name',
    '        processedAt',
    '        lineItems(first: 50) {',
    '          nodes {',
    '            id',
    '            title',
    '            quantity',
    '            product { id }',
    '            vendor',
    '            image { url }',
    '          }',
    '        }',
    '      }',
    '    }',
    '  }',
    '}',
  ].join('\n');

  const result = await deps.graphql<{
    customer: { orders: { nodes: BackfilledOrder[] } } | null;
  }>(query, { id: customerId });

  const orders = result.customer?.orders.nodes ?? [];
  const db = getFirestore();
  const userRef = db.collection('users').doc(uid);

  if (orders.length === 0) {
    await userRef.set({ backfilledAt: FieldValue.serverTimestamp() }, { merge: true });
    return { orders: 0, items: 0 };
  }

  const docs = await purchaseDocsFor(orders, deps.resolve);
  const items = docs.reduce((sum, d) => sum + Number(d.data.quantity ?? 0), 0);

  const batch = db.batch();
  for (const doc of docs) {
    batch.set(userRef.collection('purchases').doc(doc.id), doc.data, { merge: true });
  }
  // Set rather than increment: this runs once per account, and a backfill that
  // ran twice must not double the count.
  batch.set(
    userRef,
    { purchaseCount: items, backfilledAt: FieldValue.serverTimestamp() },
    { merge: true },
  );
  await batch.commit();

  logger.info('Backfilled order history', { uid, orders: orders.length, items });
  return { orders: orders.length, items };
}

// --------------------------------------------------------------- the vendor

/**
 * Whether this email belongs to a vendor.
 *
 * The roster from Shipturtle's API answers when it is configured (see
 * `shipturtle_api.ts` and the SHIPTURTLE_VENDORS_PATH param); a merchant-written
 * `vendorMappings` document is the fallback and the manual override. Exactly
 * one roster match or nothing — a wrong link hands someone another seller's
 * catalogue.
 */
async function findVendor(email: string): Promise<string | null> {
  const roster = await listVendorUsers();
  if (roster) {
    const matches = roster.filter((u) => u.email.toLowerCase() === email);
    if (matches.length === 1) {
      logger.info('Vendor matched from the Shipturtle roster', { email });
      return matches[0]!.companyId;
    }
    if (matches.length > 1) {
      logger.error('Two Shipturtle vendor users share an email', { email });
      return null;
    }
  }

  const doc = await getFirestore()
    .collection('vendorMappings')
    .doc(email.replace(/[^a-z0-9]+/g, '-'))
    .get();
  const vendorId = doc.data()?.vendorId;
  return typeof vendorId === 'string' ? vendorId : null;
}
