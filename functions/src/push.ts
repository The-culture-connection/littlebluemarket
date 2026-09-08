import { getFirestore } from 'firebase-admin/firestore';
import { getMessaging, type Messaging } from 'firebase-admin/messaging';
import { logger } from 'firebase-functions';

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
  | 'announcement'
  | 'test';

/** `users/{uid}/settings/notifications`. Every switch defaults to on. */
export interface NotificationPrefs {
  mentions?: boolean;
  comments?: boolean;
  forums?: boolean;
  reviews?: boolean;
  newProducts?: boolean;
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
