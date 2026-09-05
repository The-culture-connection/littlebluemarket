import { getAuth } from 'firebase-admin/auth';
import { getFirestore, Timestamp } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions';

import { SHIPTURTLE_API_KEY, SHIPTURTLE_AUTH_HEADER, SHIPTURTLE_BASE_URL } from './config.ts';
import { grantSellerDirect, normalizeVendorName } from './sellers.ts';
import { authHeaders, listVendorUsers } from './shipturtle_api.ts';

/**
 * Selling without a claim code.
 *
 * A Shipturtle vendor is a company with users; each user has an email. The
 * vendor string Shopify needs is not on the roster, but it is on every
 * product the company has, so the two together answer "which vendor string
 * does this verified email sell as?" — and that is the grant.
 *
 * Refusals are deliberate, not gaps:
 *  - one email on two companies: ambiguous, no grant (a claim code decides);
 *  - a company with no products yet: no vendor string to grant, no grant;
 *  - a vendor string already claimed by another account: no grant.
 */

const VENDORS_DOC = '_internal/shipturtleVendors';
const TTL_MS = 15 * 60 * 1000;

/** company id → the vendor strings its products carry. */
export async function vendorStringsByCompany(
  fetchImpl: typeof fetch = fetch,
): Promise<Map<string, string[]>> {
  const db = getFirestore();
  const ref = db.doc(VENDORS_DOC);
  const cached = (await ref.get()).data() as
    | { fetchedAt?: Timestamp; byCompany?: Record<string, string[]> }
    | undefined;
  if (cached?.fetchedAt && cached.byCompany && Date.now() - cached.fetchedAt.toMillis() < TTL_MS) {
    return new Map(Object.entries(cached.byCompany));
  }

  let key = '';
  try {
    key = SHIPTURTLE_API_KEY.value();
  } catch {
    key = '';
  }
  if (!key) return new Map();
  const base = SHIPTURTLE_BASE_URL.value().replace(/\/$/, '');
  const res = await fetchImpl(`${base}/api/v3/fetch-product-data/parent`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Accept: 'application/json', ...authHeaders(key, SHIPTURTLE_AUTH_HEADER.value() || 'Authorization') },
    body: JSON.stringify({ start: 0, length: 1000 }),
  });
  if (!res.ok) {
    logger.warn('Shipturtle products request failed', { status: res.status });
    return new Map();
  }
  const json = (await res.json()) as { data?: Array<{ company_id?: unknown; vendor?: unknown }> };
  const map = new Map<string, string[]>();
  for (const row of json.data ?? []) {
    const company = String(row.company_id ?? '');
    const vendor = String(row.vendor ?? '').trim();
    if (!company || !vendor) continue;
    const list = map.get(company) ?? [];
    if (!list.includes(vendor)) list.push(vendor);
    map.set(company, list);
  }
  await ref.set({ fetchedAt: Timestamp.now(), byCompany: Object.fromEntries(map) });
  return map;
}

export type GrantDecision = { grant: true; vendorName: string } | { grant: false; reason: string };

/** Pure: whether a roster match becomes a grant, and as which vendor string. */
export function grantDecision(input: {
  uid: string;
  companyMatches: number;
  vendorStrings: string[];
  reservedBy: string | null;
}): GrantDecision {
  if (input.companyMatches !== 1) {
    return { grant: false, reason: input.companyMatches === 0 ? 'not on the roster' : 'email belongs to more than one vendor company' };
  }
  const strings = [...new Set(input.vendorStrings.map((s) => s.trim()).filter(Boolean))];
  if (strings.length === 0) return { grant: false, reason: 'the vendor has no products yet, so no vendor string is known' };
  if (strings.length > 1) return { grant: false, reason: `the vendor's products carry more than one vendor string (${strings.join(', ')})` };
  if (input.reservedBy && input.reservedBy !== input.uid) return { grant: false, reason: 'that vendor string is already claimed by another account' };
  return { grant: true, vendorName: strings[0]! };
}

/** Grants seller status from the roster for one verified account, if it can. */
export async function autoGrantFromRoster(
  uid: string,
  email: string,
  companyId: string,
  fetchImpl: typeof fetch = fetch,
): Promise<{ vendorName: string } | { reason: string }> {
  const byCompany = await vendorStringsByCompany(fetchImpl);
  const strings = byCompany.get(companyId) ?? [];
  const db = getFirestore();
  let reservedBy: string | null = null;
  if (strings.length === 1) {
    const reserved = await db.collection('vendorNames').doc(normalizeVendorName(strings[0]!)).get();
    reservedBy = reserved.exists ? String(reserved.data()?.uid ?? '') : null;
  }
  const decision = grantDecision({ uid, companyMatches: 1, vendorStrings: strings, reservedBy });
  if (!decision.grant) {
    logger.info('Roster match did not become a grant', { uid, companyId, reason: decision.reason });
    return { reason: decision.reason };
  }
  await grantSellerDirect({ uid, email, vendorName: decision.vendorName, shipturtleVendorId: companyId, method: 'roster' });
  return { vendorName: decision.vendorName };
}

/**
 * The scheduled sweep: every roster email that belongs to a verified app
 * account that is not yet a seller gets the grant. Sign-up order does not
 * matter — a vendor added to Shipturtle after they joined the app is
 * picked up here.
 */
export async function syncVendorRoster(fetchImpl: typeof fetch = fetch): Promise<{ roster: number; granted: number; skipped: number }> {
  const roster = (await listVendorUsers(fetchImpl)) ?? [];
  const byEmail = new Map<string, Set<string>>();
  for (const user of roster) {
    const set = byEmail.get(user.email) ?? new Set<string>();
    set.add(user.companyId);
    byEmail.set(user.email, set);
  }
  let granted = 0;
  let skipped = 0;
  for (const [email, companies] of byEmail) {
    if (companies.size !== 1) {
      skipped += 1;
      continue;
    }
    let account;
    try {
      account = await getAuth().getUserByEmail(email);
    } catch {
      skipped += 1; // no app account with that email yet
      continue;
    }
    if (!account.emailVerified || account.customClaims?.seller === true) {
      skipped += 1;
      continue;
    }
    const result = await autoGrantFromRoster(account.uid, email, [...companies][0]!, fetchImpl);
    if ('vendorName' in result) granted += 1;
    else skipped += 1;
  }
  logger.info('Roster sweep', { roster: roster.length, granted, skipped });
  return { roster: roster.length, granted, skipped };
}
