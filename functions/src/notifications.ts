import { FieldValue, getFirestore } from 'firebase-admin/firestore';

/**
 * The bell.
 *
 * Two things reach it for now: someone @-mentioned you in a post, and
 * someone commented on your post. Written only here (rules: read your own,
 * mark your own read, nobody creates one from a phone), so a notification
 * is always about something that actually happened.
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

export async function notify(
  uid: string,
  notification: { type: 'mention' | 'comment'; postId: string; fromUid: string; text: string },
): Promise<void> {
  await getFirestore()
    .collection('users')
    .doc(uid)
    .collection('notifications')
    .add({ ...notification, read: false, createdAt: FieldValue.serverTimestamp() });
}
