import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions';

import {
  type NotificationPrefs,
  type PushType,
  sendPushToUid,
  shouldNotifyAtAll,
  shouldPush,
  titleFor,
} from './push.ts';

/**
 * The bell, and the push that shadows it.
 *
 * Written only here (rules: read your own, mark your own read, nobody
 * creates one from a phone), so a notification is always about something
 * that actually happened. Since Stage 12 the same call also pushes to the
 * person's phones, after their preferences have had their say; a push
 * failure is logged and never fails the trigger that caused it.
 */

export function mentionsToNotify(
  after: { authorId?: unknown; mentionedUids?: unknown } | undefined,
  before: { mentionedUids?: unknown } | undefined,
): string[] {
  if (!after) return [];
  const author = String(after.authorId ?? '');
  const now = Array.isArray(after.mentionedUids) ? after.mentionedUids.map(String) : [];
  const was = new Set(Array.isArray(before?.mentionedUids) ? before!.mentionedUids.map(String) : []);
  return [...new Set(now)].filter((uid) => uid && uid !== author && !was.has(uid));
}

/** Everything the bell carries. Not the test push, and never a promo. */
export type NotifyType = Exclude<PushType, 'test' | 'promo'>;

export interface NotifyInput {
  type: NotifyType;
  fromUid: string;
  /** The first line of what happened, ≤140 chars. */
  text: string;
  postId?: string;
  /** Where a tap goes; defaults to the post. */
  route?: string;
  /** For the per-forum mute. */
  forumId?: string;
  threadId?: string;
  productId?: string;
  /** Announcements carry their own title; everything else is named after the person. */
  title?: string;
}

/** Someone's name for a notification line. Empty rather than throwing. */
export async function displayName(uid: string): Promise<string> {
  if (!uid) return '';
  try {
    const doc = await getFirestore().collection('users').doc(uid).get();
    return String(doc.data()?.name ?? doc.data()?.handle ?? '');
  } catch {
    return '';
  }
}

export async function readPrefs(uid: string): Promise<NotificationPrefs | undefined> {
  try {
    const doc = await getFirestore().doc(`users/${uid}/settings/notifications`).get();
    return doc.data() as NotificationPrefs | undefined;
  } catch {
    return undefined;
  }
}

export async function notify(uid: string, n: NotifyInput): Promise<void> {
  if (!uid) return;
  const prefs = await readPrefs(uid);
  if (!shouldNotifyAtAll(prefs, n)) return;

  const route = n.route ?? (n.postId ? `/market/post/${n.postId}` : '/you/notifications');
  // Explicit fields: Firestore refuses `undefined` values.
  const doc: Record<string, unknown> = {
    type: n.type,
    fromUid: n.fromUid,
    text: n.text,
    postId: n.postId ?? '',
    route,
    read: false,
    createdAt: FieldValue.serverTimestamp(),
  };
  if (n.forumId) doc.forumId = n.forumId;
  if (n.threadId) doc.threadId = n.threadId;
  if (n.productId) doc.productId = n.productId;
  if (n.title) doc.title = n.title;
  const user = getFirestore().collection('users').doc(uid);
  await user.collection('notifications').add(doc);

  // A forum reply never pushes by itself: it joins the digest, which rolls
  // every reply since the last one into a single push (C2, 2026-09-28).
  if (n.type === 'forumReply') {
    if (!shouldPush(prefs, n)) return;
    const threadId = n.threadId || /\/thread\/([^/?]+)/.exec(route)?.[1] || '';
    if (!threadId) return;
    const entry: Record<string, unknown> = {
      count: FieldValue.increment(1),
      lastAt: FieldValue.serverTimestamp(),
    };
    if (n.forumId) entry.forumId = n.forumId;
    await user.collection('pendingDigest').doc(threadId).set(entry, { merge: true });
    return;
  }

  const now = new Date();
  if (!shouldPush(prefs, n, { now, lastPushAt: toDate(prefs?.lastPushAt) })) return;
  try {
    const fromName = n.type === 'announcement' ? '' : await displayName(n.fromUid);
    const outcome = await sendPushToUid(uid, {
      title: titleFor(n.type, fromName, n.title),
      body: n.text,
      data: { route, type: n.type, postId: n.postId ?? '' },
    });
    if (outcome.sent > 0) await markPushed(uid, now);
  } catch (error) {
    logger.warn('Push failed after the bell was written', { uid, type: n.type, message: (error as Error).message });
  }
}

/** A Firestore timestamp, a Date, or nothing, as a Date or nothing. */
function toDate(value: { toDate(): Date } | Date | undefined): Date | undefined {
  if (!value) return undefined;
  return value instanceof Date ? value : value.toDate();
}

/** The rate limit's memory: when this person was last pushed to. */
async function markPushed(uid: string, at: Date): Promise<void> {
  await getFirestore()
    .doc(`users/${uid}/settings/notifications`)
    .set({ lastPushAt: at }, { merge: true });
}

// ------------------------------------------------------------ forum digest

/** One thread's replies waiting under `users/{uid}/pendingDigest/{threadId}`. */
export interface DigestEntry {
  threadId: string;
  count: number;
  forumId?: string;
}

/** "3 new replies in 2 threads". Pure. */
export function digestText(entries: DigestEntry[]): { title: string; body: string } {
  const replies = entries.reduce((sum, e) => sum + Math.max(0, e.count), 0);
  const threads = entries.length;
  return {
    title: 'New in your forums',
    body:
      `${replies} new ${replies === 1 ? 'reply' : 'replies'} in ` +
      `${threads} ${threads === 1 ? 'thread' : 'threads'}`,
  };
}

/**
 * What to do with one person's waiting replies. Pure.
 *
 * `drop`: nothing left worth sending (forums switched off, or every thread
 * in a muted forum), so the entries go. `hold`: quiet hours or the rate
 * limit, so they wait for a later run. `send`: one push for all of them.
 */
export function planDigest(
  prefs: NotificationPrefs | undefined,
  entries: DigestEntry[],
  now: Date,
  lastPushAt?: Date,
): { plan: 'send' | 'hold' | 'drop'; entries: DigestEntry[] } {
  const live = entries.filter((e) => e.count > 0 && shouldPush(prefs, { type: 'forumReply', forumId: e.forumId }));
  if (live.length === 0) return { plan: 'drop', entries: [] };
  const go = shouldPush(prefs, { type: 'forumReply' }, { now, lastPushAt, digest: true });
  return { plan: go ? 'send' : 'hold', entries: live };
}

/** Everything [sendDigest] touches, so a test can stand in for Firestore and FCM. */
export interface DigestDeps {
  prefs(uid: string): Promise<NotificationPrefs | undefined>;
  push(uid: string, payload: { title: string; body: string; data: Record<string, string> }): Promise<{ sent: number }>;
  clear(uid: string, threadIds: string[]): Promise<void>;
  markPushed(uid: string, at: Date): Promise<void>;
}

/** One person's digest: plans it, sends it, clears what it covered. */
export async function sendDigest(
  uid: string,
  entries: DigestEntry[],
  deps: DigestDeps,
  now: Date,
): Promise<'sent' | 'held' | 'dropped'> {
  const prefs = await deps.prefs(uid);
  const { plan, entries: live } = planDigest(prefs, entries, now, toDate(prefs?.lastPushAt));
  if (plan === 'hold') return 'held';
  if (plan === 'drop') {
    await deps.clear(uid, entries.map((e) => e.threadId));
    return 'dropped';
  }
  const { title, body } = digestText(live);
  const outcome = await deps.push(uid, {
    title,
    body,
    data: { route: '/community', type: 'forumReply', postId: '' },
  });
  await deps.clear(uid, entries.map((e) => e.threadId));
  if (outcome.sent > 0) await deps.markPushed(uid, now);
  return 'sent';
}

const firestoreDigestDeps: DigestDeps = {
  prefs: readPrefs,
  push: (uid, payload) => sendPushToUid(uid, payload),
  clear: async (uid, threadIds) => {
    const db = getFirestore();
    const batch = db.batch();
    for (const id of threadIds) batch.delete(db.doc(`users/${uid}/pendingDigest/${id}`));
    await batch.commit();
  },
  markPushed,
};

/**
 * Every person with replies waiting gets at most one push per run. Run
 * every 30 minutes, so the first reply in a quiet spell waits half an hour
 * at most and everything after it in that half hour rides along.
 */
export async function runForumDigest(
  now = new Date(),
  deps: DigestDeps = firestoreDigestDeps,
): Promise<{ people: number; sent: number; held: number; dropped: number }> {
  const snap = await getFirestore().collectionGroup('pendingDigest').get();
  const byUser = new Map<string, DigestEntry[]>();
  for (const doc of snap.docs) {
    const uid = doc.ref.parent.parent?.id;
    if (!uid) continue;
    const data = doc.data();
    const entry: DigestEntry = { threadId: doc.id, count: Number(data.count ?? 0) };
    if (typeof data.forumId === 'string') entry.forumId = data.forumId;
    byUser.set(uid, [...(byUser.get(uid) ?? []), entry]);
  }
  const tally = { people: byUser.size, sent: 0, held: 0, dropped: 0 };
  for (const [uid, entries] of byUser) {
    try {
      tally[await sendDigest(uid, entries, deps, now)]++;
    } catch (error) {
      logger.warn('Forum digest failed for one person', { uid, message: (error as Error).message });
    }
  }
  return tally;
}
