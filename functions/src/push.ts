import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { getMessaging, type Message, type Messaging } from 'firebase-admin/messaging';
import { logger } from 'firebase-functions';
import { HttpsError } from 'firebase-functions/v2/https';
import { resolveNamed } from './mentions.ts';

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
  | 'tagPost'
  /** A direct message. No bell row: the inbox is where a DM lives. */
  | 'newMessage'
  | 'announcement'
  /**
   * A seller's advert. Never pushed: it is the feed's banner, labelled, and
   * nothing else (Grace, 2026-09-28). Here so that rule has somewhere to be
   * written down and tested, not because anything sends one.
   */
  | 'promo'
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
  /** A post under a tag you asked to be told about ("Notify me" on a tag). */
  tagPosts?: boolean;
  /** Direct messages. */
  messages?: boolean;
  announcements?: boolean;
  mutedForums?: string[];
  /** Quiet hours, "HH:mm" local. Default 22:00 to 08:00. */
  quietStart?: string;
  quietEnd?: string;
  /** The person's time zone. Default America/Detroit, where the market is. */
  tz?: string;
  /** When this person was last pushed to, written by `notify()`. */
  lastPushAt?: { toDate(): Date } | Date;
}

export interface PushEvent {
  type: PushType;
  forumId?: string;
}

/**
 * When a push would go, for the timing rules. Without it [shouldPush] is
 * the preferences alone, which is what the switches on the settings screen
 * mean.
 */
export interface PushContext {
  now: Date;
  /** The last push this person got, from any path. */
  lastPushAt?: Date;
  /** The forum digest, which is the only way a forum reply may push. */
  digest?: boolean;
}

export const DEFAULT_QUIET_START = '22:00';
export const DEFAULT_QUIET_END = '08:00';
export const DEFAULT_TZ = 'America/Detroit';

/** Outside DMs and mentions, no more than one push in this long. */
export const PUSH_GAP_MS = 20 * 60 * 1000;

/** "22:00" → 1320. Anything unreadable is null, and the default is used. */
function minutesOf(hhmm: string | undefined): number | null {
  const m = /^(\d{1,2}):(\d{2})$/.exec(hhmm ?? '');
  if (!m) return null;
  const h = Number(m[1]);
  const min = Number(m[2]);
  if (h > 23 || min > 59) return null;
  return h * 60 + min;
}

/** Minutes after midnight at [now] in [tz]. Falls back to the default zone. */
function localMinutes(now: Date, tz: string | undefined): number {
  const read = (zone: string) => {
    const parts = new Intl.DateTimeFormat('en-US', {
      timeZone: zone,
      hour: '2-digit',
      minute: '2-digit',
      hourCycle: 'h23',
    }).formatToParts(now);
    const h = Number(parts.find((p) => p.type === 'hour')?.value ?? 0);
    const m = Number(parts.find((p) => p.type === 'minute')?.value ?? 0);
    return h * 60 + m;
  };
  try {
    return read(tz || DEFAULT_TZ);
  } catch {
    return read(DEFAULT_TZ);
  }
}

/** Whether [now] is inside this person's quiet hours. Pure. */
export function isQuietHours(prefs: NotificationPrefs | undefined, now: Date): boolean {
  const start = minutesOf(prefs?.quietStart) ?? minutesOf(DEFAULT_QUIET_START)!;
  const end = minutesOf(prefs?.quietEnd) ?? minutesOf(DEFAULT_QUIET_END)!;
  if (start === end) return false;
  const at = localMinutes(now, prefs?.tz);
  // The default window crosses midnight, which is the case to get right.
  return start < end ? at >= start && at < end : at >= start || at < end;
}

/**
 * A person talking to you: the one kind of push that is let through at
 * night and is not rate limited: a mention, and a direct message.
 */
function isPersonToYou(type: PushType): boolean {
  return type === 'mention' || type === 'newMessage';
}

/**
 * Whether this push goes. Pure.
 *
 * The preferences first, exactly as before. Then, when [ctx] says when:
 * promos never; a forum reply only as the digest; announcements and the
 * test push as they always were (Grace's launch schedule depends on the
 * announcement path, so no timing rule touches it); a mention always; and
 * everything else neither in quiet hours nor within twenty minutes of the
 * last push. What is held back is still on the bell.
 */
export function shouldPush(
  prefs: NotificationPrefs | undefined,
  event: PushEvent,
  ctx?: PushContext,
): boolean {
  if (event.type === 'promo') return false;
  if (!allowedByPrefs(prefs, event)) return false;
  if (!ctx) return true;

  if (event.type === 'announcement' || event.type === 'test') return true;
  if (event.type === 'forumReply' && !ctx.digest) return false;
  if (isPersonToYou(event.type)) return true;
  if (isQuietHours(prefs, ctx.now)) return false;
  if (ctx.lastPushAt && ctx.now.getTime() - ctx.lastPushAt.getTime() < PUSH_GAP_MS) {
    return false;
  }
  return true;
}

/** The switches on the settings screen, and the per-forum mute. Pure. */
function allowedByPrefs(prefs: NotificationPrefs | undefined, event: PushEvent): boolean {
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
    case 'tagPost':
      return on(prefs?.tagPosts);
    case 'newMessage':
      return on(prefs?.messages);
    case 'announcement':
      return on(prefs?.announcements);
    case 'promo':
      return false;
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
    // The tag is the news here, not who wrote it: you asked to hear about
    // #Handmade, not about this person. The caller passes "New under
    // #handmade" as the fallback title, and the body names the person.
    case 'tagPost':
      return fallbackTitle || `${who} posted under a tag you follow`;
    // A message is from a person, and their name is the whole title, as in
    // every phone's own messaging app.
    case 'newMessage':
      return who;
    case 'announcement':
    case 'promo':
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
/**
 * What an announcement looks like on the wire. One place, so the
 * Diagnostics delivery test sends exactly what a real announcement sends,
 * only to a private topic. Pure.
 */
export function announcementMessage(
  target: { topic: string } | { condition: string },
  a: { title: string; body: string; route: string; announcementId: string },
): Message {
  return {
    ...target,
    notification: { title: a.title, body: a.body },
    data: { route: a.route, type: 'announcement', announcementId: a.announcementId },
    android: {
      priority: 'high',
      notification: { channelId: 'lbm_default', icon: 'ic_stat_lbm', color: '#70A0D0' },
    },
    apns: { payload: { aps: { sound: 'default' } } },
  } as Message;
}

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
  // The @handles and #hashtags the copy names. Resolved before the push
  // goes out, because a push cannot be taken back: a mistyped handle has to
  // be a message in the form, not a dead link on every phone.
  const named = await resolveNamed(title, body);
  const db = getFirestore();
  const ref = db.collection('announcements').doc();
  await ref.set({
    title,
    body,
    audience: input.audience,
    route,
    ...named,
    createdBy: input.byUid,
    createdAt: FieldValue.serverTimestamp(),
  });

  const message = announcementMessage(topicTarget(input.audience), { title, body, route, announcementId: ref.id });
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

/**
 * Whether a `followedTags` document should have a subscriber row. Pure.
 *
 * Following a tag and asking to be told about it are two things: the tag
 * page offers Follow and Notify me separately, and plenty of people want a
 * collection in their feed without a buzz every time somebody posts to it.
 * Only "notify" gets a row, so the quiet half of the pair costs nothing at
 * post time.
 */
export function wantsTagTelling(
  after: Record<string, unknown> | undefined,
  exists: boolean,
): boolean {
  return exists && after?.notify === true;
}

/**
 * The tags of a new post that are worth fanning out, in order. Pure.
 *
 * Capped, and the cap is on the post's tags rather than on the people who
 * follow them: a post carrying thirty hashtags is reach-seeking, and the
 * people who follow those tags are the ones who would pay for it in buzzes.
 * Blanks and repeats drop out, so `#Handmade #handmade` is one tag.
 */
export function tagsToFanOut(keys: Iterable<string>, cap = 5): string[] {
  const seen = new Set<string>();
  for (const key of keys) {
    if (!key) continue;
    seen.add(key);
    if (seen.size >= cap) break;
  }
  return [...seen];
}

/**
 * Who asked to be told about this tag (the reverse of
 * users/{me}/followedTags where `notify` is true, kept by
 * onTagFollowWritten). Capped the same way: a tag everybody follows still
 * gets a bounded fan-out per post.
 *
 * [exclude] is everyone already being notified about this post for another
 * reason — the author, the people it mentions, the seller of a shoutout,
 * the author's own followers — so somebody who follows both the person and
 * the tag hears about it once rather than twice.
 */
export async function tagSubscribers(
  key: string,
  exclude: ReadonlySet<string> = new Set(),
  cap = 500,
): Promise<string[]> {
  if (!key) return [];
  const snapshot = await getFirestore()
    .collection('hashtags')
    .doc(key)
    .collection('subscribers')
    .limit(cap)
    .get();
  return snapshot.docs.map((d) => d.id).filter((id) => id && !exclude.has(id));
}
