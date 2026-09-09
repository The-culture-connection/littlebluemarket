import { getFirestore, Timestamp } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions';

import { authHeaders, shipturtleConfig } from './shipturtle_config.ts';
import { directoryRoster } from './vendor_directory.ts';

export { authHeaders } from './shipturtle_config.ts';

/**
 * Shipturtle's merchant API, as far as we can see it.
 *
 * Their documentation is a Postman collection, not a spec, so the endpoint
 * that lists vendors is discovered by `scripts/shipturtle-probe.mjs` and set
 * as a param (SHIPTURTLE_VENDORS_PATH) rather than hardcoded. Until it is
 * set, every function here reports "not configured" and nothing depends on
 * it: vendor linking falls back to the vendor directory, claim codes and
 * merchant-written mappings.
 *
 * Nothing here ever logs the token.
 */

export interface VendorUser {
  companyId: string;
  email: string;
  name: string;
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

export function isConfigured(): boolean {
  const { key, path } = shipturtleConfig();
  return Boolean(key && path);
}

const ROSTER_DOC = '_internal/shipturtleRoster';
const ROSTER_TTL_MS = 15 * 60 * 1000;

/**
 * How long one roster request may take, and how long a failure is remembered.
 *
 * Measured 2026-09-08: the real Little Blue Market account's `/api/v1/users`
 * ends in Shipturtle's own 504 after 120 s (the dev account's answers in
 * 4 s). Without a limit that call hung every sign-in (`linkAccounts`) and
 * every "Check my seller status" until the function timed out. So: a bounded
 * wait, a short memory of the failure so a burst of sign-ins does not each
 * pay it, and the vendor directory (`vendor_directory.ts`) as the answer
 * when the user list has none.
 */
export const ROSTER_TIMEOUT_MS = 12 * 1000;
export const ROSTER_FAILURE_TTL_MS = 10 * 60 * 1000;

export interface RosterOptions {
  /** Skip the fresh-cache shortcut: the caller wants what Shipturtle says now. */
  force?: boolean;
  /**
   * Ask the user list again even though it failed in the last ten minutes.
   * The two-hourly sweep does, so a repaired endpoint is noticed; the
   * seller-status tap does not, so it never waits twelve seconds for nothing.
   */
  retryFailed?: boolean;
}

interface RosterCache {
  fetchedAt?: Timestamp;
  users?: VendorUser[];
  failedAt?: Timestamp;
}

/**
 * The vendor roster, or null when Shipturtle is not configured or nothing is
 * known. Shipturtle's user list first (cached fifteen minutes); when that
 * does not answer, the vendor directory, which is built from calls that do.
 */
export async function listVendorUsers(
  fetchImpl: typeof fetch = fetch,
  options: RosterOptions = {},
): Promise<VendorUser[] | null> {
  const { key, base, path, header } = shipturtleConfig();
  if (!key || !path) return null;

  const db = getFirestore();
  const cacheRef = db.doc(ROSTER_DOC);
  const cached = (await cacheRef.get()).data() as RosterCache | undefined;
  const age = cached?.fetchedAt ? Date.now() - cached.fetchedAt.toMillis() : Infinity;
  const cachedUsers = Array.isArray(cached?.users) ? cached.users : null;
  if (!options.force && cachedUsers && age < ROSTER_TTL_MS) return cachedUsers;

  const fromDirectory = async () => {
    const users = await directoryRoster();
    return users.length > 0 ? users : null;
  };

  const recentlyFailed =
    cached?.failedAt && Date.now() - cached.failedAt.toMillis() < ROSTER_FAILURE_TTL_MS;
  if (recentlyFailed && !options.retryFailed) return fromDirectory();

  const endpoint = `${base}${path}`;
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
  await cacheRef.set({ failedAt: Timestamp.now(), failedReason: failure ?? 'unknown' }, { merge: true });
  return fromDirectory();
}

/** For the health check: is the roster reachable, and how big is it? */
export async function probeShipturtle(): Promise<{
  summary: string;
  data: Record<string, unknown>;
}> {
  const { key, base, path } = shipturtleConfig();
  if (!key) throw new Error('SHIPTURTLE_API_KEY is empty');
  if (!path) {
    throw new Error(
      'SHIPTURTLE_VENDORS_PATH is not set: run scripts/probe-shipturtle to find the roster endpoint, then put it in functions/.env.<project-id>',
    );
  }
  const users = await listVendorUsers();
  if (!users) throw new Error(`no answer from ${base}${path}, and the vendor directory is empty so far`);
  const directory = await directoryRoster();
  return {
    summary: `${users.length} vendor user(s) via ${path} · directory ${directory.length} row(s)`,
    data: { count: users.length, endpoint: `${base}${path}`, directory: directory.length },
  };
}
