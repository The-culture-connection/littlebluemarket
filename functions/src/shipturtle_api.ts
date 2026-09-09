import { getFirestore, Timestamp } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions';

import {
  SHIPTURTLE_API_KEY,
  SHIPTURTLE_AUTH_HEADER,
  SHIPTURTLE_BASE_URL,
  SHIPTURTLE_VENDORS_PATH,
} from './config.ts';

/**
 * Shipturtle's merchant API, as far as we can see it.
 *
 * Their documentation is a Postman collection, not a spec, so the endpoint
 * that lists vendors is discovered by `scripts/shipturtle-probe.mjs` and set
 * as a param (SHIPTURTLE_VENDORS_PATH) rather than hardcoded. Until it is
 * set, every function here reports "not configured" and nothing depends on
 * it: vendor linking falls back to claim codes and merchant-written mappings.
 *
 * Nothing here ever logs the token.
 */

export interface VendorUser {
  companyId: string;
  email: string;
  name: string;
}

export function authHeaders(key: string, style: string): Record<string, string> {
  switch (style.trim().toLowerCase()) {
    case 'x-api-key':
      return { 'x-api-key': key };
    case 'access-token':
      return { 'access-token': key };
    default:
      return { Authorization: `Bearer ${key}` };
  }
}

/**
 * Pulls vendor users out of whatever shape the API returns. Defensive on
 * purpose: `data`, `vendors`, `users`, a bare array, and nested `users`
 * arrays are all accepted, and anything without an email is dropped.
 */
export function extractVendorUsers(json: unknown): VendorUser[] {
  const out: VendorUser[] = [];
  const seen = new Set<string>();

  const push = (item: Record<string, unknown>, companyId: string) => {
    const email = String(item.email ?? item.user_email ?? item.contact_email ?? '')
      .trim()
      .toLowerCase();
    if (!email || !companyId) return;
    const key = `${companyId}|${email}`;
    if (seen.has(key)) return;
    seen.add(key);
    out.push({
      companyId,
      email,
      name: String(item.name ?? item.company_name ?? item.shop_name ?? ''),
    });
  };

  const visit = (node: unknown) => {
    if (Array.isArray(node)) {
      for (const item of node) visit(item);
      return;
    }
    if (!node || typeof node !== 'object') return;
    const item = node as Record<string, unknown>;
    const companyId = String(
      item.company_id ?? item.vendor_id ?? item.companyId ?? item.id ?? '',
    );
    push(item, companyId);
    for (const key of ['users', 'vendor_users', 'members']) {
      if (Array.isArray(item[key])) {
        for (const sub of item[key] as unknown[]) {
          if (sub && typeof sub === 'object') {
            push(sub as Record<string, unknown>, companyId);
          }
        }
      }
    }
    for (const key of ['data', 'vendors', 'items', 'results']) {
      if (item[key] !== undefined) visit(item[key]);
    }
  };

  visit(json);
  return out;
}

function config() {
  let key = '';
  try {
    key = SHIPTURTLE_API_KEY.value();
  } catch {
    key = '';
  }
  return {
    key,
    base: SHIPTURTLE_BASE_URL.value().replace(/\/$/, ''),
    path: SHIPTURTLE_VENDORS_PATH.value().trim(),
    header: SHIPTURTLE_AUTH_HEADER.value() || 'Authorization',
  };
}

export function isConfigured(): boolean {
  const { key, path } = config();
  return Boolean(key && path);
}

const ROSTER_DOC = '_internal/shipturtleRoster';
const ROSTER_TTL_MS = 15 * 60 * 1000;

/**
 * How long one roster request may take, and how long a failure is remembered.
 *
 * Measured 2026-09-08: the real Little Blue Market account's `/api/v1/users`
 * never answered inside 170 s (the dev account's answers in 4 s). Without a
 * limit that call hung every sign-in (`linkAccounts`) and every "Check my
 * seller status" until the function timed out. So: a bounded wait, and a
 * short memory of the failure so a burst of sign-ins does not each pay it.
 * The fallback is the merchant's `vendorMappings` document and claim codes.
 */
export const ROSTER_TIMEOUT_MS = 12 * 1000;
export const ROSTER_FAILURE_TTL_MS = 10 * 60 * 1000;

/**
 * The vendor roster, or null when Shipturtle is not configured or did not
 * answer. Cached in `_internal` for fifteen minutes so a burst of sign-ins
 * does not hammer their API; a failure is cached for ten.
 */
export async function listVendorUsers(
  fetchImpl: typeof fetch = fetch,
  options: RosterOptions = {},
): Promise<VendorUser[] | null> {
  const { key, base, path, header } = config();
  if (!key || !path) return null;

  const db = getFirestore();
  const cacheRef = db.doc(ROSTER_DOC);
  const cached = (await cacheRef.get()).data() as RosterCache | undefined;
  const age = cached?.fetchedAt ? Date.now() - cached.fetchedAt.toMillis() : Infinity;
  const ttl = cached?.source === 'companies' ? COMPANIES_ROSTER_TTL_MS : ROSTER_TTL_MS;
  const cachedUsers = Array.isArray(cached?.users) ? cached.users : null;
  if (!options.force && cachedUsers && age < ttl) return cachedUsers;

  /** What to hand back when Shipturtle does not answer: the last roster we built, or nothing. */
  const stale = () => (cachedUsers && cachedUsers.length > 0 ? cachedUsers : null);

  const recentlyFailed =
    cached?.failedAt && Date.now() - cached.failedAt.toMillis() < ROSTER_FAILURE_TTL_MS;
  if (recentlyFailed && !options.force && !(options.rebuildBudgetMs && options.rebuildBudgetMs > 0)) {
    return stale();
  }

  const endpoint = `${base}${path}`;
  const rememberFailure = (reason: string) =>
    cacheRef.set(
      { failedAt: Timestamp.now(), failedReason: reason },
      { merge: true },
    );

  let failure: string | null = null;
  try {
    const response = await fetchImpl(endpoint, {
      headers: { Accept: 'application/json', ...authHeaders(key, header) },
      signal: AbortSignal.timeout(ROSTER_TIMEOUT_MS),
    });
    if (response.ok) {
      const users = extractVendorUsers(await response.json());
      await cacheRef.set({
        fetchedAt: Timestamp.now(),
        users,
        count: users.length,
        source: 'users',
        complete: true,
        failedAt: null,
        failedReason: null,
      });
      return users;
    }
    failure = `HTTP ${response.status}`;
    logger.warn('Shipturtle roster request failed', { status: response.status, endpoint });
  } catch (error) {
    failure = error instanceof Error ? error.name : String(error);
    logger.warn('Shipturtle roster request did not answer', {
      endpoint,
      reason: failure,
      timeoutMs: ROSTER_TIMEOUT_MS,
    });
  }
  await rememberFailure(failure ?? 'unknown');

  // The slow road, only when the caller has minutes (the scheduled sweep;
  // never a sign-in, and not the seller-status tap either: the real
  // account's product list arrives at 26–40 s per thousand). Each run
  // continues where the last one stopped, so the roster grows to completion
  // over a few sweeps and then starts over to pick up new vendors.
  if (options.rebuildBudgetMs && options.rebuildBudgetMs > 0) {
    const excludeCompanyId = await merchantCompanyId(fetchImpl);
    const continuing = cached?.source === 'companies';
    const rebuilt = await rosterFromCompanies(fetchImpl, {
      budgetMs: options.rebuildBudgetMs,
      excludeCompanyId: excludeCompanyId ?? undefined,
      startAt: continuing ? (cached?.productCursor ?? 0) : 0,
      known: continuing && cachedUsers ? cachedUsers : [],
    });
    if (rebuilt.users.length > 0 || rebuilt.pages > 0) {
      await cacheRef.set({
        fetchedAt: Timestamp.now(),
        users: rebuilt.users,
        count: rebuilt.users.length,
        source: 'companies',
        complete: rebuilt.complete,
        productCursor: rebuilt.nextStart,
        lastRun: { companies: rebuilt.companies, pages: rebuilt.pages },
        failedAt: null,
        failedReason: null,
      });
      logger.info('Shipturtle roster rebuilt from products and company records', {
        users: rebuilt.users.length,
        newCompanies: rebuilt.companies,
        pages: rebuilt.pages,
        complete: rebuilt.complete,
        nextStart: rebuilt.nextStart,
      });
      return rebuilt.users;
    }
  }
  return stale();
}

export interface RosterOptions {
  /** Skip the fresh-cache shortcut: the caller wants what Shipturtle says now. */
  force?: boolean;
  /**
   * How long the caller can spend rebuilding the roster from products and
   * company records when `/users` does not answer. 0 (the default) means
   * "cache or nothing": the right choice on a sign-in.
   */
  rebuildBudgetMs?: number;
}

interface RosterCache {
  fetchedAt?: Timestamp;
  users?: VendorUser[];
  source?: 'users' | 'companies';
  complete?: boolean;
  /** Where the incremental product crawl continues; 0 once a full pass is done. */
  productCursor?: number;
  failedAt?: Timestamp;
}

/**
 * A roster rebuilt from company records is served from the cache for six
 * hours between sweeps. A sweep (`force`) always runs another instalment.
 */
export const COMPANIES_ROSTER_TTL_MS = 6 * 60 * 60 * 1000;

/** The merchant's own company id (from `/api/v1/me`), so it is never treated as a vendor. */
async function merchantCompanyId(fetchImpl: typeof fetch): Promise<string | null> {
  const { key, base, header } = config();
  if (!key) return null;
  try {
    const res = await fetchImpl(`${base}/api/v1/me`, {
      headers: { Accept: 'application/json', ...authHeaders(key, header) },
      signal: AbortSignal.timeout(10_000),
    });
    if (!res.ok) return null;
    const json = (await res.json()) as { data?: { company_id?: unknown; company?: { id?: unknown } } };
    const id = json.data?.company_id ?? json.data?.company?.id;
    return id === undefined || id === null ? null : String(id);
  } catch {
    return null;
  }
}

/**
 * The roster rebuilt from two endpoints that do answer on the real account:
 * the product list (every product carries its vendor's `company_id` and the
 * vendor string) and the company record (`/api/v1/companies/{id}`, which
 * carries the vendor's contact email, sometimes several separated by commas).
 *
 * Measured 2026-09-09 on the real Little Blue Market account: `/api/v1/users`
 * ends in Shipturtle's own 504 after 120 s, while these two answer in a few
 * seconds each. Vendors with no products yet are not found this way, which
 * is the same limit the grant already has (it needs a vendor string).
 *
 * Pure apart from the fetches: the caller caches the result.
 */
export const PRODUCT_PAGE = 500;

export interface RosterRebuild {
  /** Everything known so far: what was passed in as `known`, plus this run's finds. */
  users: VendorUser[];
  /** Companies looked up in this run. */
  companies: number;
  /** Product pages read in this run. */
  pages: number;
  /** True when the end of the product list was reached in this run. */
  complete: boolean;
  /** Where the next run should continue when `complete` is false. */
  nextStart: number;
}

export async function rosterFromCompanies(
  fetchImpl: typeof fetch = fetch,
  options: {
    concurrency?: number;
    budgetMs?: number;
    excludeCompanyId?: string;
    /** Product offset to start from (a previous run's `nextStart`). */
    startAt?: number;
    /** Users already known; their companies are not looked up again. */
    known?: VendorUser[];
  } = {},
): Promise<RosterRebuild> {
  const known = options.known ?? [];
  const startAt = options.startAt ?? 0;
  const { key, base, header } = config();
  if (!key) return { users: known, companies: 0, pages: 0, complete: false, nextStart: startAt };
  const concurrency = options.concurrency ?? 8;
  const deadline = Date.now() + (options.budgetMs ?? 240_000);
  const headers = {
    Accept: 'application/json',
    'Content-Type': 'application/json',
    ...authHeaders(key, header),
  };
  const PAGE_TIMEOUT_MS = 120_000;

  // 1. Every product's company id and vendor string, a page at a time, for as
  //    long as the budget allows another page.
  const knownCompanies = new Set(known.map((u) => u.companyId));
  const vendorStrings = new Map<string, Set<string>>();
  let pages = 0;
  let complete = false;
  let nextStart = startAt;
  for (let start = startAt; start < 100_000; start += PRODUCT_PAGE) {
    if (Date.now() + PAGE_TIMEOUT_MS > deadline) break;
    let rows: Array<{ company_id?: unknown; vendor?: unknown }>;
    try {
      const res = await fetchImpl(`${base}/api/v3/fetch-product-data/parent`, {
        method: 'POST',
        headers,
        body: JSON.stringify({ start, length: PRODUCT_PAGE }),
        signal: AbortSignal.timeout(PAGE_TIMEOUT_MS),
      });
      if (!res.ok) {
        logger.warn('Shipturtle products request failed', { status: res.status, start });
        break;
      }
      const json = (await res.json()) as { data?: typeof rows };
      rows = Array.isArray(json.data) ? json.data : [];
    } catch (error) {
      logger.warn('Shipturtle products request did not answer', { start, error: String(error).slice(0, 80) });
      break;
    }
    pages += 1;
    nextStart = start + PRODUCT_PAGE;
    for (const row of rows) {
      const company = String(row.company_id ?? '').trim();
      if (!company || company === options.excludeCompanyId || knownCompanies.has(company)) continue;
      const set = vendorStrings.get(company) ?? new Set<string>();
      const vendor = String(row.vendor ?? '').trim();
      if (vendor) set.add(vendor);
      vendorStrings.set(company, set);
    }
    if (rows.length < PRODUCT_PAGE) {
      complete = true;
      nextStart = 0;
      break;
    }
  }

  // 2. Each new company's record, a few at a time.
  const ids = [...vendorStrings.keys()];
  const users: VendorUser[] = [...known];
  const seen = new Set(known.map((u) => `${u.companyId}|${u.email}`));
  let index = 0;
  const worker = async () => {
    while (index < ids.length) {
      if (Date.now() > deadline) {
        complete = false;
        return;
      }
      const companyId = ids[index++]!;
      try {
        const res = await fetchImpl(`${base}/api/v1/companies/${encodeURIComponent(companyId)}`, {
          headers,
          signal: AbortSignal.timeout(20_000),
        });
        if (!res.ok) {
          complete = false;
          continue;
        }
        const json = (await res.json()) as { data?: Record<string, unknown> };
        const company = json.data ?? {};
        const name = String(company.brand_name ?? company.company_name ?? '').trim();
        const emails = String(company.email ?? '')
          .split(/[,;\s]+/)
          .map((e) => e.trim().toLowerCase())
          .filter((e) => e.includes('@'));
        for (const email of emails) {
          const dedupe = `${companyId}|${email}`;
          if (seen.has(dedupe)) continue;
          seen.add(dedupe);
          users.push({ companyId, email, name });
        }
      } catch (error) {
        logger.warn('Shipturtle company lookup failed', { companyId, error: String(error).slice(0, 120) });
        complete = false;
      }
    }
  };
  await Promise.all(Array.from({ length: Math.min(concurrency, ids.length || 1) }, worker));
  return { users, companies: ids.length, pages, complete, nextStart };
}

/** For the health check: is the roster reachable, and how big is it? */
export async function probeShipturtle(): Promise<{
  summary: string;
  data: Record<string, unknown>;
}> {
  const { key, base, path } = config();
  if (!key) throw new Error('SHIPTURTLE_API_KEY is empty');
  if (!path) {
    throw new Error(
      'SHIPTURTLE_VENDORS_PATH is not set: run scripts/probe-shipturtle to find the roster endpoint, then put it in functions/.env.<project-id>',
    );
  }
  const users = await listVendorUsers();
  if (!users) throw new Error(`no answer from ${base}${path}`);
  return {
    summary: `${users.length} vendor user(s) via ${path}`,
    data: { count: users.length, endpoint: `${base}${path}` },
  };
}
