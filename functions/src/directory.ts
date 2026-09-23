import { FieldValue, getFirestore, Timestamp } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions';
import { HttpsError } from 'firebase-functions/v2/https';

import {
  credentialsFromParams,
  indexEntriesFromWp,
  listingFromWp,
  orderFromWc,
  pickWpUser,
  wcGet,
  wpBase,
  wpConfigured,
  wpFetch,
  wpGet,
  type DirectoryListingRecord,
  type ListingIndexEntry,
  type WcOrderRecord,
  type WpUser,
} from './wordpress.ts';
import { titleWords } from './catalog.ts';

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
 * `users/{uid}/directoryOrders/{wcOrderId}`; the member's directory listings
 * to the public mirror `directoryListings/{wpPostId}`.
 *
 * The mirror carries only what the site already shows without a password
 * (`context=view`): the business's own website, phone, email and address as
 * the listing publishes them. Nothing from `context=edit` reaches Firestore.
 */

/** A tap on the button asks again after this long. */
export const MANUAL_MIN_AGE_MS = 10 * 60_000;
/** The silent launch-time call asks again after this long. */
export const AUTO_MIN_AGE_MS = 6 * 3_600_000;
/** An account the site never heard of is re-checked silently this often. */
export const NOT_FOUND_RECHECK_MS = 7 * 86_400_000;
/** Category, tag and location names change rarely. */
export const TERM_CACHE_TTL_MS = 24 * 3_600_000;
/**
 * The owner index. littlebluecart.com blanks every `?author=` query (an
 * anti-enumeration plugin), so "which listings are this member's" is answered
 * from an index of every listing's owner, built from the listing pages the
 * site does answer: a full crawl every six hours, a changed-since delta in
 * between.
 */
export const INDEX_DOC = '_internal/wpListingIndex';
export const INDEX_FULL_TTL_MS = 6 * 3_600_000;
export const INDEX_DELTA_MIN_AGE_MS = 10 * 60_000;
/** How far back a delta looks past the last refresh, for clock skew. */
export const INDEX_DELTA_OVERLAP_MS = 60 * 60_000;
const EVERY_STATUS = 'publish,pending,draft,private,future';

export const LISTING_TAXONOMIES = ['vendors_dir_cat', 'vendors_dir_tag', 'vendors_loc_loc'] as const;
export type ListingTaxonomy = (typeof LISTING_TAXONOMIES)[number];

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
  /** Set once the listing has filled the profile (Stage 13). */
  profileAppliedAt?: Timestamp;
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

// ---------------------------------------------------------------- listings

export type TermNames = Record<ListingTaxonomy, Record<string, string>>;

/**
 * The public mirror document for one listing. Pure. Term ids become names
 * here so a phone never needs the taxonomy; an id with no known name is
 * dropped rather than shown as a number.
 */
export function listingMirrorDoc(
  record: DirectoryListingRecord,
  ownerUid: string,
  names: TermNames,
  imageUrl: string,
): Record<string, unknown> {
  const resolve = (taxonomy: ListingTaxonomy, ids: number[]) =>
    ids.map((id) => names[taxonomy]?.[String(id)] ?? '').filter(Boolean);
  const address = record.businessAddress;
  return {
    ownerUid,
    wpUserId: record.wpAuthorId,
    title: record.title,
    slug: record.slug,
    status: record.status,
    link: record.link,
    website: record.website,
    email: record.email,
    phone: record.phone,
    storeLink: record.storeLink,
    locationLabel: record.locationLabel,
    street: address?.street ?? '',
    city: address?.city ?? '',
    state: address?.state ?? '',
    zip: address?.zip ?? '',
    address: address?.display ?? '',
    categories: resolve('vendors_dir_cat', record.categoryIds),
    tags: resolve('vendors_dir_tag', record.tagIds),
    locations: resolve('vendors_loc_loc', record.locationIds),
    plan: record.plan,
    description: record.description,
    imageUrl,
    updatedAt: wcTimestamp(record.modified) ?? FieldValue.serverTimestamp(),
    refreshedAt: FieldValue.serverTimestamp(),
  };
}

/**
 * The feed entry a published listing makes for itself, the way a live
 * product does (`autoPostFor` in catalog.ts): posted as the owner, id derived
 * from the listing so a re-sync updates rather than duplicates. `createdAt`
 * is added by the caller only on first creation, so a six-hourly re-sync
 * does not float the post back to the top of the feed.
 */
export function directoryPostFor(record: DirectoryListingRecord, ownerUid: string): Record<string, unknown> {
  return {
    kind: 'directory',
    authorId: ownerUid,
    listingId: String(record.wpPostId),
    title: record.title,
    tags: [],
    auto: true,
    likeCount: FieldValue.increment(0),
    commentCount: FieldValue.increment(0),
  };
}

/** Which term ids a set of listings needs names for, per taxonomy. Pure. */
export function termIdsNeeded(records: DirectoryListingRecord[]): Record<ListingTaxonomy, number[]> {
  const cat = new Set<number>();
  const tag = new Set<number>();
  const loc = new Set<number>();
  for (const r of records) {
    r.categoryIds.forEach((id) => cat.add(id));
    r.tagIds.forEach((id) => tag.add(id));
    r.locationIds.forEach((id) => loc.add(id));
  }
  return { vendors_dir_cat: [...cat], vendors_dir_tag: [...tag], vendors_loc_loc: [...loc] };
}

// ------------------------------------------------------------- owner index

/** The stored index: listing id → owner, last change, status. */
export type StoredIndex = Record<string, { a: number; m: string; s: string }>;

/** Folds crawled rows into the index. Pure. */
export function mergeIndex(existing: StoredIndex, rows: ListingIndexEntry[]): StoredIndex {
  const out: StoredIndex = { ...existing };
  for (const row of rows) out[String(row.id)] = { a: row.author, m: row.modified, s: row.status };
  return out;
}

/**
 * WordPress roles that mean "this person runs the site", not "this person
 * has a listing". A listing's author is whoever typed it in, and on
 * littlebluecart.com that is usually staff rather than the business.
 */
export const SITE_ROLES = ['administrator', 'editor', 'shop_manager'];

/**
 * More listings than any one business plausibly has. A directory member
 * owns a handful; the site's own account authors hundreds.
 */
export const MAX_OWNED_LISTINGS = 25;

/**
 * Why this WordPress user must not be handed listing ownership, or null.
 *
 * **This is the guard that was missing on 2026-09-24.** A member linked by
 * a verified email, correctly, to WordPress user 6 — `lbcerin`,
 * role `administrator`, and the author of all 263 listings on the site,
 * because staff enter them on the businesses' behalf. The app concluded she
 * owned the entire directory: it mirrored 263 listings under her uid, posted
 * 263 feed posts as her, and renamed her profile after the first listing it
 * found. Every step did exactly what it was told.
 *
 * The email match is not wrong and is not the thing to fix: it is her
 * address, on that account. What was missing is the idea that authorship is
 * not ownership. Two independent checks, because either alone would have
 * stopped it and neither catches everything: a role that runs the site, and
 * a volume no real business reaches.
 *
 * Pure, so both are provable without WordPress or Firestore.
 */
export function listingOwnershipRefusal(input: {
  roles: string[];
  listingCount: number;
}): string | null {
  const role = input.roles
    .map((r) => r.trim().toLowerCase())
    .find((r) => SITE_ROLES.includes(r));
  if (role) {
    return `the website account is a ${role}, and a listing's author is whoever typed it in`;
  }
  if (input.listingCount > MAX_OWNED_LISTINGS) {
    return `the website account authored ${input.listingCount} listings, more than the ${MAX_OWNED_LISTINGS} one business plausibly has`;
  }
  return null;
}

/** The listing ids one member owns, per the index. Pure. */
export function listingIdsOf(index: StoredIndex, wpUserId: number): number[] {
  return Object.entries(index)
    .filter(([, v]) => v.a === wpUserId)
    .map(([id]) => Number(id))
    .filter((id) => Number.isFinite(id));
}

/** What kind of refresh the index needs. Pure. */
export function indexRefreshKind(
  stored: { fullAt?: number; updatedAt?: number } | undefined,
  now: number,
): 'full' | 'delta' | 'none' {
  if (!stored?.fullAt || now - stored.fullAt >= INDEX_FULL_TTL_MS) return 'full';
  if (!stored.updatedAt || now - stored.updatedAt >= INDEX_DELTA_MIN_AGE_MS) return 'delta';
  return 'none';
}

// ----------------------------------------------------------------- lookups

export interface Lookups {
  user: (emailLower: string) => Promise<WpUser | null>;
  customer: (emailLower: string) => Promise<number | null>;
  ordersByCustomer: (customerId: number) => Promise<WcOrderRecord[]>;
  ordersByEmail: (emailLower: string) => Promise<WcOrderRecord[]>;
  /** Every listing's owner, one row per listing; `since` narrows to those changed after it. */
  crawlIndex: (since?: string) => Promise<ListingIndexEntry[]>;
  /** These listings, in every status the credential can see. */
  listingsByIds: (ids: number[]) => Promise<DirectoryListingRecord[]>;
  /** Names for these term ids; unknown ids simply missing. */
  termNames: (taxonomy: ListingTaxonomy, ids: number[]) => Promise<Record<string, string>>;
  /** The public URL of a media item, or ''. */
  mediaUrl: (mediaId: number) => Promise<string>;
  /**
   * Public URLs for many media items at once, keyed by id; ids the site
   * will not answer for are simply missing.
   *
   * WordPress answers a hundred media records in one request, so the
   * whole-directory crawl asks that way. One request per image is what put
   * the first production run over the function's nine-minute ceiling.
   */
  mediaUrls: (ids: number[]) => Promise<Record<string, string>>;
}

export function defaultLookups(): Lookups {
  const base = wpBase();
  const orders = (json: unknown): WcOrderRecord[] =>
    (Array.isArray(json) ? json : [])
      .map((o) => orderFromWc(o, base))
      .filter((o): o is WcOrderRecord => o !== null);
  const records = (json: unknown): DirectoryListingRecord[] =>
    (Array.isArray(json) ? json : [])
      .map((l) => listingFromWp(l))
      .filter((l): l is DirectoryListingRecord => l !== null);
  return {
    user: async (email) => {
      // WooCommerce's customers endpoint lists every WordPress user when
      // asked for every role, and littlebluecart.com answers it; core's
      // wp/v2/users comes back blank there. WooCommerce first, core second.
      const creds = credentialsFromParams();
      if (creds.wcKey && creds.wcSecret) {
        try {
          const page = await wcGet<unknown>('customers', { email, role: 'all', per_page: 20 });
          const hit = pickWpUser(page.data, email);
          if (hit) return hit;
        } catch (error) {
          logger.warn('WooCommerce customer lookup failed; trying core users', { message: (error as Error).message });
        }
      }
      try {
        return pickWpUser(await wpGet<unknown>('wp/v2/users', { search: email, context: 'edit', per_page: 100 }), email);
      } catch (error) {
        logger.warn('Core users lookup unavailable', { message: (error as Error).message });
        return null;
      }
    },
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
    crawlIndex: async (since) => {
      const creds = credentialsFromParams();
      const withApp = Boolean(creds.appUser && creds.appPassword);
      const rows: ListingIndexEntry[] = [];
      for (let page = 1; page <= 100; page++) {
        const query: Record<string, string | number | undefined> = {
          _fields: 'id,author,modified_gmt,status',
          per_page: 100,
          page,
          modified_after: since,
          // Pending and draft listings are only visible with the credential.
          status: withApp ? EVERY_STATUS : undefined,
        };
        let result;
        try {
          result = await wpFetch<unknown>('wp/v2/vendors_dir_ltg', { auth: withApp ? 'app' : 'none', query });
        } catch (error) {
          // Past the last page WordPress answers 400 rest_post_invalid_page_number.
          if (/WP 400 /.test((error as Error).message) && page > 1) break;
          throw error;
        }
        rows.push(...indexEntriesFromWp(result.data));
        const totalPages = result.totalPages ?? page;
        if (page >= totalPages) break;
      }
      return rows;
    },
    listingsByIds: async (ids) => {
      const creds = credentialsFromParams();
      const withApp = Boolean(creds.appUser && creds.appPassword);
      const out: DirectoryListingRecord[] = [];
      for (let i = 0; i < ids.length; i += 100) {
        const page = await wpFetch<unknown[]>('wp/v2/vendors_dir_ltg', {
          auth: withApp ? 'app' : 'none',
          // context=view on purpose: edit context drops drts_fields.
          query: { include: ids.slice(i, i + 100).join(','), per_page: 100, context: 'view', status: withApp ? EVERY_STATUS : undefined },
        });
        out.push(...records(page.data));
      }
      return out;
    },
    termNames: async (taxonomy, ids) => {
      if (!ids.length) return {};
      const out: Record<string, string> = {};
      for (let i = 0; i < ids.length; i += 100) {
        const page = await wpFetch<Array<{ id?: unknown; name?: unknown }>>(`wp/v2/${taxonomy}`, {
          auth: 'none',
          query: { include: ids.slice(i, i + 100).join(','), per_page: 100 },
        });
        for (const term of Array.isArray(page.data) ? page.data : []) {
          if (term?.id !== undefined && term.name) out[String(term.id)] = decodeName(String(term.name));
        }
      }
      return out;
    },
    mediaUrls: async (ids) => {
      const out: Record<string, string> = {};
      if (ids.length === 0) return out;
      // One request per hundred images instead of one per image. This is the
      // difference between the whole-directory crawl finishing and hitting
      // the function's nine-minute ceiling (measured on prod, 2026-09-14).
      for (let i = 0; i < ids.length; i += 100) {
        try {
          const page = await wpFetch<unknown[]>('wp/v2/media', {
            auth: 'none',
            query: {
              include: ids.slice(i, i + 100).join(','),
              per_page: 100,
              _fields: 'id,source_url,media_details',
            },
          });
          for (const row of Array.isArray(page.data) ? page.data : []) {
            if (!row || typeof row !== 'object') continue;
            const media = row as {
              id?: unknown;
              source_url?: unknown;
              media_details?: { sizes?: Record<string, { source_url?: unknown }> };
            };
            const id = Number(media.id);
            if (!Number.isFinite(id)) continue;
            const sizes = media.media_details?.sizes;
            const medium =
              sizes?.medium_large?.source_url ?? sizes?.medium?.source_url;
            const url = String(medium ?? media.source_url ?? '');
            if (url) out[String(id)] = url;
          }
        } catch (error) {
          // A batch we cannot read leaves those listings on their Yoast
          // share image, which is what they had before.
          logger.warn('Listing images not readable', {
            count: ids.slice(i, i + 100).length,
            message: (error as Error).message,
          });
        }
      }
      return out;
    },
    mediaUrl: async (mediaId) => {
      try {
        const media = await wpGet<{ source_url?: unknown; media_details?: { sizes?: Record<string, { source_url?: unknown }> } }>(
          `wp/v2/media/${mediaId}`,
          undefined,
          'none',
        );
        const medium = media.media_details?.sizes?.medium_large?.source_url ?? media.media_details?.sizes?.medium?.source_url;
        return String(medium ?? media.source_url ?? '');
      } catch (error) {
        logger.warn('Listing image not readable', { mediaId, message: (error as Error).message });
        return '';
      }
    },
  };
}

function decodeName(name: string): string {
  return name.replace(/&amp;/g, '&').replace(/&#0?39;/g, "'").replace(/&#8217;/g, '’');
}

/**
 * Term names, from the `_internal/wpTerms/{taxonomy}` cache when it has them
 * and is under a day old, from the site otherwise. Only the ids asked for
 * are fetched, so the cache grows with use rather than mirroring the whole
 * taxonomy up front.
 */
export async function cachedTermNames(
  taxonomy: ListingTaxonomy,
  ids: number[],
  lookups: Lookups,
  now = Date.now(),
): Promise<Record<string, string>> {
  if (!ids.length) return {};
  const db = getFirestore();
  const ref = db.doc(`_internal/wpTerms/taxonomies/${taxonomy}`);
  const snap = await ref.get();
  const data = snap.data() as { names?: Record<string, string>; updatedAt?: Timestamp } | undefined;
  const fresh = data?.names && now - millis(data.updatedAt) < TERM_CACHE_TTL_MS;
  const names: Record<string, string> = fresh ? { ...data!.names } : {};
  const missing = ids.filter((id) => !names[String(id)]);
  if (missing.length) {
    Object.assign(names, await lookups.termNames(taxonomy, missing));
    await ref.set({ names, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
  }
  return names;
}

/**
 * The owner index, refreshed as needed: a full crawl when it is missing or
 * six hours old, a changed-since delta when it is ten minutes old, the
 * stored copy otherwise. `force` skips the ten-minute wait (a person who just
 * added a listing is tapping Refresh).
 */
export async function ownerIndex(lookups: Lookups, { now = Date.now(), force = false } = {}): Promise<StoredIndex> {
  const db = getFirestore();
  const ref = db.doc(INDEX_DOC);
  const stored = (await ref.get()).data() as
    | { entries?: StoredIndex; fullAt?: Timestamp; updatedAt?: Timestamp }
    | undefined;
  const fullAt = millis(stored?.fullAt);
  const updatedAt = millis(stored?.updatedAt);
  let kind = indexRefreshKind({ fullAt: fullAt || undefined, updatedAt: updatedAt || undefined }, now);
  if (kind === 'none' && force) kind = 'delta';
  if (kind === 'none') return stored?.entries ?? {};

  if (kind === 'full') {
    const rows = await lookups.crawlIndex();
    const entries = mergeIndex({}, rows);
    await ref.set({ entries, fullAt: Timestamp.fromMillis(now), updatedAt: Timestamp.fromMillis(now), count: rows.length });
    logger.info('Listing owner index rebuilt', { count: rows.length });
    return entries;
  }
  const since = new Date(updatedAt - INDEX_DELTA_OVERLAP_MS).toISOString().replace(/\.\d{3}Z$/, '');
  const rows = await lookups.crawlIndex(since);
  const entries = mergeIndex(stored?.entries ?? {}, rows);
  await ref.set({ entries, updatedAt: Timestamp.fromMillis(now), count: Object.keys(entries).length }, { merge: true });
  return entries;
}

/**
 * Mirrors one member's listings and removes mirror documents for listings
 * the site no longer has. Returns how many the member has now.
 */
export async function syncListings(
  ownerUid: string,
  wpUserId: number,
  lookups: Lookups,
  options: { force?: boolean } = {},
): Promise<number> {
  const db = getFirestore();
  const index = await ownerIndex(lookups, { force: options.force ?? false });
  const ids = listingIdsOf(index, wpUserId);
  const records = ids.length ? await lookups.listingsByIds(ids) : [];
  const needed = termIdsNeeded(records);
  const names: TermNames = {
    vendors_dir_cat: await cachedTermNames('vendors_dir_cat', needed.vendors_dir_cat, lookups),
    vendors_dir_tag: await cachedTermNames('vendors_dir_tag', needed.vendors_dir_tag, lookups),
    vendors_loc_loc: await cachedTermNames('vendors_loc_loc', needed.vendors_loc_loc, lookups),
  };
  const mirror = db.collection('directoryListings');
  const posts = db.collection('posts');
  const existing = await mirror.where('ownerUid', '==', ownerUid).select().get();
  const keep = new Set(records.map((r) => String(r.wpPostId)));
  const postRefs = records.map((r) => posts.doc(`directory_${r.wpPostId}`));
  const existingPosts = postRefs.length ? await db.getAll(...postRefs) : [];
  const batch = db.batch();
  for (const [i, record] of records.entries()) {
    const featured = record.featuredMediaId ? await lookups.mediaUrl(record.featuredMediaId) : '';
    const imageUrl = featured || record.ogImageUrl;
    batch.set(mirror.doc(String(record.wpPostId)), listingMirrorDoc(record, ownerUid, names, imageUrl), { merge: true });
    // Published listings announce themselves in the feed; anything else
    // (pending, draft, unpublished again) has no business there.
    const postRef = postRefs[i]!;
    const hadPost = existingPosts[i]?.exists ?? false;
    if (record.status === 'publish') {
      batch.set(
        postRef,
        { ...directoryPostFor(record, ownerUid), ...(hadPost ? {} : { createdAt: FieldValue.serverTimestamp() }) },
        { merge: true },
      );
    } else if (hadPost) {
      batch.delete(postRef);
    }
  }
  for (const doc of existing.docs) {
    if (keep.has(doc.id)) continue;
    batch.delete(doc.ref);
    batch.delete(posts.doc(`directory_${doc.id}`));
  }
  await batch.commit();
  return records.length;
}


// ------------------------------------------------- the whole public directory

/**
 * Grace's #2 (2026-09-14): every published listing on littlebluecart.com in
 * the app, before anyone has signed up for anything.
 *
 * What was there before this only mirrored the listings of accounts that had
 * already linked by email (`syncAllDirectoryListings` walks `directory`
 * where status is linked), so a shopper saw nothing until a business joined.
 * This walks the other way round: every published listing the site will
 * answer for, whether or not its owner has ever opened the app.
 *
 * Three things it deliberately does not do:
 *
 *  * **No feed posts.** `syncListings` writes `posts/directory_{id}` for a
 *    published listing so it announces itself in the Market feed. Doing that
 *    here would bury the feed under every business in the directory on day
 *    one. Grace's call: unclaimed listings live under Browse the directory
 *    and in search, and a listing enters the feed when its owner claims it,
 *    which is `syncListings`' job and is untouched.
 *  * **It never blanks an `ownerUid`.** The field is written only when the
 *    author is a linked member, so a claimed listing stays claimed even if
 *    the linked-owner map is empty on this pass.
 *  * **It never touches a pending or draft listing.** Only `publish` is
 *    crawled, which is also all the site answers without the application
 *    password. A stranger must not see a listing its owner has not published.
 */

/** Firestore's cap is 500 writes; leave room for the category rollup. */
const MIRROR_BATCH = 400;

/** How many listings one call will fetch from WordPress at a time. */
const FETCH_CHUNK = 100;

/**
 * How long one call spends walking listings before it hands back a cursor.
 *
 * The function's own ceiling is 540s. The first production run spent all of
 * it and was killed (2026-09-14), so a call now stops well short and says
 * where it got to. 300s leaves room for the batch commits and the rollup
 * that follow the loop.
 */
const CHUNK_BUDGET_MS = 300_000;

/** Where a part-finished crawl left off. */
export const SYNC_DOC = '_internal/publicDirectorySync';

interface SyncProgress {
  /** The published ids to walk, snapshotted when the run started. */
  ids: number[];
  /** How many of [ids] are done. */
  at: number;
  /**
   * The category slugs seen so far, slug -> the directory's own name.
   *
   * Names only, never counts: a chunk that is written and then retried
   * (the call died before it could save) would inflate an accumulated
   * count, and the counts are what the rail shows. They are measured
   * exactly at the end instead, with one aggregation query per category.
   */
  categories: Record<string, string>;
  claimed: number;
  /** Everything mirrored before this is stale once the run finishes. */
  startedAt: Timestamp;
}

export interface PublicDirectoryResult {
  listings: number;
  categories: number;
  claimed: number;
  removed: number;
  /** False when there is more to do; call again with [nextCursor]. */
  done: boolean;
  /** Opaque: hand it straight back. Null when finished. */
  nextCursor: string | null;
  /** How many listings this call wrote, as opposed to the run's total. */
  processedNow: number;
  /** The run's total so far, finished or not. */
  processed: number;
  total: number;
}

/** "Bath, Beauty & Wellness" -> "bath-beauty-and-wellness". */
export function categorySlug(name: string): string {
  return name
    .toLowerCase()
    .replace(/&/g, ' and ')
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 80);
}

/**
 * The extra fields a listing needs to be browsable and searchable, on top of
 * what `listingMirrorDoc` already writes.
 *
 * `titleWords` and `titleLower` are the same two fields the `catalog` mirror
 * carries, built by the same helper, so `FirestoreSearchRepository`'s pattern
 * ("a word anywhere in the title, plus a prefix scan for a phrase") works
 * over directory listings without inventing a second search scheme.
 */
export function browseFields(
  record: DirectoryListingRecord,
  categories: string[],
  ownerUid: string,
): Record<string, unknown> {
  const city = record.businessAddress?.city ?? '';
  return {
    categorySlugs: categories.map(categorySlug).filter(Boolean),
    titleLower: record.title.toLowerCase(),
    // The business's name, its categories and its city, so searching any of
    // the three finds it. Capped the way the catalog caps `searchWords`.
    titleWords: titleWords(`${record.title} ${categories.join(' ')} ${city}`).slice(0, 120),
    unclaimed: ownerUid === '',
  };
}

/**
 * Takes a directory back off an account that should never have been given
 * it, and undoes what that produced.
 *
 * The repair for 2026-09-24: 263 listings mirrored under one member and 263
 * feed posts written as her. `listingOwnershipRefusal` stops it happening
 * again; this puts back what already happened.
 *
 * Deliberately narrow. It releases only listings whose `ownerUid` is this
 * account and only the `directory_*` posts that go with them, so anything
 * the person actually wrote — their own shoutouts, their cart posts, a
 * listing that genuinely is theirs and was linked some other way — is left
 * alone. `dryRun` counts without writing, which is how to look before
 * leaping on production.
 */
export async function releaseDirectoryFrom(
  uid: string,
  options: { dryRun?: boolean } = {},
): Promise<{ listings: number; posts: number; dryRun: boolean }> {
  const db = getFirestore();
  const dryRun = options.dryRun ?? false;
  const mine = await db.collection('directoryListings').where('ownerUid', '==', uid).get();

  let posts = 0;
  if (!dryRun) {
    for (let i = 0; i < mine.docs.length; i += 200) {
      const batch = db.batch();
      for (const doc of mine.docs.slice(i, i + 200)) {
        // The mirror row stays: the listing is real and the directory should
        // still show it. It simply is not this person's.
        batch.set(doc.ref, { ownerUid: '', unclaimed: true }, { merge: true });
        batch.delete(db.collection('posts').doc(`directory_${doc.id}`));
        posts += 1;
      }
      await batch.commit();
    }

    await db.collection('directory').doc(uid).set(
      {
        ownsListings: false,
        ownershipRefusedReason: 'released by an admin',
        listingCount: 0,
        refreshedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    // The profile was renamed after one of those listings. Nobody but the
    // person can say what their name should be, so the flag that let it be
    // applied is cleared and the name is left for them to set.
    await db.collection('directory').doc(uid).set({ profileAppliedAt: null }, { merge: true });
  } else {
    posts = mine.size;
  }

  logger.warn('Directory released from an account', { uid, listings: mine.size, posts, dryRun });
  return { listings: mine.size, posts, dryRun };
}

/** wpUserId -> uid, for the accounts that have linked. */
async function linkedOwners(): Promise<Map<number, string>> {
  const snapshot = await getFirestore().collection('directory').where('status', '==', 'linked').get();
  const map = new Map<number, string>();
  for (const doc of snapshot.docs) {
    const data = doc.data() as DirectoryDoc & { ownsListings?: unknown };
    // The account that manages the directory authored everybody's listings.
    // Linking it is right; handing it the directory is not.
    if (data.ownsListings === false) continue;
    const wpUserId = Number(data.wpUserId);
    if (Number.isFinite(wpUserId) && wpUserId > 0) map.set(wpUserId, doc.id);
  }
  return map;
}

/**
 * Starts a run: refreshes the owner index and snapshots every published id.
 *
 * Paid once per run, not once per call, which is why a continuation reads
 * the stored progress instead of crawling again.
 */
async function beginRun(lookups: Lookups, force: boolean): Promise<SyncProgress> {
  const index = await ownerIndex(lookups, { force });
  const ids = Object.entries(index)
    .filter(([, row]) => row.s === 'publish')
    .map(([id]) => Number(id))
    .filter((id) => Number.isFinite(id) && id > 0)
    .sort((a, b) => a - b);
  const progress: SyncProgress = {
    ids,
    at: 0,
    categories: {},
    claimed: 0,
    startedAt: Timestamp.now(),
  };
  await getFirestore().doc(SYNC_DOC).set(progress);
  return progress;
}

/**
 * Grace's #2 (2026-09-14): every published listing on littlebluecart.com in
 * the app, before anyone has signed up for anything.
 *
 * What was there before this only mirrored the listings of accounts that had
 * already linked by email (`syncAllDirectoryListings` walks `directory`
 * where status is linked), so a shopper saw nothing until a business joined.
 * This walks the other way round: every published listing the site will
 * answer for, whether or not its owner has ever opened the app.
 *
 * **Resumable, because the whole directory does not fit in one call.** The
 * first production attempt was killed at the 540s ceiling. A call now spends
 * at most [CHUNK_BUDGET_MS] walking listings, stores where it got to in
 * [SYNC_DOC], and returns a cursor; the caller keeps calling until `done`.
 * The same shape `adminBackfillBuyerIndex` already uses.
 *
 * Three things it deliberately does not do:
 *
 *  * **No feed posts.** `syncListings` writes `posts/directory_{id}` for a
 *    published listing so it announces itself in the Market feed. Doing that
 *    here would bury the feed under every business in the directory on day
 *    one. Grace's call: unclaimed listings live under Browse the directory
 *    and in search, and a listing enters the feed when its owner claims it,
 *    which is `syncListings`' job and is untouched.
 *  * **It never blanks an `ownerUid`.** The field is written only when the
 *    author is a linked member, so a claimed listing stays claimed even if
 *    the linked-owner map is empty on this pass.
 *  * **It never touches a pending or draft listing.** Only `publish` is
 *    crawled, which is also all the site answers without the application
 *    password. A stranger must not see a listing its owner has not published.
 */
export async function syncPublicDirectory(
  lookups: Lookups = defaultLookups(),
  options: { force?: boolean; cursor?: string | null; budgetMs?: number } = {},
): Promise<PublicDirectoryResult> {
  if (!wpConfigured()) {
    throw new HttpsError(
      'failed-precondition',
      'The Little Blue Cart directory is not connected to this project yet (WP_BASE_URL).',
    );
  }
  const db = getFirestore();
  const mirror = db.collection('directoryListings');
  const budgetMs = options.budgetMs ?? CHUNK_BUDGET_MS;
  const until = Date.now() + budgetMs;

  // A cursor continues the run in progress; no cursor starts a fresh one.
  let progress: SyncProgress;
  if (options.cursor) {
    const stored = (await db.doc(SYNC_DOC).get()).data() as SyncProgress | undefined;
    if (!stored || !Array.isArray(stored.ids)) {
      throw new HttpsError('failed-precondition', 'That directory pull has expired. Start it again.');
    }
    progress = { ...stored, at: Number(options.cursor) || 0 };
  } else {
    progress = await beginRun(lookups, options.force ?? false);
  }

  const owners = await linkedOwners();
  const categories = progress.categories ?? {};
  let claimed = progress.claimed ?? 0;
  let processedNow = 0;
  let at = progress.at;
  let writes = 0;
  let batch = db.batch();
  const flush = async () => {
    if (writes === 0) return;
    await batch.commit();
    batch = db.batch();
    writes = 0;
  };

  while (at < progress.ids.length && Date.now() < until) {
    const slice = progress.ids.slice(at, at + FETCH_CHUNK);
    const records = await lookups.listingsByIds(slice);
    const needed = termIdsNeeded(records);
    const names: TermNames = {
      vendors_dir_cat: await cachedTermNames('vendors_dir_cat', needed.vendors_dir_cat, lookups),
      vendors_dir_tag: await cachedTermNames('vendors_dir_tag', needed.vendors_dir_tag, lookups),
      vendors_loc_loc: await cachedTermNames('vendors_loc_loc', needed.vendors_loc_loc, lookups),
    };
    // Every image for this chunk in one or two requests, rather than one
    // request per listing awaited inside the loop below.
    const mediaIds = records
      .map((r) => r.featuredMediaId)
      .filter((id): id is number => typeof id === 'number' && id > 0);
    const media = await lookups.mediaUrls([...new Set(mediaIds)]);

    // What the mirror already holds for these ids, so a claimed listing's
    // ownerUid survives a pass where the linked-owner map cannot name it.
    const refs = records.map((r) => mirror.doc(String(r.wpPostId)));
    const existing = refs.length ? await db.getAll(...refs) : [];

    for (const [j, record] of records.entries()) {
      if (record.status !== 'publish') continue;
      const was = String((existing[j]?.data() as { ownerUid?: unknown } | undefined)?.ownerUid ?? '');
      const ownerUid = owners.get(record.wpAuthorId) ?? was;
      if (ownerUid) claimed++;

      const featured = record.featuredMediaId ? (media[String(record.featuredMediaId)] ?? '') : '';
      const doc = listingMirrorDoc(record, ownerUid, names, featured || record.ogImageUrl);
      const listingCategories = (doc.categories as string[]) ?? [];
      for (const name of listingCategories) {
        const slug = categorySlug(name);
        if (slug) categories[slug] = name;
      }

      batch.set(refs[j]!, { ...doc, ...browseFields(record, listingCategories, ownerUid) }, { merge: true });
      writes++;
      processedNow++;
      if (writes >= MIRROR_BATCH) await flush();
    }
    at += slice.length;
    // Saved after every chunk, not only when the budget runs out: a call
    // that dies mid-loop then re-walks at most one chunk of a hundred.
    await flush();
    await db.doc(SYNC_DOC).set({ at, categories, claimed }, { merge: true });
  }
  await flush();

  const done = at >= progress.ids.length;
  if (!done) {
    await db.doc(SYNC_DOC).set({ ...progress, at, categories, claimed }, { merge: true });
    logger.info('Public directory pull paused', { at, total: progress.ids.length });
    return {
      listings: progress.ids.length,
      categories: Object.keys(categories).length,
      claimed,
      removed: 0,
      done: false,
      nextCursor: String(at),
      processedNow,
      processed: at,
      total: progress.ids.length,
    };
  }

  // -------- the run is finished: the rollup and the tidying, once

  // Listings the site no longer publishes. Only the unclaimed ones (a
  // claimed listing's lifecycle, pending and draft included, belongs to
  // syncListings), and recognised by not having been refreshed during this
  // run, which costs nothing to track.
  const stale = await mirror
    .where('unclaimed', '==', true)
    .where('refreshedAt', '<', progress.startedAt)
    .select()
    .get();
  let removed = 0;
  for (const doc of stale.docs) {
    batch.delete(doc.ref);
    writes++;
    removed++;
    if (writes >= MIRROR_BATCH) await flush();
  }

  // The rail on the feed reads this instead of counting listings on a phone.
  //
  // Each count is measured with an aggregation query rather than carried
  // through the run: exact whatever happened along the way, including a
  // chunk that was written twice because a call died before saving. One
  // small query per category, and there are tens of them, not thousands.
  const catalogue = db.collection('directoryCategories');
  const before = await catalogue.select().get();
  for (const [slug, name] of Object.entries(categories)) {
    let count = 0;
    try {
      const measured = await mirror
        .where('status', '==', 'publish')
        .where('categorySlugs', 'array-contains', slug)
        .count()
        .get();
      count = measured.data().count;
    } catch (error) {
      logger.warn('Category count failed; leaving the previous number', {
        slug,
        message: (error as Error).message,
      });
      continue;
    }
    batch.set(
      catalogue.doc(slug),
      { name, slug, count, updatedAt: FieldValue.serverTimestamp() },
      { merge: true },
    );
    writes++;
    if (writes >= MIRROR_BATCH) await flush();
  }
  for (const doc of before.docs) {
    if (categories[doc.id]) continue;
    batch.delete(doc.ref);
    writes++;
    if (writes >= MIRROR_BATCH) await flush();
  }
  await flush();

  const result: PublicDirectoryResult = {
    listings: progress.ids.length,
    categories: Object.keys(categories).length,
    claimed,
    removed,
    done: true,
    nextCursor: null,
    processedNow,
    processed: at,
    total: progress.ids.length,
  };
  logger.info('Public directory mirrored', result);
  await db.doc('_internal/publicDirectory').set(
    { ...result, refreshedAt: FieldValue.serverTimestamp() },
    { merge: true },
  );
  await db.doc(SYNC_DOC).delete();
  return result;
}

/** Runs a pull to completion, however many calls that takes. */
export async function syncPublicDirectoryFully(
  lookups: Lookups = defaultLookups(),
  options: { force?: boolean; budgetMs?: number; maxCalls?: number } = {},
): Promise<PublicDirectoryResult> {
  let result = await syncPublicDirectory(lookups, { force: options.force, budgetMs: options.budgetMs });
  for (let call = 0; !result.done && call < (options.maxCalls ?? 40); call++) {
    result = await syncPublicDirectory(lookups, {
      cursor: result.nextCursor,
      budgetMs: options.budgetMs,
    });
  }
  return result;
}

/** The six-hourly pass over every linked owner. */
export async function syncAllDirectoryListings(lookups: Lookups = defaultLookups()): Promise<number> {
  if (!wpConfigured()) return 0;
  const db = getFirestore();
  const linked = await db.collection('directory').where('status', '==', 'linked').get();
  let owners = 0;
  for (const doc of linked.docs) {
    const wpUserId = Number((doc.data() as DirectoryDoc).wpUserId);
    if (!Number.isFinite(wpUserId) || wpUserId <= 0) continue;
    try {
      const count = await syncListings(doc.id, wpUserId, lookups);
      await doc.ref.set({ listingCount: count, listingsRefreshedAt: FieldValue.serverTimestamp() }, { merge: true });
      owners++;
    } catch (error) {
      logger.error('Directory listing sync failed for one owner', { uid: doc.id, message: (error as Error).message });
    }
  }
  return owners;
}

// ------------------------------------------------------- profile from listing

/** What the listing says the profile should be. */
export interface ListingProfile {
  name: string;
  /** The handle before uniqueness: letters and digits, at most 24. */
  handleBase: string;
  bio: string;
  tags: string[];
  /** "City, ST", a state name, or '' for an online-only business. */
  cityState: string;
}

/** `Home/Living` → `#HomeLiving`, `Woman-Owned` → `#WomanOwned`. Pure. */
export function hashtagFor(term: string): string {
  const words = term.split(/[^A-Za-z0-9]+/).filter(Boolean);
  if (!words.length) return '';
  return `#${words.map((w) => w[0]!.toUpperCase() + w.slice(1)).join('')}`;
}

/** `Field Trips Travel & Vacations` → `fieldtripstravelvacations`. Pure. */
export function handleBaseFor(title: string): string {
  const base = title.toLowerCase().replace(/[^a-z0-9]/g, '').slice(0, 24);
  return base || 'business';
}

/**
 * The profile a mirrored listing implies, per Grace's mapping (2026-09-08):
 * title → name and handle; category and tags → hashtags; location → City,
 * State; description, website and owner → bio. Pure, over the mirror
 * document so the names are already resolved.
 */
export function profileFromMirror(
  doc: Record<string, unknown>,
  ownerName: string,
): ListingProfile {
  const str = (v: unknown) => (v === null || v === undefined ? '' : String(v).trim());
  const list = (v: unknown) => (Array.isArray(v) ? v.map(String) : []);
  const title = str(doc.title);
  const city = str(doc.city);
  const state = str(doc.state);
  const locations = list(doc.locations);
  const locationLabel = str(doc.locationLabel);
  let cityState = '';
  if (city && state) cityState = `${city}, ${state}`;
  else if (city) cityState = city;
  else if (locations[0] && !/online|virtual/i.test(locations[0])) cityState = locations[0];
  else if (locationLabel && !/online|virtual/i.test(locationLabel)) cityState = locationLabel.replace(/^\*/, '');

  const tags = [...new Set([...list(doc.categories), ...list(doc.tags)].map(hashtagFor).filter(Boolean))];
  const lines = [str(doc.description), str(doc.website)];
  // The owner's name only when it is a name, not a login.
  if (ownerName && /\s/.test(ownerName)) lines.push(`Owner: ${ownerName}`);
  return {
    name: title,
    handleBase: handleBaseFor(title),
    bio: lines.filter(Boolean).join('\n'),
    tags,
    cityState,
  };
}

/** `foundhouse`, then `foundhouse2`, `foundhouse3`… Pure. */
export function* handleCandidates(base: string): Generator<string> {
  yield base;
  for (let n = 2; n < 1000; n++) yield `${base}${n}`;
}

/** Which of this owner's mirrored listings speaks for the profile: the newest published one, else the newest of any. */
export function pickProfileListing(docs: Array<Record<string, unknown>>): Record<string, unknown> | null {
  if (!docs.length) return null;
  const at = (d: Record<string, unknown>) => millis(d.updatedAt as Timestamp | undefined);
  const sorted = [...docs].sort((a, b) => at(b) - at(a));
  return sorted.find((d) => d.status === 'publish') ?? sorted[0] ?? null;
}

/**
 * Writes the listing's profile onto `users/{uid}` and stamps
 * `directory/{uid}.profileAppliedAt`. Runs once by itself on the first
 * successful link with a listing, and again whenever the person taps
 * "Use my directory listing", so their own later edits are never replaced
 * behind their back. The handle is made unique against everyone else's.
 */
export async function applyListingProfile(uid: string): Promise<{ name: string; handle: string } | null> {
  const db = getFirestore();
  const link = (await db.collection('directory').doc(uid).get()).data() as (DirectoryDoc & { wpName?: string }) | undefined;
  if (!link || link.status !== 'linked') return null;
  const mirrored = await db.collection('directoryListings').where('ownerUid', '==', uid).get();
  const doc = pickProfileListing(mirrored.docs.map((d) => d.data()));
  if (!doc) return null;

  const profile = profileFromMirror(doc, String(link.wpName ?? ''));
  const current = (await db.collection('users').doc(uid).get()).data() ?? {};
  let handle = String(current.handleLower ?? '');
  const already = handle === profile.handleBase || handle.startsWith(profile.handleBase);
  if (!already) {
    handle = profile.handleBase;
    for (const candidate of handleCandidates(profile.handleBase)) {
      const taken = await db.collection('users').where('handleLower', '==', candidate).limit(1).get();
      if (taken.empty || taken.docs[0]!.id === uid) {
        handle = candidate;
        break;
      }
    }
  }

  await db.collection('users').doc(uid).set(
    {
      name: profile.name,
      handle: `@${handle}`,
      handleLower: handle,
      bio: profile.bio,
      tags: profile.tags,
      cityState: profile.cityState,
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
  await db.collection('directory').doc(uid).set({ profileAppliedAt: FieldValue.serverTimestamp() }, { merge: true });
  logger.info('Profile filled from the directory listing', { uid, handle });
  return { name: profile.name, handle: `@${handle}` };
}

// -------------------------------------------------------------------- sync

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
    // A WooCommerce customer id is the WordPress user id, so a member found
    // above is their own customer record whatever role they hold.
    customerId = (await lookups.customer(emailLower)) ?? user?.id ?? null;
    const [byCustomer, byEmail] = await Promise.all([
      customerId === null ? Promise.resolve([]) : lookups.ordersByCustomer(customerId),
      lookups.ordersByEmail(emailLower),
    ]);
    orders = mergeOrders(byCustomer, byEmail, emailLower);
  } else {
    notes.push('Website orders are not set up yet (WC_CONSUMER_KEY / WC_CONSUMER_SECRET).');
  }

  // Authorship is not ownership. Before mirroring anything under this
  // account, ask whether this WordPress user is a business with listings or
  // the staff account that typed everybody's in. See
  // `listingOwnershipRefusal` for the day that distinction was learned.
  let refusal: string | null = null;
  if (user) {
    const index = await ownerIndex(lookups, { force: !auto });
    refusal = listingOwnershipRefusal({
      roles: user.roles,
      listingCount: listingIdsOf(index, user.id).length,
    });
    if (refusal) {
      logger.error('Refused to give an account the directory', {
        uid,
        wpUserId: user.id,
        wpLogin: user.slug,
        roles: user.roles,
        reason: refusal,
      });
      notes.push(
        'Your website account is the one that manages the directory, so the ' +
          'listings on it are not being treated as yours. Get in touch if a ' +
          'listing really is yours.',
      );
    }
  }

  // A tap on the button refreshes the owner index too: the person has
  // usually just added a listing on the website.
  const listings =
    user && !refusal ? await syncListings(uid, user.id, lookups, { force: !auto }) : 0;
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
      // Whether this website account's listings are theirs. False for the
      // account that manages the directory; read by `linkedOwners` so the
      // whole-directory sync cannot re-attach what the link refused.
      ownsListings: user !== null && !refusal,
      ...(refusal ? { ownershipRefusedReason: refusal } : {}),
      wpLogin: user?.slug ?? '',
      wpName: user?.name ?? '',
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

  // Stage 13: the first link with a listing fills the profile. Once, by
  // itself; after that only the button does it.
  if (listings > 0 && !existing?.profileAppliedAt) {
    try {
      await applyListingProfile(uid);
    } catch (error) {
      logger.warn('Profile from listing failed on first link', { uid, message: (error as Error).message });
    }
  }
  return { status: 'linked', orders: orders.length, listings, wpLogin: user?.slug, note };
}
