import { FieldValue, getFirestore, Timestamp } from 'firebase-admin/firestore';
import { HttpsError } from 'firebase-functions/v2/https';

/**
 * The app's analytics: every screen opened and every action taken, kept in
 * `analyticsEvents` and downloaded as JSON from the admin website (Grace,
 * 2026-11-04: "add analytics to the app that record all user events and are
 * downloadable as a JSON from the admin portal. Add the user's id so we can
 * track them across events").
 *
 * The user id is the caller's sign-in, set here and never read from the
 * phone, so nobody can record events in somebody else's name. A guest has
 * none; their device id ties their events together, and to their account
 * once they sign in on that device.
 */
export const EVENTS_PER_CALL = 50;
export const PROPS_MAX = 20;
const TEXT_MAX = 200;
const NAME = /^[a-z][a-z0-9_]{0,47}$/;
const KEY = /^[A-Za-z][A-Za-z0-9_]{0,39}$/;

export interface CleanEvent {
  name: string;
  props: Record<string, string | number | boolean>;
  at: Timestamp;
  sessionId: string;
  deviceId: string;
  platform: string;
  appVersion: string;
  path: string;
}

const short = (value: unknown, max = TEXT_MAX): string => String(value ?? '').slice(0, max);

/**
 * What a phone sent, made safe to keep. Anything malformed is dropped rather
 * than refused: one bad event must not cost the rest of the batch. Pure.
 */
export function cleanEvents(raw: unknown, nowMs: number): CleanEvent[] {
  if (!Array.isArray(raw)) return [];
  const out: CleanEvent[] = [];
  for (const item of raw.slice(0, EVENTS_PER_CALL)) {
    if (!item || typeof item !== 'object') continue;
    const e = item as Record<string, unknown>;
    const name = String(e.name ?? '');
    if (!NAME.test(name)) continue;
    const props: Record<string, string | number | boolean> = {};
    if (e.props && typeof e.props === 'object' && !Array.isArray(e.props)) {
      for (const [k, v] of Object.entries(e.props as Record<string, unknown>).slice(0, PROPS_MAX)) {
        if (!KEY.test(k)) continue;
        if (typeof v === 'number' && Number.isFinite(v)) props[k] = v;
        else if (typeof v === 'boolean') props[k] = v;
        else if (typeof v === 'string') props[k] = v.slice(0, TEXT_MAX);
      }
    }
    // The phone's clock, unless it is plainly wrong: kept within a day of
    // arrival, so a phone set to 1970 does not sort to the start of time.
    const parsed = Date.parse(String(e.at ?? ''));
    const atMs = Number.isFinite(parsed) && Math.abs(parsed - nowMs) < 86_400_000 ? parsed : nowMs;
    out.push({
      name,
      props,
      at: Timestamp.fromMillis(atMs),
      sessionId: short(e.sessionId, 64),
      deviceId: short(e.deviceId, 64),
      platform: short(e.platform, 20),
      appVersion: short(e.appVersion, 30),
      path: short(e.path),
    });
  }
  return out;
}

export async function saveEvents(raw: unknown, uid: string | null): Promise<{ saved: number }> {
  const events = cleanEvents(raw, Date.now());
  if (events.length === 0) return { saved: 0 };
  const db = getFirestore();
  const batch = db.batch();
  for (const event of events) {
    batch.set(db.collection('analyticsEvents').doc(), {
      ...event,
      uid,
      receivedAt: FieldValue.serverTimestamp(),
    });
  }
  await batch.commit();
  return { saved: events.length };
}

/** One page of an export. Big enough to be quick, small enough for 70 s. */
export const EXPORT_PAGE = 2_000;

export interface ExportInput {
  from?: unknown;
  to?: unknown;
  uid?: unknown;
  after?: unknown;
}

/** A date from the admin form ("2026-11-04"), as the start of that day UTC. Pure. */
export function dayStart(raw: unknown, label: string): Timestamp {
  const text = String(raw ?? '').trim();
  const ms = Date.parse(/^\d{4}-\d{2}-\d{2}$/.test(text) ? `${text}T00:00:00Z` : text);
  if (!Number.isFinite(ms)) throw new HttpsError('invalid-argument', `${label} is not a date. Got ${text || '(nothing)'}`);
  return Timestamp.fromMillis(ms);
}

/**
 * One page of events between two days (the second one included), oldest
 * first, optionally for one user. [after] is the last id of the previous
 * page; the admin website asks again until [next] comes back empty.
 */
export async function exportEvents(input: ExportInput): Promise<{
  events: Record<string, unknown>[];
  next: string;
}> {
  const from = dayStart(input.from, 'The start date');
  const to = Timestamp.fromMillis(dayStart(input.to, 'The end date').toMillis() + 86_400_000);
  if (to.toMillis() <= from.toMillis()) {
    throw new HttpsError('invalid-argument', 'The end date has to be on or after the start date.');
  }
  const db = getFirestore();
  let q = db
    .collection('analyticsEvents')
    .where('receivedAt', '>=', from)
    .where('receivedAt', '<', to);
  const uid = String(input.uid ?? '').trim();
  if (uid) q = q.where('uid', '==', uid);
  q = q.orderBy('receivedAt').orderBy('__name__').limit(EXPORT_PAGE);
  const after = String(input.after ?? '').trim();
  if (after) {
    const last = await db.collection('analyticsEvents').doc(after).get();
    if (last.exists) q = q.startAfter(last);
  }
  const snap = await q.get();
  const iso = (t: unknown) => (t instanceof Timestamp ? t.toDate().toISOString() : null);
  const events = snap.docs.map((d) => {
    const e = d.data();
    return {
      id: d.id,
      uid: e.uid ?? null,
      name: e.name,
      props: e.props ?? {},
      at: iso(e.at),
      receivedAt: iso(e.receivedAt),
      sessionId: e.sessionId,
      deviceId: e.deviceId,
      platform: e.platform,
      appVersion: e.appVersion,
      path: e.path,
    };
  });
  const lastDoc = snap.docs.at(-1);
  return { events, next: snap.size === EXPORT_PAGE && lastDoc ? lastDoc.id : '' };
}
