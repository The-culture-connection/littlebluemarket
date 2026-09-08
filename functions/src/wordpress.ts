import { logger } from 'firebase-functions';

import {
  WC_CONSUMER_KEY,
  WC_CONSUMER_SECRET,
  WP_APP_PASSWORD,
  WP_APP_USER,
  WP_BASE_URL,
  WP_LIVE_OK,
} from './config.ts';
import { toCents } from './orders.ts';

/**
 * littlebluecart.com: the WordPress REST API and WooCommerce's, from the
 * backend only. The phone never talks to WordPress, for the same reason it
 * never talks to Shopify.
 *
 * Two credentials, both server-side: an administrator Application Password
 * (WordPress core, Basic auth) for looking a member up by email and reading
 * their listings in every status, and a WooCommerce consumer key pair (also
 * Basic auth over https) for orders. Nothing here ever logs either; an error
 * quotes the status, the path and WordPress's own `code`/`message`, never a
 * header.
 *
 * The parsers at the bottom are pure and tested against a recorded listing,
 * because the Directories Pro field layout (`drts_fields`) is only known
 * from what the live site returned on 2026-09-08. When a plan carries a field
 * these have not seen, they drop it rather than guess.
 */

// ------------------------------------------------------------------ config

export const LIVE_WP_HOST = 'littlebluecart.com';

/** The configured base, no trailing slash; '' when the directory is off. */
export function wpBase(): string {
  try {
    return WP_BASE_URL.value().trim().replace(/\/+$/, '');
  } catch {
    return '';
  }
}

export function wpConfigured(): boolean {
  return wpBase() !== '';
}

export function wpHost(base: string = wpBase()): string {
  try {
    return new URL(base).host;
  } catch {
    return '';
  }
}

/** The live site's host, or a subdomain of it. */
export function isLiveWpHost(host: string): boolean {
  const h = host.toLowerCase();
  return h === LIVE_WP_HOST || h === `www.${LIVE_WP_HOST}` || h.endsWith(`.${LIVE_WP_HOST}`);
}

/**
 * The live site itself: the live host with nothing after it. Dev must never
 * point here. A staging copy made by the WP Staging plugin lives in a folder
 * under the live domain (`https://littlebluecart.com/dev`), which is a
 * different WordPress with its own database, so that is allowed.
 */
export function isLiveWpBase(base: string): boolean {
  let url: URL;
  try {
    url = new URL(base);
  } catch {
    return false;
  }
  if (!isLiveWpHost(url.host)) return false;
  return url.pathname.replace(/\/+$/, '') === '';
}

/** Whether the merchant has said, in the env, that reading the live site is intended. */
export function liveWpAllowed(): boolean {
  try {
    return WP_LIVE_OK.value().trim().toLowerCase() === 'yes';
  } catch {
    return false;
  }
}

export interface WpCredentials {
  appUser: string;
  appPassword: string;
  wcKey: string;
  wcSecret: string;
}

function quiet(read: () => string): string {
  try {
    return read().trim();
  } catch {
    // A function that did not declare the secret; treat as unset.
    return '';
  }
}

export function credentialsFromParams(): WpCredentials {
  return {
    appUser: quiet(() => WP_APP_USER.value()),
    appPassword: quiet(() => WP_APP_PASSWORD.value()),
    wcKey: quiet(() => WC_CONSUMER_KEY.value()),
    wcSecret: quiet(() => WC_CONSUMER_SECRET.value()),
  };
}

// ------------------------------------------------------------------- fetch

export type WpAuth = 'none' | 'app' | 'wc';
export type Query = Record<string, string | number | boolean | undefined>;

export function basicAuth(user: string, secret: string): string {
  return `Basic ${Buffer.from(`${user}:${secret}`, 'utf8').toString('base64')}`;
}

/** `wp/v2/users` + query → `<base>/wp-json/wp/v2/users?…`; undefined values are skipped. */
export function wpUrl(base: string, path: string, query?: Query): string {
  const url = new URL(`${base.replace(/\/+$/, '')}/wp-json/${path.replace(/^\/+/, '')}`);
  for (const [key, value] of Object.entries(query ?? {})) {
    if (value === undefined) continue;
    url.searchParams.set(key, String(value));
  }
  return url.toString();
}

export interface WpPage<T> {
  data: T;
  /** `X-WP-Total`, when WordPress sent it. */
  total: number | null;
  totalPages: number | null;
}

export interface WpFetchOptions {
  auth?: WpAuth;
  query?: Query;
  timeoutMs?: number;
  /** Overrides the configured base (the doctor and tests). */
  base?: string;
  /** Injected in tests. */
  fetchImpl?: typeof fetch;
  /** Back-off between attempts; tests pass zeros. */
  delaysMs?: number[];
}

function headerInt(headers: Headers, name: string): number | null {
  const raw = headers.get(name);
  if (raw === null) return null;
  const n = Number.parseInt(raw, 10);
  return Number.isFinite(n) ? n : null;
}

function describeBody(text: string): string {
  const trimmed = text.trim();
  if (trimmed.startsWith('<')) return '(an HTML page: a login box, a password wall or a firewall)';
  try {
    const parsed = JSON.parse(trimmed) as { code?: unknown; message?: unknown };
    if (parsed && (parsed.code || parsed.message)) {
      return `${String(parsed.code ?? '')} ${String(parsed.message ?? '')}`.trim().slice(0, 160);
    }
  } catch {
    // not JSON
  }
  return trimmed.slice(0, 160);
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/**
 * One REST call with the right credential, two retries on 429/5xx or a
 * network failure, and an error message that names the path and WordPress's
 * reason. Authorization never appears in a message or a log.
 *
 * A call meant to be public (`auth: 'none'`) that the site refuses with 401
 * or 403 is tried once more with the app credential: a WP Staging copy gates
 * visitors behind a login, and the data is the same either way.
 */
export async function wpFetch<T>(
  path: string,
  options: WpFetchOptions = {},
  credentials: WpCredentials = credentialsFromParams(),
): Promise<WpPage<T>> {
  try {
    return await wpFetchOnce<T>(path, options, credentials);
  } catch (error) {
    const gated = error instanceof Error && /^WP 40[13] /.test(error.message);
    const publicCall = (options.auth ?? 'none') === 'none';
    if (gated && publicCall && credentials.appUser && credentials.appPassword) {
      return wpFetchOnce<T>(path, { ...options, auth: 'app' }, credentials);
    }
    throw error;
  }
}

async function wpFetchOnce<T>(
  path: string,
  options: WpFetchOptions,
  credentials: WpCredentials,
): Promise<WpPage<T>> {
  const base = (options.base ?? wpBase()).replace(/\/+$/, '');
  if (!base) throw new Error('WP_BASE_URL is empty: the directory features are off');
  const auth = options.auth ?? 'none';
  const headers: Record<string, string> = { accept: 'application/json' };
  if (auth === 'app') {
    if (!credentials.appUser) throw new Error('WP_APP_USER is empty');
    if (!credentials.appPassword) throw new Error('WP_APP_PASSWORD is empty');
    headers.authorization = basicAuth(credentials.appUser, credentials.appPassword);
  } else if (auth === 'wc') {
    if (!credentials.wcKey || !credentials.wcSecret) {
      throw new Error('WC_CONSUMER_KEY / WC_CONSUMER_SECRET is empty');
    }
    headers.authorization = basicAuth(credentials.wcKey, credentials.wcSecret);
  }

  const url = wpUrl(base, path, options.query);
  const fetchImpl = options.fetchImpl ?? fetch;
  const delays = options.delaysMs ?? [500, 1500];
  const timeoutMs = options.timeoutMs ?? 15_000;
  let lastError: Error | null = null;

  for (let attempt = 0; attempt <= delays.length; attempt++) {
    if (attempt > 0) await sleep(delays[attempt - 1] ?? 0);
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeoutMs);
    try {
      const res = await fetchImpl(url, { headers, redirect: 'follow', signal: controller.signal });
      const text = await res.text();
      if (res.ok) {
        let data: T;
        try {
          data = JSON.parse(text) as T;
        } catch {
          throw new Error(`WP ${res.status} ${path}: the body is not JSON (${text.trim().slice(0, 80)})`);
        }
        return {
          data,
          total: headerInt(res.headers, 'x-wp-total'),
          totalPages: headerInt(res.headers, 'x-wp-totalpages'),
        };
      }
      const error = new Error(`WP ${res.status} ${path}: ${describeBody(text)}`);
      if (res.status === 429 || res.status >= 500) {
        lastError = error;
        continue;
      }
      throw error;
    } catch (error) {
      const e = error instanceof Error ? error : new Error(String(error));
      if (/^WP \d{3} /.test(e.message)) {
        if (lastError === e) continue;
        throw e;
      }
      // Network-level: retry, then surface without the URL's query (no secret
      // lives there, but the message stays short).
      lastError = new Error(`WP ${path}: ${e.name === 'AbortError' ? `timed out after ${timeoutMs} ms` : e.message}`);
    } finally {
      clearTimeout(timer);
    }
  }
  logger.warn('WordPress call gave up', { path, message: lastError?.message });
  throw lastError ?? new Error(`WP ${path}: failed`);
}

export async function wpGet<T>(path: string, query?: Query, auth: WpAuth = 'app'): Promise<T> {
  return (await wpFetch<T>(path, { auth, query })).data;
}

export async function wcGet<T>(path: string, query?: Query): Promise<WpPage<T>> {
  return wpFetch<T>(`wc/v3/${path.replace(/^\/+/, '')}`, { auth: 'wc', query });
}

// ----------------------------------------------------------------- parsers

function first(value: unknown): unknown {
  return Array.isArray(value) ? value[0] : value;
}

function str(value: unknown): string {
  return value === null || value === undefined ? '' : String(value).trim();
}

function num(value: unknown): number | null {
  const n = typeof value === 'number' ? value : Number.parseInt(str(value), 10);
  return Number.isFinite(n) ? n : null;
}

function ids(value: unknown): number[] {
  if (!Array.isArray(value)) return [];
  return value.map((v) => num(v)).filter((v): v is number => v !== null);
}

const NAMED_ENTITIES: Record<string, string> = {
  amp: '&',
  lt: '<',
  gt: '>',
  quot: '"',
  apos: "'",
  nbsp: ' ',
  hellip: '…',
  ndash: '–',
  mdash: '—',
  rsquo: '’',
  lsquo: '‘',
  rdquo: '”',
  ldquo: '“',
};

/** WordPress renders titles with HTML entities (`&amp;`, `&#8217;`). */
export function decodeEntities(text: string): string {
  return text
    .replace(/&#(\d+);/g, (_, code: string) => String.fromCodePoint(Number(code)))
    .replace(/&#x([0-9a-f]+);/gi, (_, code: string) => String.fromCodePoint(Number.parseInt(code, 16)))
    .replace(/&([a-z]+);/gi, (whole, name: string) => NAMED_ENTITIES[name.toLowerCase()] ?? whole);
}

export interface WpUser {
  id: number;
  email: string;
  slug: string;
  name: string;
  roles: string[];
}

/**
 * The one member whose email is exactly this, out of a `users?search=` page
 * (`search` also matches logins and display names, so the filter is on the
 * email field). Two members on one email link neither, the same rule
 * `linking.ts` applies to store customers.
 */
export function pickWpUser(json: unknown, emailLower: string): WpUser | null {
  if (!Array.isArray(json)) return null;
  const wanted = emailLower.trim().toLowerCase();
  const matches = json
    .filter((u): u is Record<string, unknown> => !!u && typeof u === 'object')
    .filter((u) => str(u.email).toLowerCase() === wanted);
  if (matches.length !== 1) {
    if (matches.length > 1) logger.error('Two WordPress users share an email', { count: matches.length });
    return null;
  }
  const u = matches[0]!;
  const id = num(u.id);
  if (id === null) return null;
  return {
    id,
    email: wanted,
    slug: str(u.slug),
    name: str(u.name),
    roles: Array.isArray(u.roles) ? u.roles.map(String) : [],
  };
}

export interface WpAddress {
  street: string;
  city: string;
  state: string;
  zip: string;
  display: string;
}

function address(value: unknown): WpAddress | null {
  const a = first(value);
  if (!a || typeof a !== 'object') return null;
  const o = a as Record<string, unknown>;
  const out = {
    street: [str(o.street), str(o.street2)].filter(Boolean).join(', '),
    city: str(o.city),
    state: str(o.province),
    zip: str(o.zip),
    display: str(o.display_address) || str(o.address),
  };
  return out.display || out.city || out.street ? out : null;
}

export interface DirectoryListingRecord {
  wpPostId: number;
  slug: string;
  /** publish · pending · draft · private · future */
  status: string;
  link: string;
  title: string;
  wpAuthorId: number;
  featuredMediaId: number | null;
  categoryIds: number[];
  tagIds: number[];
  locationIds: number[];
  website: string;
  email: string;
  phone: string;
  /** The seller's Little Blue Market storefront, when they filled it in. */
  storeLink: string;
  /** Directories Pro's "location", e.g. a state name or "*Online/Virtual Business". */
  locationLabel: string;
  businessAddress: WpAddress | null;
  plan: string;
  planId: number | null;
  modified: string;
}

/** One `vendors_dir_ltg` post as the public REST API returns it (`context=view`). */
export function listingFromWp(json: unknown): DirectoryListingRecord | null {
  if (!json || typeof json !== 'object') return null;
  const o = json as Record<string, unknown>;
  const id = num(o.id);
  const author = num(o.author);
  if (id === null || author === null) return null;
  const title = o.title && typeof o.title === 'object' ? str((o.title as Record<string, unknown>).rendered) : str(o.title);
  const fields = (o.drts_fields && typeof o.drts_fields === 'object' ? o.drts_fields : {}) as Record<string, unknown>;
  const plan = fields.payment_plan && typeof fields.payment_plan === 'object'
    ? (first(fields.payment_plan) as Record<string, unknown>)
    : null;
  const location = address(fields.location_address);
  return {
    wpPostId: id,
    slug: str(o.slug),
    status: str(o.status) || 'publish',
    link: str(o.link),
    title: decodeEntities(title),
    wpAuthorId: author,
    featuredMediaId: num(o.featured_media) || null,
    categoryIds: ids(o.vendors_dir_cat),
    tagIds: ids(o.vendors_dir_tag),
    locationIds: ids(o.vendors_loc_loc),
    website: str(first(fields.field_website)),
    email: str(first(fields.field_email)).toLowerCase(),
    phone: str(first(fields.field_phone)),
    storeLink: str(first(fields.field_little_blue_market_store_link)),
    locationLabel: location?.display ?? '',
    businessAddress: address(fields.field_business_owners_address),
    plan: plan ? str(plan.plan_name) : '',
    planId: plan ? num(plan.plan_id) : null,
    modified: str(o.modified_gmt) || str(o.modified),
  };
}

export interface WcOrderItem {
  id: number;
  name: string;
  quantity: number;
  totalCents: number;
  productId: number | null;
}

export interface WcOrderRecord {
  id: number;
  number: string;
  status: string;
  createdAt: string;
  totalCents: number;
  currency: string;
  billingEmail: string;
  customerId: number;
  items: WcOrderItem[];
  /** The order on the website's My account page. */
  viewUrl: string;
}

/** One WooCommerce order (`wc/v3/orders`). Money is integer cents, via the same parser the Shopify path uses. */
export function orderFromWc(json: unknown, base: string): WcOrderRecord | null {
  if (!json || typeof json !== 'object') return null;
  const o = json as Record<string, unknown>;
  const id = num(o.id);
  if (id === null) return null;
  const billing = (o.billing && typeof o.billing === 'object' ? o.billing : {}) as Record<string, unknown>;
  const lines = Array.isArray(o.line_items) ? o.line_items : [];
  return {
    id,
    number: str(o.number) || String(id),
    status: str(o.status),
    createdAt: str(o.date_created_gmt) || str(o.date_created),
    totalCents: toCents(o.total ?? '0'),
    currency: str(o.currency) || 'USD',
    billingEmail: str(billing.email).toLowerCase(),
    customerId: num(o.customer_id) ?? 0,
    items: lines
      .filter((l): l is Record<string, unknown> => !!l && typeof l === 'object')
      .map((l) => ({
        id: num(l.id) ?? 0,
        name: str(l.name),
        quantity: num(l.quantity) ?? 1,
        totalCents: toCents(l.total ?? '0'),
        productId: num(l.product_id) || null,
      })),
    viewUrl: `${base.replace(/\/+$/, '')}/my-account/view-order/${id}/`,
  };
}
