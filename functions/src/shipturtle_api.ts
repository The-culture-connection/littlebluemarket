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
): Promise<VendorUser[] | null> {
  const { key, base, path, header } = config();
  if (!key || !path) return null;

  const db = getFirestore();
  const cacheRef = db.doc(ROSTER_DOC);
  const cached = (await cacheRef.get()).data() as
    | { fetchedAt?: Timestamp; users?: VendorUser[]; failedAt?: Timestamp }
    | undefined;
  if (
    cached?.fetchedAt &&
    Array.isArray(cached.users) &&
    Date.now() - cached.fetchedAt.toMillis() < ROSTER_TTL_MS
  ) {
    return cached.users;
  }
  if (
    cached?.failedAt &&
    Date.now() - cached.failedAt.toMillis() < ROSTER_FAILURE_TTL_MS
  ) {
    return null;
  }

  const endpoint = `${base}${path}`;
  const rememberFailure = (reason: string) =>
    cacheRef.set(
      { failedAt: Timestamp.now(), failedReason: reason },
      { merge: true },
    );

  let response: Response;
  try {
    response = await fetchImpl(endpoint, {
      headers: { Accept: 'application/json', ...authHeaders(key, header) },
      signal: AbortSignal.timeout(ROSTER_TIMEOUT_MS),
    });
  } catch (error) {
    const reason = error instanceof Error ? error.name : String(error);
    logger.warn('Shipturtle roster request did not answer', {
      endpoint,
      reason,
      timeoutMs: ROSTER_TIMEOUT_MS,
    });
    await rememberFailure(reason);
    return null;
  }
  if (!response.ok) {
    logger.warn('Shipturtle roster request failed', {
      status: response.status,
      endpoint,
    });
    await rememberFailure(`HTTP ${response.status}`);
    return null;
  }
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
