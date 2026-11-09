import { getFirestore, Timestamp } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions';

import { SHIPTURTLE_MARKETPLACE_ID } from './config.ts';
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

// ------------------------------------------------------- the company sweep

/**
 * Finds vendors Shipturtle has approved before they have a single product.
 *
 * Why (2026-11-09, luckyducklady@gmail.com): everything above starts from a
 * vendor name the catalog already carries, so a seller approved yesterday,
 * with nothing listed yet, was in no roster the app could read, and
 * "Connect my Market account" told her she was not on the vendor list. The
 * real account's user list (`/api/v1/users`) and company list both time out
 * or 502, and neither takes a filter that works.
 *
 * What does answer, in under a second, is `/api/v1/companies/{id}`, and
 * company ids are handed out in order. Every vendor company under the
 * marketplace carries the marketplace's id as `parent_id`, and `status` is
 * "Active" once the merchant has approved it. So the sweep walks ids,
 * newest first, keeps the Active vendors of this marketplace, and remembers
 * the ones still waiting so their approval is noticed on a later run.
 *
 * State, on the `_internal/vendorDirectory` document:
 *   companyHighest    the newest id ever queued; everything above is new
 *   companyRanges     [{ next, bottom }] still to look at, newest first;
 *                     each is walked down from `next` to `bottom`
 *   companyPending    { id: firstSeenMillis } for vendors not yet Active
 *
 * New ids found on a run go to the front of the queue, so a long first
 * walk never makes this week's vendor wait behind last year's.
 */

const SWEEP_STATE_DOC = '_internal/vendorDirectory';
/** Known marketplaces, so a deploy from a checkout without the env line still sweeps. */
const KNOWN_MARKETPLACES: Record<string, string> = {
  'little-blue-cart-prod': '1066319',
  'little-blue-610e5': '1092564',
};
/** How long a not-yet-Active vendor is re-checked before it is given up on. */
const PENDING_KEEP_MS = 60 * 24 * 60 * 60 * 1000;
/** Ids have holes (a deleted company); this many missing in a row is the end. */
const END_RUN = 8;

export function marketplaceId(): string {
  let id = '';
  try {
    id = SHIPTURTLE_MARKETPLACE_ID.value().trim();
  } catch {
    id = '';
  }
  if (id) return id;
  const project = process.env.GCLOUD_PROJECT ?? process.env.GOOGLE_CLOUD_PROJECT ?? '';
  return KNOWN_MARKETPLACES[project] ?? '';
}

export type CompanyVerdict =
  | { kind: 'vendor'; entry: VendorEntry }
  | { kind: 'pending' }
  | { kind: 'other' };

/**
 * Pure: what one company record means for this marketplace. A vendor of
 * ours that is Active with a brand name and an email becomes a directory
 * entry; one of ours that is not there yet is pending; anything else is
 * not ours.
 */
export function companyVerdict(
  companyId: string,
  company: Record<string, unknown>,
  marketplace: string,
): CompanyVerdict {
  const parent = String(company.parent_id ?? '').trim();
  // The marketplace's own company has itself as parent; it is not a vendor.
  if (!marketplace || parent !== marketplace || companyId === marketplace) return { kind: 'other' };
  const status = String(company.status ?? '').trim().toLowerCase();
  if (status !== 'active') return { kind: 'pending' };
  const brandName = String(company.brand_name ?? company.company_name ?? '').trim();
  const emails = emailsFrom(company);
  if (!brandName || emails.length === 0) return { kind: 'pending' };
  return {
    kind: 'vendor',
    entry: { vendorKey: normalizeVendorName(brandName), vendorName: brandName, companyId, brandName, emails },
  };
}

/** One company: its record, null when the id does not exist, undefined when Shipturtle did not answer. */
async function fetchCompany(
  id: number,
  fetchImpl: typeof fetch,
): Promise<Record<string, unknown> | null | undefined> {
  const { key, base, header } = shipturtleConfig();
  for (let attempt = 0; attempt < 2; attempt++) {
    try {
      const res = await fetchImpl(`${base}/api/v1/companies/${id}`, {
        headers: { Accept: 'application/json', ...authHeaders(key, header) },
        // Normally under a second and a half; a slow one is retried once.
        signal: AbortSignal.timeout(8_000),
      });
      if (res.status === 404) return null;
      if (!res.ok) continue;
      const json = (await res.json()) as { data?: Record<string, unknown> };
      return json.data ?? null;
    } catch {
      // Tried once more, then reported as silence.
    }
  }
  return undefined;
}

/**
 * Stores a vendor found by the sweep. Never takes a vendor key away from a
 * different company: two companies with one brand name is a judgement for
 * the admin card, not for a loop.
 */
async function storeSweptVendor(entry: VendorEntry): Promise<boolean> {
  if (!entry.vendorKey) return false;
  const ref = getFirestore().collection(DIRECTORY).doc(entry.vendorKey);
  const existing = (await ref.get()).data();
  if (existing && typeof existing.companyId === 'string' && existing.companyId !== entry.companyId) {
    logger.warn('Company sweep: brand name already belongs to another company', {
      vendorName: entry.vendorName,
      companyId: entry.companyId,
      existing: existing.companyId,
    });
    return false;
  }
  const unchanged =
    existing?.companyId === entry.companyId &&
    Array.isArray(existing?.emails) &&
    existing.emails.join(',') === entry.emails.join(',');
  if (unchanged) return false;
  await ref.set({
    vendorName: entry.vendorName,
    companyId: entry.companyId,
    brandName: entry.brandName,
    emails: entry.emails,
    resolvedAt: Timestamp.now(),
    source: 'company-sweep',
    failedAt: null,
    reason: null,
  });
  logger.info('Company sweep: vendor added', { vendorName: entry.vendorName, companyId: entry.companyId });
  return true;
}

interface SweepRange {
  next: number;
  bottom: number;
}

interface SweepState {
  companyHighest?: number;
  companyRanges?: SweepRange[];
  companyPending?: Record<string, number>;
}

export interface SweepResult {
  checked: number;
  added: string[];
  pending: number;
  /** True when every id up to the newest has been looked at. */
  caughtUp: boolean;
  /** Ids still queued for a later run. */
  left?: number;
  off?: string;
}

/**
 * Walks Shipturtle company ids for vendors of this marketplace, newest
 * first, for as long as the budget allows, and resumes where it stopped.
 * Never throws.
 */
export async function discoverNewCompanies(
  options: { budgetMs: number; fetchImpl?: typeof fetch; concurrency?: number },
): Promise<SweepResult> {
  const fetchImpl = options.fetchImpl ?? fetch;
  const concurrency = options.concurrency ?? 16;
  const deadline = Date.now() + options.budgetMs;
  const marketplace = marketplaceId();
  const { key } = shipturtleConfig();
  const result: SweepResult = { checked: 0, added: [], pending: 0, caughtUp: false };
  if (!key) return { ...result, off: 'no Shipturtle key' };
  if (!marketplace) return { ...result, off: 'no marketplace id' };

  try {
    const db = getFirestore();
    const stateRef = db.doc(SWEEP_STATE_DOC);
    const state = ((await stateRef.get()).data() ?? {}) as SweepState;
    const pending: Record<string, number> = { ...(state.companyPending ?? {}) };

    const consider = async (id: number, company: Record<string, unknown>) => {
      const verdict = companyVerdict(String(id), company, marketplace);
      if (verdict.kind === 'vendor') {
        delete pending[String(id)];
        if (await storeSweptVendor(verdict.entry)) result.added.push(verdict.entry.vendorName);
      } else if (verdict.kind === 'pending') {
        pending[String(id)] ??= Date.now();
      } else {
        delete pending[String(id)];
      }
    };

    // 1. The ones waiting for approval: few, and the likeliest to have changed.
    for (const [id, firstSeen] of Object.entries(pending)) {
      if (Date.now() + 5_000 > deadline) break;
      if (Date.now() - firstSeen > PENDING_KEEP_MS) {
        delete pending[id];
        continue;
      }
      const company = await fetchCompany(Number(id), fetchImpl);
      result.checked += 1;
      if (company === null) delete pending[id];
      else if (company) await consider(Number(id), company);
    }

    // 2. New ids since the last run go to the front of the queue. On the
    // first run "the last run" is the marketplace itself, since no vendor of
    // it can be older; that first range is long (every merchant's companies
    // share the counter, tens of thousands of ids on the real account) and
    // is spread over many runs, newest first.
    const ranges: SweepRange[] = Array.isArray(state.companyRanges)
      ? state.companyRanges.filter((r) => typeof r?.next === 'number' && typeof r?.bottom === 'number')
      : [];
    let highest = typeof state.companyHighest === 'number' ? state.companyHighest : Number(marketplace);
    // Whatever part of the way it got is kept: the next run leaps on from
    // there, so even a short first tap makes progress.
    const top = await newestCompanyId(highest, fetchImpl, deadline);
    if (top.newest > highest) {
      ranges.unshift({ next: top.newest, bottom: highest + 1 });
      highest = top.newest;
    }

    // 3. Down each range, newest range first, a batch at a time.
    let silent = false;
    while (ranges.length > 0 && !silent && Date.now() + 8_000 < deadline) {
      const range = ranges[0]!;
      if (range.next < range.bottom) {
        ranges.shift();
        continue;
      }
      const ids: number[] = [];
      for (let id = range.next; id >= range.bottom && ids.length < concurrency; id--) ids.push(id);
      const companies = await Promise.all(ids.map((id) => fetchCompany(id, fetchImpl)));
      for (let i = 0; i < ids.length; i++) {
        const company = companies[i];
        if (company === undefined) {
          // Silence: stop here, and look at this id again next time.
          silent = true;
          break;
        }
        result.checked += 1;
        if (company) await consider(ids[i]!, company);
        range.next = ids[i]! - 1;
      }
    }
    const remaining = ranges.filter((r) => r.next >= r.bottom);
    await stateRef.set(
      { companyHighest: highest, companyRanges: remaining, companyPending: pending },
      { merge: true },
    );
    result.caughtUp = top.complete && remaining.length === 0;
    result.left = remaining.reduce((n, r) => n + (r.next - r.bottom + 1), 0);
    result.pending = Object.keys(pending).length;
    if (result.added.length || result.checked > 50) {
      logger.info('Company sweep', { ...result, highest });
    }
    return result;
  } catch (error) {
    logger.error('Company sweep failed', { message: String((error as Error)?.message ?? error) });
    return result;
  }
}

/**
 * The newest company id above `from`, exactly as Shipturtle answered it.
 *
 * Ids are shared by every merchant on Shipturtle and are dense near "now"
 * (hundreds a day), but have long holes: on the real account nothing
 * answers between about 1098466 and 1105700 (measured 2026-11-09). So each
 * round looks a long way ahead, at windows 256, 512, ... 32768 ids past the
 * newest id seen, all at once, and moves to the furthest that answers; when
 * none does, the newest is within 256 of it, and a binary search over that
 * dense stretch finds it. When Shipturtle stops answering or the time runs
 * out, it says how far it got (`complete: false`), which is still a real
 * id, so the next run carries on from there.
 *
 * Returned exactly, never rounded up: an id above it that does not exist
 * yet must stay above the line, or the company that later takes it is
 * never looked at.
 */
async function newestCompanyId(
  from: number,
  fetchImpl: typeof fetch,
  deadline: number,
): Promise<{ newest: number; complete: boolean }> {
  let newest = from;
  const existsNear = async (id: number, width: number): Promise<boolean | undefined> => {
    const ids = Array.from({ length: width }, (_, i) => id + i);
    const found = await Promise.all(ids.map((n) => fetchCompany(n, fetchImpl)));
    found.forEach((c, i) => {
      if (c && ids[i]! > newest) newest = ids[i]!;
    });
    if (found.some((c) => c)) return true;
    if (found.some((c) => c === undefined)) return undefined;
    return false;
  };
  const partial = () => ({ newest, complete: false });

  // 1. Leap ahead, every distance at once, until none answers.
  const steps = [256, 512, 1024, 2048, 4096, 8192, 16_384, 32_768];
  for (;;) {
    if (Date.now() + 10_000 > deadline) return partial();
    const base = newest;
    const answers = await Promise.all(steps.map((step) => existsNear(base + step, 4)));
    if (answers.some((a) => a === undefined) && !answers.some((a) => a)) return partial();
    if (!answers.some((a) => a)) break;
  }

  // 2. The newest is within 256 of `newest` (that stretch is dense): halve the gap.
  let lo = newest;
  let hi = newest + 256;
  while (hi - lo > END_RUN) {
    if (Date.now() + 10_000 > deadline) return partial();
    const mid = Math.floor((lo + hi) / 2);
    const e = await existsNear(mid, END_RUN);
    if (e === undefined) return partial();
    if (e) lo = newest;
    else hi = mid;
  }
  if ((await existsNear(lo + 1, END_RUN)) === undefined) return partial();
  return { newest, complete: true };
}
