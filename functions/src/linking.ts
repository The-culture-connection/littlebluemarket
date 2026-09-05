import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions';

import { adminGraphQL } from './shopify/token.ts';

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
 * a seller is a ShipTurtle *vendor*. Matching a seller against the customer
 * table would silently fail and hand them an empty buyer profile.
 */
export async function linkStoreAccounts(
  uid: string,
  verifiedEmail: string,
): Promise<{ linkedCustomer: boolean; linkedVendor: boolean }> {
  const email = verifiedEmail.trim().toLowerCase();
  const db = getFirestore();
  const user = db.collection('users').doc(uid);

  // Stored so the order pipeline can attribute a website order by email.
  await user.set(
    { emailLower: email, linkedAt: FieldValue.serverTimestamp() },
    { merge: true },
  );

  const customerId = await findShopifyCustomer(email);
  if (customerId) {
    await user.set({ shopifyCustomerId: customerId }, { merge: true });
    await backfillOrders(uid, customerId);
  }

  const vendorId = await findVendor(email);
  if (vendorId) {
    // Deliberately not `isSeller`. Seller status is a grant, written to
    // `sellers/{uid}` by `sellerClaimVendor` and mirrored into a custom claim;
    // see Planning/backend-architecture.md §8. Recording the vendor id here is
    // still useful — it is what the roster path will match on once Shipturtle
    // can be queried.
    await user.set({ shipturtleVendorId: vendorId }, { merge: true });
  }

  logger.info('Linked a store account', {
    uid,
    linkedCustomer: Boolean(customerId),
    linkedVendor: Boolean(vendorId),
  });

  return {
    linkedCustomer: Boolean(customerId),
    linkedVendor: Boolean(vendorId),
  };
}

async function findShopifyCustomer(email: string): Promise<string | null> {
  const query = [
    'query FindCustomer($query: String!) {',
    '  customers(first: 2, query: $query) {',
    '    nodes { id email }',
    '  }',
    '}',
  ].join('\n');

  const result = await adminGraphQL<{
    customers: { nodes: Array<{ id: string; email: string }> };
  }>(query, { query: `email:${email}` });

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

/**
 * Pulls an existing customer's order history into the app.
 *
 * Without this, someone with three years of purchases sees an empty profile on
 * their first sign-in, which is exactly the moment they decide whether the app
 * is worth keeping.
 */
async function backfillOrders(uid: string, customerId: string): Promise<void> {
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
    '            title',
    '            quantity',
    '            product { id }',
    '            vendor',
    '          }',
    '        }',
    '      }',
    '    }',
    '  }',
    '}',
  ].join('\n');

  const result = await adminGraphQL<{
    customer: {
      orders: {
        nodes: Array<{
          id: string;
          name: string;
          processedAt: string;
          lineItems: {
            nodes: Array<{
              title: string;
              quantity: number;
              product: { id: string } | null;
              vendor: string | null;
            }>;
          };
        }>;
      };
    } | null;
  }>(query, { id: customerId });

  const orders = result.customer?.orders.nodes ?? [];
  if (orders.length === 0) return;

  const db = getFirestore();
  const batch = db.batch();
  let items = 0;

  for (const order of orders) {
    const orderId = order.id.split('/').pop() ?? order.id;
    for (const [index, line] of order.lineItems.nodes.entries()) {
      const productId = line.product?.id.split('/').pop() ?? '';
      items += line.quantity;
      batch.set(
        db
          .collection('users')
          .doc(uid)
          .collection('purchases')
          .doc(`${orderId}_${index}`),
        {
          orderId,
          productId,
          title: line.title,
          sellerId: '',
          purchasedAt: new Date(order.processedAt),
          // A historical order is assumed delivered; nothing here can tell,
          // and showing it as in transit would be worse.
          delivered: true,
          reviewed: false,
          backfilled: true,
        },
        { merge: true },
      );
    }
  }

  // Set rather than increment: this runs once per account, and a backfill that
  // ran twice must not double the count.
  batch.set(
    db.collection('users').doc(uid),
    { purchaseCount: items, backfilledAt: FieldValue.serverTimestamp() },
    { merge: true },
  );

  await batch.commit();
  logger.info('Backfilled order history', { uid, orders: orders.length, items });
}

/**
 * Whether this email belongs to a vendor.
 *
 * ⚠️ **Outstanding.** The vendor lookup needs the ShipTurtle API key and,
 * more importantly, a decision about what actually identifies a vendor. Until
 * both exist this checks the `vendorMappings` collection, so a vendor can be
 * linked by hand today and automatically once the rule is settled — the call
 * site does not change either way.
 */
async function findVendor(email: string): Promise<string | null> {
  const doc = await getFirestore()
    .collection('vendorMappings')
    .doc(email.replace(/[^a-z0-9]+/g, '-'))
    .get();
  const vendorId = doc.data()?.vendorId;
  return typeof vendorId === 'string' ? vendorId : null;
}
