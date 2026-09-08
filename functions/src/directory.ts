import { FieldValue, getFirestore, Timestamp } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions';
import { HttpsError } from 'firebase-functions/v2/https';

import {
  credentialsFromParams,
  orderFromWc,
  pickWpUser,
  wcGet,
  wpBase,
  wpConfigured,
  wpFetch,
  wpGet,
  type WcOrderRecord,
  type WpUser,
} from './wordpress.ts';

/**
 * littlebluecart.com, joined to an app account.
 *
 * The same shape as the store link in `linking.ts`: the email comes from the
 * verified token, never from the request; the answer is a server-only
 * document (`directory/{uid}`, readable by its owner, written only here); and
 * the call is idempotent, so the session can fire it on every launch and a
 * tap on "Link my directory account" can repeat it without side effects.
 *
 * What it finds: the WordPress member with exactly this email (an
 * administrator Application Password can list members), the WooCommerce
 * customer with this email and their orders, plus any guest orders whose
 * billing email is this one. Orders are copied to
 * `users/{uid}/directoryOrders/{wcOrderId}`. Listings are counted here and
 * mirrored in CP-D3.
 */

/** A tap on the button asks again after this long. */
export const MANUAL_MIN_AGE_MS = 10 * 60_000;
/** The silent launch-time call asks again after this long. */
export const AUTO_MIN_AGE_MS = 6 * 3_600_000;
/** An account the site never heard of is re-checked silently this often. */
export const NOT_FOUND_RECHECK_MS = 7 * 86_400_000;

export interface DirectorySyncResult {
  /** `off`: no directory configured; only the silent call gets this, a tap gets an error it can read. */
  status: 'linked' | 'alreadyLinked' | 'notFound' | 'off';
  orders: number;
  listings: number;
  wpLogin?: string;
  /** Something the person can act on, in words. */
  note?: string;
}

/** The `directory/{uid}` document, as stored. */
export interface DirectoryDoc {
  status?: string;
  wpUserId?: number | null;
  wpLogin?: string;
  wcCustomerId?: number | null;
  orderCount?: number;
  listingCount?: number;
  linkedAt?: Timestamp;
  checkedAt?: Timestamp;
  refreshedAt?: Timestamp;
}

function millis(stamp: Timestamp | undefined): number {
  return stamp && typeof stamp.toMillis === 'function' ? stamp.toMillis() : 0;
}

/**
 * Whether the stored answer is fresh enough to hand back without asking the
 * site again. Pure. A manual tap on a "not found" always asks again: the
 * person has usually just fixed the email on the website.
 */
export function reuseStored(
  doc: DirectoryDoc | undefined,
  options: { auto: boolean; now: number },
): DirectorySyncResult | null {
  if (!doc?.status) return null;
  const age = options.now - millis(doc.refreshedAt ?? doc.checkedAt);
  if (doc.status === 'linked') {
    const minAge = options.auto ? AUTO_MIN_AGE_MS : MANUAL_MIN_AGE_MS;
    if (age >= minAge) return null;
    return {
      status: 'alreadyLinked',
      orders: doc.orderCount ?? 0,
      listings: doc.listingCount ?? 0,
      wpLogin: doc.wpLogin,
      note: options.auto ? undefined : 'Checked a few minutes ago. Try again in a few minutes.',
    };
  }
  if (doc.status === 'notFound' && options.auto && age < NOT_FOUND_RECHECK_MS) {
    return { status: 'notFound', orders: 0, listings: 0 };
  }
  return null;
}

/**
 * The orders that are this person's: everything on their customer record,
 * plus guest checkouts whose billing email is exactly theirs. `search=` on
 * WooCommerce is a loose text match (names, notes), hence the exact filter.
 * Pure; newest first; one entry per order id.
 */
export function mergeOrders(
  byCustomer: WcOrderRecord[],
  byEmail: WcOrderRecord[],
  emailLower: string,
): WcOrderRecord[] {
  const out = new Map<number, WcOrderRecord>();
  for (const o of byCustomer) out.set(o.id, o);
  for (const o of byEmail) {
    if (o.billingEmail === emailLower && !out.has(o.id)) out.set(o.id, o);
  }
  return [...out.values()].sort((a, b) => b.createdAt.localeCompare(a.createdAt));
}

/** WooCommerce's `date_created_gmt` has no zone marker; it is UTC. */
export function wcTimestamp(iso: string): Timestamp | null {
  if (!iso) return null;
  const withZone = /[zZ]|[+-]\d\d:\d\d$/.test(iso) ? iso : `${iso}Z`;
  const date = new Date(withZone);
  return Number.isNaN(date.getTime()) ? null : Timestamp.fromDate(date);
}

export interface Lookups {
  user: (emailLower: string) => Promise<WpUser | null>;
  customer: (emailLower: string) => Promise<number | null>;
  ordersByCustomer: (customerId: number) => Promise<WcOrderRecord[]>;
  ordersByEmail: (emailLower: string) => Promise<WcOrderRecord[]>;
  listingCount: (wpUserId: number) => Promise<number>;
}

export function defaultLookups(): Lookups {
  const base = wpBase();
  const orders = (json: unknown): WcOrderRecord[] =>
    (Array.isArray(json) ? json : [])
      .map((o) => orderFromWc(o, base))
      .filter((o): o is WcOrderRecord => o !== null);
  return {
    user: async (email) =>
      pickWpUser(await wpGet<unknown>('wp/v2/users', { search: email, context: 'edit', per_page: 100 }), email),
    customer: async (email) => {
      const page = await wcGet<Array<{ id?: unknown; email?: unknown }>>('customers', { email, per_page: 10 });
      const hit = (Array.isArray(page.data) ? page.data : []).find(
        (c) => String(c.email ?? '').toLowerCase() === email,
      );
      const id = Number(hit?.id);
      return Number.isFinite(id) && id > 0 ? id : null;
    },
    ordersByCustomer: async (customerId) =>
      orders((await wcGet<unknown>('orders', { customer: customerId, per_page: 100 })).data),
    ordersByEmail: async (email) =>
      orders((await wcGet<unknown>('orders', { search: email, per_page: 100 })).data),
    listingCount: async (wpUserId) => {
      try {
        const page = await wpFetch<unknown[]>('wp/v2/vendors_dir_ltg', {
          auth: 'app',
          query: { author: wpUserId, status: 'publish,pending,draft,private,future', context: 'view', per_page: 1 },
        });
        return page.total ?? page.data.length;
      } catch (error) {
        // A site that refuses the status filter still answers for published ones.
        logger.warn('Listing count fell back to published only', { message: (error as Error).message });
        const page = await wpFetch<unknown[]>('wp/v2/vendors_dir_ltg', { auth: 'none', query: { author: wpUserId, per_page: 1 } });
        return page.total ?? page.data.length;
      }
    },
  };
}

export interface SyncOptions {
  /** True for the launch-time call: reuses a fresher answer, never nags. */
  auto?: boolean;
  now?: number;
  lookups?: Lookups;
}

export async function syncDirectory(
  uid: string,
  emailLower: string,
  options: SyncOptions = {},
): Promise<DirectorySyncResult> {
  const auto = options.auto ?? false;
  if (!wpConfigured()) {
    // The launch-time call must stay quiet: every user on every launch would
    // otherwise report an error for a feature that is simply not on yet.
    if (auto) return { status: 'off', orders: 0, listings: 0 };
    throw new HttpsError(
      'failed-precondition',
      'The Little Blue Cart directory is not connected to the app yet.',
    );
  }
  const now = options.now ?? Date.now();
  const lookups = options.lookups ?? defaultLookups();
  const db = getFirestore();
  const ref = db.collection('directory').doc(uid);
  const existing = (await ref.get()).data() as DirectoryDoc | undefined;
  const reused = reuseStored(existing, { auto, now });
  if (reused) return reused;

  const creds = credentialsFromParams();
  const notes: string[] = [];

  let user: WpUser | null = null;
  if (creds.appUser && creds.appPassword) {
    user = await lookups.user(emailLower);
  } else {
    notes.push('Member lookup is not set up yet (WP_APP_USER / WP_APP_PASSWORD).');
  }

  let customerId: number | null = null;
  let orders: WcOrderRecord[] = [];
  if (creds.wcKey && creds.wcSecret) {
    customerId = await lookups.customer(emailLower);
    const [byCustomer, byEmail] = await Promise.all([
      customerId === null ? Promise.resolve([]) : lookups.ordersByCustomer(customerId),
      lookups.ordersByEmail(emailLower),
    ]);
    orders = mergeOrders(byCustomer, byEmail, emailLower);
  } else {
    notes.push('Website orders are not set up yet (WC_CONSUMER_KEY / WC_CONSUMER_SECRET).');
  }

  const listings = user ? await lookups.listingCount(user.id) : 0;
  const note = notes.length ? notes.join(' ') : undefined;
  const found = user !== null || customerId !== null || orders.length > 0;

  if (!found) {
    await ref.set(
      {
        status: 'notFound',
        wpEmailLower: emailLower,
        checkedAt: FieldValue.serverTimestamp(),
        refreshedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    return { status: 'notFound', orders: 0, listings: 0, note };
  }

  const batch = db.batch();
  batch.set(
    ref,
    {
      status: 'linked',
      wpEmailLower: emailLower,
      wpUserId: user?.id ?? null,
      wpLogin: user?.slug ?? '',
      wcCustomerId: customerId,
      orderCount: orders.length,
      listingCount: listings,
      linkedAt: existing?.linkedAt ?? FieldValue.serverTimestamp(),
      checkedAt: FieldValue.serverTimestamp(),
      refreshedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
  const ordersRef = db.collection('users').doc(uid).collection('directoryOrders');
  for (const o of orders) {
    batch.set(
      ordersRef.doc(String(o.id)),
      {
        number: o.number,
        status: o.status,
        createdAt: wcTimestamp(o.createdAt) ?? FieldValue.serverTimestamp(),
        totalCents: o.totalCents,
        currency: o.currency,
        items: o.items.map((i) => ({ name: i.name, quantity: i.quantity, totalCents: i.totalCents, productId: i.productId })),
        viewUrl: o.viewUrl,
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  }
  await batch.commit();
  logger.info('Directory linked', { uid, wpUserId: user?.id ?? null, customerId, orders: orders.length, listings });
  return { status: 'linked', orders: orders.length, listings, wpLogin: user?.slug, note };
}
