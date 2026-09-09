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

export type NotifyType = Exclude<PushType, 'test'>;

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

async function displayName(uid: string): Promise<string> {
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
  await getFirestore().collection('users').doc(uid).collection('notifications').add(doc);

  if (!shouldPush(prefs, n)) return;
  try {
    const fromName = n.type === 'announcement' ? '' : await displayName(n.fromUid);
    await sendPushToUid(uid, {
      title: titleFor(n.type, fromName, n.title),
      body: n.text,
      data: { route, type: n.type, postId: n.postId ?? '' },
    });
  } catch (error) {
    logger.warn('Push failed after the bell was written', { uid, type: n.type, message: (error as Error).message });
  }
}

/** How many sends go out at once in a fan-out. */
export const FAN_OUT_CHUNK = 25;

/**
 * One notification to many people: a new post to its author's followers, a
 * new thread to a forum, a reply to everyone in the thread.
 *
 * Chunks in parallel, not one await per person: five hundred sequential
 * sends can outlive the trigger's timeout and silently drop the tail. One
 * person's failure (a dead push token, a missing preferences document) is
 * logged and does not stop the rest. Returns how it went, for the logs.
 */
export async function notifyMany(
  uids: readonly string[],
  n: NotifyInput,
  send: (uid: string, n: NotifyInput) => Promise<void> = notify,
): Promise<{ sent: number; failed: number }> {
  let sent = 0;
  let failed = 0;
  for (let i = 0; i < uids.length; i += FAN_OUT_CHUNK) {
    const results = await Promise.allSettled(
      uids.slice(i, i + FAN_OUT_CHUNK).map((uid) => send(uid, n)),
    );
    for (const r of results) {
      if (r.status === 'fulfilled') sent++;
      else {
        failed++;
        logger.warn('A notification in a fan-out failed', { type: n.type, error: String(r.reason) });
      }
    }
  }
  return { sent, failed };
}
