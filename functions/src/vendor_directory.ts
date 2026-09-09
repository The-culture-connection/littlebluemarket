import { getFirestore, Timestamp } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions';

import { normalizeVendorName } from './sellers.ts';
import { authHeaders, shipturtleConfig } from './shipturtle_config.ts';

/**
 * The vendor directory: which Shipturtle company, and which emails, stand
 * behind each vendor name the shop sells under. Built one vendor at a time,
 * with nothing for anyone to do.
 *
 * Why it exists (2026-09-09): the real Little Blue Market account's
 * `/api/v1/users` never answers, and its product list takes half a minute per
 * thousand rows. But two calls are quick: the product list *filtered by
 * vendor name* (a DataTables column search, ~3 s) gives the vendor's company
 * id, and `/api/v1/companies/{id}` (~2 s) gives that company's contact
 * email. The shop already tells the app every vendor name through Shopify's
 * product webhooks, so each new name is resolved as it appears, and the
 * two-hourly sweep catches up on anything missed.
 *
 * `_internal/vendorDirectory/{vendorKey}`:
 *   { vendorName, companyId, brandName, emails[], resolvedAt }   resolved
 *   { vendorName, failedAt, reason }                             not found / ambiguous / Shipturtle silent
 */

/**
 * A collection path needs an odd number of segments, so the vendors sit one
 * level under the `_internal/vendorDirectory` document (the whole `_internal`
 * tree is closed to clients by the rules).
 */
export const DIRECTORY = '_internal/vendorDirectory/vendors';

/** A vendor not found is tried again after a day; Shipturtle silence after an hour. */
const NOT_FOUND_RETRY_MS = 24 * 60 * 60 * 1000;
const SILENT_RETRY_MS = 60 * 60 * 1000;

export interface VendorEntry {
  vendorKey: string;
  vendorName: string;
  companyId: string;
  brandName: string;
  emails: string[];
}

export interface Resolution {
  entry?: VendorEntry;
  /** Why there is no entry: 'not-found' | 'ambiguous' | 'silent' | 'not-configured'. */
  reason?: string;
}

/** Pure: the company id the filtered product rows agree on, or why not. */
export function pickCompany(
  vendorName: string,
  rows: Array<{ company_id?: unknown; vendor?: unknown }>,
): { companyId: string } | { reason: 'not-found' | 'ambiguous' } {
  const wanted = normalizeVendorName(vendorName);
  const ids = new Set<string>();
  for (const row of rows) {
    if (normalizeVendorName(String(row.vendor ?? '')) !== wanted) continue;
    const id = String(row.company_id ?? '').trim();
    if (id) ids.add(id);
  }
  if (ids.size === 1) return { companyId: [...ids][0]! };
  return { reason: ids.size === 0 ? 'not-found' : 'ambiguous' };
}

/** Pure: the emails a company record carries (one field, sometimes several addresses). */
export function emailsFrom(company: Record<string, unknown>): string[] {
  const raw = [company.email, company.contact_email, company.user_email]
    .map((v) => String(v ?? ''))
    .join(',');
  const out: string[] = [];
  for (const part of raw.split(/[,;\s]+/)) {
    const email = part.trim().toLowerCase();
    if (email.includes('@') && !out.includes(email)) out.push(email);
  }
  return out;
}

/**
 * One vendor name → its company and emails, asked of Shipturtle now.
 * Two requests, about five seconds. Does not touch Firestore.
 */
export async function lookupVendor(
  vendorName: string,
  fetchImpl: typeof fetch = fetch,
): Promise<Resolution> {
  const { key, base, header } = shipturtleConfig();
  if (!key) return { reason: 'not-configured' };
  const headers = { Accept: 'application/json', 'Content-Type': 'application/json', ...authHeaders(key, header) };

  let rows: Array<{ company_id?: unknown; vendor?: unknown }>;
  try {
    const res = await fetchImpl(`${base}/api/v3/fetch-product-data/parent`, {
      method: 'POST',
      headers,
      body: JSON.stringify({
        draw: 1,
        start: 0,
        length: 10,
        columns: [{ data: 'vendor', name: 'vendor', searchable: true, search: { value: vendorName, regex: false } }],
      }),
      signal: AbortSignal.timeout(25_000),
    });
    if (!res.ok) return { reason: 'silent' };
    const json = (await res.json()) as { data?: typeof rows };
    rows = Array.isArray(json.data) ? json.data : [];
  } catch (error) {
    logger.warn('Shipturtle vendor search did not answer', { vendorName, error: String(error).slice(0, 80) });
    return { reason: 'silent' };
  }
  const picked = pickCompany(vendorName, rows);
  if ('reason' in picked) return { reason: picked.reason };

  try {
    const res = await fetchImpl(`${base}/api/v1/companies/${encodeURIComponent(picked.companyId)}`, {
      headers,
      signal: AbortSignal.timeout(20_000),
    });
    if (!res.ok) return { reason: 'silent' };
    const json = (await res.json()) as { data?: Record<string, unknown> };
    const company = json.data ?? {};
    return {
      entry: {
        vendorKey: normalizeVendorName(vendorName),
        vendorName,
        companyId: picked.companyId,
        brandName: String(company.brand_name ?? company.company_name ?? vendorName).trim(),
        emails: emailsFrom(company),
      },
    };
  } catch (error) {
    logger.warn('Shipturtle company lookup did not answer', { vendorName, error: String(error).slice(0, 80) });
    return { reason: 'silent' };
  }
}

/** The stored entry for a vendor name, if resolved. */
export async function directoryEntry(vendorName: string): Promise<VendorEntry | null> {
  const key = normalizeVendorName(vendorName);
  if (!key) return null;
  const doc = await getFirestore().collection(DIRECTORY).doc(key).get();
  const data = doc.data();
  if (!data || typeof data.companyId !== 'string') return null;
  return {
    vendorKey: key,
    vendorName: String(data.vendorName ?? vendorName),
    companyId: data.companyId,
    brandName: String(data.brandName ?? ''),
    emails: Array.isArray(data.emails) ? data.emails.map(String) : [],
  };
}

/**
 * Resolves a vendor name and stores the answer. Returns the entry when one
 * exists (stored earlier or found now); null when it could not be resolved
 * yet. Never throws: Shipturtle's moods must not break a product webhook.
 */
export async function resolveVendor(
  vendorName: string,
  fetchImpl: typeof fetch = fetch,
  options: { force?: boolean } = {},
): Promise<VendorEntry | null> {
  const key = normalizeVendorName(vendorName);
  if (!key) return null;
  const db = getFirestore();
  const ref = db.collection(DIRECTORY).doc(key);
  const existing = (await ref.get()).data();
  if (!options.force && existing) {
    if (typeof existing.companyId === 'string') {
      return {
        vendorKey: key,
        vendorName: String(existing.vendorName ?? vendorName),
        companyId: existing.companyId,
        brandName: String(existing.brandName ?? ''),
        emails: Array.isArray(existing.emails) ? existing.emails.map(String) : [],
      };
    }
    const failedAt = existing.failedAt instanceof Timestamp ? existing.failedAt.toMillis() : 0;
    const retryAfter = existing.reason === 'silent' ? SILENT_RETRY_MS : NOT_FOUND_RETRY_MS;
    if (failedAt && Date.now() - failedAt < retryAfter) return null;
  }

  const result = await lookupVendor(vendorName, fetchImpl);
  if (result.entry) {
    await ref.set({
      vendorName: result.entry.vendorName,
      companyId: result.entry.companyId,
      brandName: result.entry.brandName,
      emails: result.entry.emails,
      resolvedAt: Timestamp.now(),
      failedAt: null,
      reason: null,
    });
    logger.info('Vendor resolved', { vendorName, companyId: result.entry.companyId, emails: result.entry.emails.length });
    return result.entry;
  }
  // Not configured (no key in this function) is not a fact about the vendor:
  // leave no marker, so the next caller that has the key tries at once.
  if (result.reason === 'not-configured') return null;
  await ref.set(
    { vendorName, failedAt: Timestamp.now(), reason: result.reason ?? 'unknown' },
    { merge: true },
  );
  return null;
}

/** Every vendor name the catalog mirror knows, by key. */
export async function catalogVendorNames(): Promise<Map<string, string>> {
  const db = getFirestore();
  const snapshot = await db.collection('catalog').select('vendorName', 'vendorKey').get();
  const names = new Map<string, string>();
  for (const doc of snapshot.docs) {
    const data = doc.data();
    const key = String(data.vendorKey ?? normalizeVendorName(String(data.vendorName ?? '')));
    const name = String(data.vendorName ?? '').trim();
    if (key && name && !names.has(key)) names.set(key, name);
  }
  return names;
}

/**
 * Resolves catalog vendors that have no directory entry yet, for as long as
 * the budget allows (each takes ~5 s). Returns what it resolved this time.
 */
export async function resolvePendingVendors(
  options: { budgetMs: number; fetchImpl?: typeof fetch } = { budgetMs: 60_000 },
): Promise<{ resolved: VendorEntry[]; pending: number; tried: number }> {
  const fetchImpl = options.fetchImpl ?? fetch;
  const deadline = Date.now() + options.budgetMs;
  const db = getFirestore();
  const [names, directory] = await Promise.all([
    catalogVendorNames(),
    db.collection(DIRECTORY).get(),
  ]);
  const known = new Map(directory.docs.map((d) => [d.id, d.data()]));
  const pending: string[] = [];
  for (const [key, name] of names) {
    const entry = known.get(key);
    if (!entry) {
      pending.push(name);
      continue;
    }
    if (typeof entry.companyId === 'string') continue;
    const failedAt = entry.failedAt instanceof Timestamp ? entry.failedAt.toMillis() : 0;
    const retryAfter = entry.reason === 'silent' ? SILENT_RETRY_MS : NOT_FOUND_RETRY_MS;
    if (!failedAt || Date.now() - failedAt >= retryAfter) pending.push(name);
  }
  const resolved: VendorEntry[] = [];
  let tried = 0;
  for (const name of pending) {
    if (Date.now() + 30_000 > deadline) break;
    tried += 1;
    const entry = await resolveVendor(name, fetchImpl, { force: true });
    if (entry) resolved.push(entry);
  }
  if (tried > 0) logger.info('Vendor directory sweep', { tried, resolved: resolved.length, pending: pending.length - tried });
  return { resolved, pending: Math.max(0, pending.length - tried), tried };
}

/**
 * The directory as a roster: one row per (company, email). What the sign-in
 * link and the seller-status tap match an email against when Shipturtle's
 * own user list does not answer.
 */
export async function directoryRoster(): Promise<Array<{ companyId: string; email: string; name: string }>> {
  const snapshot = await getFirestore().collection(DIRECTORY).get();
  const out: Array<{ companyId: string; email: string; name: string }> = [];
  const seen = new Set<string>();
  for (const doc of snapshot.docs) {
    const data = doc.data();
    if (typeof data.companyId !== 'string') continue;
    const emails = Array.isArray(data.emails) ? data.emails.map((e) => String(e).toLowerCase()) : [];
    for (const email of emails) {
      const dedupe = `${data.companyId}|${email}`;
      if (seen.has(dedupe)) continue;
      seen.add(dedupe);
      out.push({ companyId: data.companyId, email, name: String(data.brandName ?? data.vendorName ?? '') });
    }
  }
  return out;
}
