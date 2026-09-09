import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { getMessaging, type Message, type Messaging } from 'firebase-admin/messaging';
import { logger } from 'firebase-functions';
import { HttpsError } from 'firebase-functions/v2/https';

/**
 * Push, in TypeScript, for both phones.
 *
 * A phone registers its FCM token under `users/{uid}/devices/{token}` (the
 * app writes it, rules let only the owner). Everything that sends goes
 * through here, reads those tokens, and forgets the ones FCM says are dead.
 * The bell (`notifications.ts`) calls [sendPushToUid] after writing its
 * document, so a push is always the shadow of something the app also shows.
 *
 * Nothing here decides *whether* someone should hear about something; that
 * is [shouldPush] against their preferences, and the triggers that build
 * the recipient lists.
 */

export type PushType =
  | 'mention'
  | 'comment'
  | 'review'
  | 'forumThread'
  | 'forumReply'
  | 'newProduct'
  | 'newPost'
  | 'announcement'
  | 'test';

/** `users/{uid}/settings/notifications`. Every switch defaults to on. */
export interface NotificationPrefs {
  mentions?: boolean;
  comments?: boolean;
  forums?: boolean;
  reviews?: boolean;
  newProducts?: boolean;
  /** A post from someone you follow. */
  newPosts?: boolean;
  announcements?: boolean;
  mutedForums?: string[];
}

export interface PushEvent {
  type: PushType;
  forumId?: string;
}

/** Whether these preferences let this push through. Pure. */
export function shouldPush(prefs: NotificationPrefs | undefined, event: PushEvent): boolean {
  const on = (value: boolean | undefined) => value !== false;
  if (event.forumId && (prefs?.mutedForums ?? []).includes(event.forumId)) return false;
  switch (event.type) {
    case 'mention':
      return on(prefs?.mentions);
    case 'comment':
      return on(prefs?.comments);
    case 'review':
      return on(prefs?.reviews);
    case 'forumThread':
    case 'forumReply':
      return on(prefs?.forums);
    case 'newProduct':
      return on(prefs?.newProducts);
    case 'newPost':
      return on(prefs?.newPosts);
    case 'announcement':
      return on(prefs?.announcements);
    case 'test':
      return true;
  }
}

/** A muted forum silences the bell as well as the push. Pure. */
export function shouldNotifyAtAll(prefs: NotificationPrefs | undefined, event: PushEvent): boolean {
  return !(event.forumId && (prefs?.mutedForums ?? []).includes(event.forumId));
}

/** FCM's ways of saying "this token is dead; stop sending to it". Pure. */
export function shouldPrune(code: string | undefined): boolean {
  return (
    code === 'messaging/registration-token-not-registered' ||
    code === 'messaging/invalid-registration-token' ||
    code === 'messaging/invalid-argument'
  );
}

/** The one line on the lock screen. Pure. */
export function titleFor(type: PushType, fromName: string, fallbackTitle?: string): string {
  const who = fromName || 'Someone';
  switch (type) {
    case 'mention':
      return `${who} mentioned you`;
    case 'comment':
      return `${who} commented on your post`;
    case 'review':
      return `${who} reviewed your product`;
    case 'forumThread':
      return `${who} started a thread`;
    case 'forumReply':
      return `${who} replied`;
    case 'newProduct':
      return `New from ${who}`;
    case 'newPost':
      return `${who} posted`;
    case 'announcement':
      return fallbackTitle || 'Little Blue Market';
    case 'test':
      return 'Little Blue Market';
  }
}

export interface PushPayload {
  title: string;
  body: string;
  /** Strings only: FCM data is a string map. `route` is what the app opens. */
  data?: Record<string, string>;
}

export interface PushOutcome {
  devices: number;
  sent: number;
  pruned: number;
}

/** Sends to every phone this person has registered; forgets dead tokens. */
export async function sendPushToUid(
  uid: string,
  payload: PushPayload,
  messaging: Messaging = getMessaging(),
): Promise<PushOutcome> {
  const db = getFirestore();
  const devices = db.collection('users').doc(uid).collection('devices');
  const snapshot = await devices.get();
  const tokens = snapshot.docs.map((d) => d.id).filter(Boolean);
  if (!tokens.length) return { devices: 0, sent: 0, pruned: 0 };

  const response = await messaging.sendEachForMulticast({
    tokens,
    notification: { title: payload.title, body: payload.body },
    data: payload.data ?? {},
    android: {
      priority: 'high',
      notification: { channelId: 'lbm_default', icon: 'ic_stat_lbm', color: '#70A0D0' },
    },
    apns: { payload: { aps: { sound: 'default' } } },
  });

  let pruned = 0;
  const batch = db.batch();
  response.responses.forEach((r, i) => {
    if (r.success) return;
    const code = r.error?.code;
    if (shouldPrune(code)) {
      batch.delete(devices.doc(tokens[i]!));
      pruned++;
    } else {
      logger.warn('Push to one device failed', { uid, code, message: r.error?.message });
    }
  });
  if (pruned) await batch.commit();
  return { devices: tokens.length, sent: response.successCount, pruned };
}

// -------------------------------------------------------------- recipients
//
// Who hears about what, as pure functions the triggers feed. Authors never
// hear about their own act; nobody is listed twice.

/** A new thread: every member of the forum except the person who started it. Capped: a runaway forum is not a reason to send 10,000 pushes from one trigger. */
export function forumThreadRecipients(memberIds: Iterable<string>, authorId: string, cap = 500): string[] {
  const out: string[] = [];
  for (const uid of new Set(memberIds)) {
    if (!uid || uid === authorId) continue;
    out.push(uid);
    if (out.length >= cap) break;
  }
  return out;
}

/** A reply: the thread's author and everyone who commented before, except the replier. Not the whole forum. */
export function forumReplyRecipients(
  threadAuthorId: string,
  earlierCommenterIds: Iterable<string>,
  replierId: string,
): string[] {
  const out = new Set<string>();
  if (threadAuthorId) out.add(threadAuthorId);
  for (const uid of earlierCommenterIds) if (uid) out.add(uid);
  out.delete(replierId);
  out.delete('');
  return [...out];
}

/**
 * A shoutout names one seller (`aboutSellerId`) besides any @-mentions. The
 * seller hears about it once: not when they wrote it, not when they were
 * also @-mentioned (the mention path already told them), and not on an edit
 * that kept the same seller.
 */
export function shoutoutSellerToNotify(
  after: { authorId?: unknown; aboutSellerId?: unknown; mentionedUids?: unknown } | undefined,
  before: { aboutSellerId?: unknown } | undefined,
): string | null {
  if (!after) return null;
  const seller = String(after.aboutSellerId ?? '');
  if (!seller) return null;
  if (seller === String(after.authorId ?? '')) return null;
  if (String(before?.aboutSellerId ?? '') === seller) return null;
  const mentioned = Array.isArray(after.mentionedUids) ? after.mentionedUids.map(String) : [];
  if (mentioned.includes(seller)) return null;
  return seller;
}

// ----------------------------------------------------------- announcements

export const AUDIENCES = ['all', 'sellers', 'buyers', 'directory'] as const;
export type Audience = (typeof AUDIENCES)[number];
export const ANNOUNCEMENT_TITLE_MAX = 60;
export const ANNOUNCEMENT_BODY_MAX = 180;

/**
 * Who an announcement reaches, in FCM's terms. Phones subscribe to `all`
 * on sign-in, `sellers` when the token carries the seller claim, and
 * `directory` when the account is joined to littlebluecart.com; "buyers"
 * is everyone who is not a seller, which FCM expresses as a condition.
 * Pure.
 */
export function topicTarget(audience: Audience): { topic: string } | { condition: string } {
  switch (audience) {
    case 'all':
      return { topic: 'all' };
    case 'sellers':
      return { topic: 'sellers' };
    case 'directory':
      return { topic: 'directory' };
    case 'buyers':
      return { condition: "'all' in topics && !('sellers' in topics)" };
  }
}

export function isAudience(value: unknown): value is Audience {
  return typeof value === 'string' && (AUDIENCES as readonly string[]).includes(value);
}

export interface AnnouncementInput {
  title: string;
  body: string;
  audience: Audience;
  /** Where a tap goes; the bell when empty. */
  route?: string;
  byUid: string;
}

/**
 * Grace's announcement: written to `announcements/{id}` first (the bell
 * shows it from there, filtered by audience on the phone), then sent once
 * to the topic. One send, however many phones: no fan-out, no per-user
 * bell documents.
 */
export async function sendAnnouncement(
  input: AnnouncementInput,
  messaging: Messaging = getMessaging(),
): Promise<{ id: string; messageId: string }> {
  const title = input.title.trim();
  const body = input.body.trim();
  if (!title) throw new HttpsError('invalid-argument', 'Give the announcement a title.');
  if (title.length > ANNOUNCEMENT_TITLE_MAX) {
    throw new HttpsError('invalid-argument', `Keep the title under ${ANNOUNCEMENT_TITLE_MAX} characters.`);
  }
  if (!body) throw new HttpsError('invalid-argument', 'Write something for the announcement to say.');
  if (body.length > ANNOUNCEMENT_BODY_MAX) {
    throw new HttpsError('invalid-argument', `Keep the message under ${ANNOUNCEMENT_BODY_MAX} characters.`);
  }
  if (!isAudience(input.audience)) throw new HttpsError('invalid-argument', 'Pick who this goes to.');

  const route = (input.route ?? '').trim() || '/you/notifications';
  const db = getFirestore();
  const ref = db.collection('announcements').doc();
  await ref.set({
    title,
    body,
    audience: input.audience,
    route,
    createdBy: input.byUid,
    createdAt: FieldValue.serverTimestamp(),
  });

  const message: Message = {
    ...topicTarget(input.audience),
    notification: { title, body },
    data: { route, type: 'announcement', announcementId: ref.id },
    android: {
      priority: 'high',
      notification: { channelId: 'lbm_default', icon: 'ic_stat_lbm', color: '#70A0D0' },
    },
    apns: { payload: { aps: { sound: 'default' } } },
  } as Message;
  const messageId = await messaging.send(message);
  await ref.set({ messageId, sentAt: FieldValue.serverTimestamp() }, { merge: true });
  logger.info('Announcement sent', { id: ref.id, audience: input.audience, messageId });
  return { id: ref.id, messageId };
}

/** The same payload to many people, one after another; a failure for one never stops the rest. */
export async function sendPushToUids(uids: Iterable<string>, payload: PushPayload): Promise<number> {
  let sent = 0;
  for (const uid of new Set(uids)) {
    try {
      sent += (await sendPushToUid(uid, payload)).sent;
    } catch (error) {
      logger.warn('Push to one person failed', { uid, message: (error as Error).message });
    }
  }
  return sent;
}

/**
 * Who follows this person (the reverse of users/{me}/following, kept by
 * onFollowWritten), minus the person themself. Capped like the forum list:
 * a wildly popular seller still gets a bounded fan-out per post.
 */
export async function postSubscribers(authorUid: string, cap = 500): Promise<string[]> {
  if (!authorUid) return [];
  const snapshot = await getFirestore()
    .collection('users')
    .doc(authorUid)
    .collection('subscribers')
    .limit(cap)
    .get();
  return snapshot.docs.map((d) => d.id).filter((id) => id && id !== authorUid);
}
