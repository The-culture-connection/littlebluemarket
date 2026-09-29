import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { getMessaging } from 'firebase-admin/messaging';
import { HttpsError } from 'firebase-functions/v2/https';

import { firestoreDigestDeps, readPrefs, sendDigest, type DigestEntry } from './notifications.ts';
import { announcementMessage, DEFAULT_TZ } from './push.ts';

/**
 * The notification delivery suite on the Diagnostics screen (2026-09-28).
 *
 * The phone that runs it is the device under test. Each step here makes one
 * real thing happen to the person running it, as a "Diagnostics bot"
 * account, through the same triggers and rules as everything else: a
 * comment on their post, a mention, a DM, a forum reply, the digest, an
 * announcement. The phone then waits for the push to actually arrive. This
 * side never says whether a push "worked"; only the phone can.
 *
 * Admins only, and the dev project only: it writes test content, and a
 * production run would put a bot's comments on the live site.
 *
 * Everything a run creates is recorded under `_internal/diagNotify/runs/{uid}`
 * (with the settings it found), so `restore` removes exactly that and puts
 * quiet hours and the rate limit back the way they were.
 */

export const DIAG_BOT = 'diag-bot';
export const DEV_PROJECT = 'little-blue-610e5';

export const DIAG_STEPS = [
  'setup',
  'comment',
  'mention',
  'dm',
  'quietOn',
  'quietOff',
  'forumReply',
  'digestNow',
  'announcement',
  'restore',
] as const;
export type DiagStep = (typeof DIAG_STEPS)[number];

export function isDiagStep(value: unknown): value is DiagStep {
  return typeof value === 'string' && (DIAG_STEPS as readonly string[]).includes(value);
}

/** The private topic only the tester's phone joins. Pure. */
export function diagTopic(uid: string): string {
  return `diag_${uid.replace(/[^A-Za-z0-9_.~-]/g, '')}`;
}

/** "HH:mm" in [tz], [offsetMinutes] from [now]. Pure. */
export function hhmmIn(now: Date, offsetMinutes: number, tz = DEFAULT_TZ): string {
  const at = new Date(now.getTime() + offsetMinutes * 60_000);
  const format = (zone: string) =>
    new Intl.DateTimeFormat('en-GB', { timeZone: zone, hour: '2-digit', minute: '2-digit', hourCycle: 'h23' }).format(at);
  try {
    return format(tz);
  } catch {
    return format(DEFAULT_TZ);
  }
}

/** Quiet hours around now (to test holding), or well away from it. Pure. */
export function quietWindow(now: Date, around: boolean, tz?: string): { quietStart: string; quietEnd: string } {
  return around
    ? { quietStart: hhmmIn(now, -60, tz), quietEnd: hhmmIn(now, 60, tz) }
    : { quietStart: hhmmIn(now, 300, tz), quietEnd: hhmmIn(now, 360, tz) };
}

export function requireDevProject(project: string): void {
  if (project !== DEV_PROJECT) {
    throw new HttpsError(
      'failed-precondition',
      'The delivery tests only run on the dev project: they post test content as a bot.',
    );
  }
}

const text = (nonce: string) => `Diagnostics ${nonce}`;

export async function runDiagStep(uid: string, step: DiagStep, nonce: string): Promise<Record<string, unknown>> {
  const db = getFirestore();
  const run = db.doc(`_internal/diagNotify/runs/${uid}`);
  const settings = db.doc(`users/${uid}/settings/notifications`);
  const remember = (...paths: string[]) => run.set({ created: FieldValue.arrayUnion(...paths) }, { merge: true });
  const postId = `diag_post_${uid}`;
  const threadId = `diag_thread_${uid}`;
  const conversationId = [uid, DIAG_BOT].sort().join('_');
  const now = new Date();

  switch (step) {
    case 'setup': {
      await db.doc(`users/${DIAG_BOT}`).set(
        { name: 'Diagnostics bot', handle: 'diagnostics_bot', revenueCents: 0, purchaseCount: 0, postCount: 0 },
        { merge: true },
      );
      // The settings as they were, kept once: a second setup after a run
      // that died half way must not overwrite the real ones with test ones.
      if (!(await run.get()).exists) {
        const prefs = (await settings.get()).data() ?? {};
        await run.set({
          startedAt: FieldValue.serverTimestamp(),
          had: {
            quietStart: prefs.quietStart ?? null,
            quietEnd: prefs.quietEnd ?? null,
            lastPushAt: prefs.lastPushAt ?? null,
          },
          created: [],
        });
      }
      const prefs = await readPrefs(uid);
      await settings.set({ ...quietWindow(now, false, prefs?.tz), lastPushAt: FieldValue.delete() }, { merge: true });
      await db.doc(`posts/${postId}`).set({
        kind: 'shoutout',
        authorId: uid,
        text: 'Diagnostics test post, removed when the test finishes.',
        tags: [],
        likeCount: 0,
        commentCount: 0,
        createdAt: FieldValue.serverTimestamp(),
      });
      await remember(`posts/${postId}`);
      return { topic: diagTopic(uid) };
    }

    case 'comment': {
      const ref = db.collection('posts').doc(postId).collection('comments').doc(`diag_${nonce}`);
      await ref.set({ authorId: DIAG_BOT, postId, text: text(nonce), likeCount: 0, createdAt: FieldValue.serverTimestamp() });
      await remember(ref.path);
      return {};
    }

    case 'mention': {
      const ref = db.collection('posts').doc(`diag_mention_${nonce}`);
      await ref.set({
        kind: 'shoutout',
        authorId: DIAG_BOT,
        text: text(nonce),
        mentionedUids: [uid],
        tags: [],
        likeCount: 0,
        commentCount: 0,
        createdAt: FieldValue.serverTimestamp(),
      });
      await remember(ref.path);
      return {};
    }

    case 'dm': {
      const conversation = db.collection('conversations').doc(conversationId);
      await conversation.set(
        { participantIds: [uid, DIAG_BOT], preview: text(nonce), lastMessageAt: FieldValue.serverTimestamp() },
        { merge: true },
      );
      const ref = conversation.collection('messages').doc(`diag_${nonce}`);
      await ref.set({ conversationId, authorId: DIAG_BOT, text: text(nonce), createdAt: FieldValue.serverTimestamp() });
      await remember(conversation.path, ref.path);
      return {};
    }

    case 'quietOn':
    case 'quietOff': {
      const prefs = await readPrefs(uid);
      await settings.set(
        { ...quietWindow(now, step === 'quietOn', prefs?.tz), lastPushAt: FieldValue.delete() },
        { merge: true },
      );
      return {};
    }

    case 'forumReply': {
      const thread = db.collection('threads').doc(threadId);
      if (!(await thread.get()).exists) {
        await thread.set({
          forumId: 'diagnostics',
          authorId: uid,
          title: 'Diagnostics test thread',
          body: '',
          commentCount: 0,
          createdAt: FieldValue.serverTimestamp(),
        });
        await remember(thread.path);
      }
      const ref = thread.collection('comments').doc(`diag_${nonce}`);
      await ref.set({ authorId: DIAG_BOT, text: text(nonce), createdAt: FieldValue.serverTimestamp() });
      await remember(ref.path, `users/${uid}/pendingDigest/${threadId}`);
      return {};
    }

    case 'digestNow': {
      // The scheduled job's own code, for this one person, now.
      const snap = await db.collection(`users/${uid}/pendingDigest`).get();
      const entries: DigestEntry[] = snap.docs.map((d) => {
        const entry: DigestEntry = { threadId: d.id, count: Number(d.data().count ?? 0) };
        if (typeof d.data().forumId === 'string') entry.forumId = d.data().forumId;
        return entry;
      });
      if (entries.length === 0) return { outcome: 'nothing waiting' };
      return { outcome: await sendDigest(uid, entries, firestoreDigestDeps, now), threads: entries.length };
    }

    case 'announcement': {
      // Exactly what a real announcement sends, only to this phone's private
      // topic, and with no announcement document: nobody else's bell or
      // feed banner sees it.
      const messageId = await getMessaging().send(
        announcementMessage(
          { topic: diagTopic(uid) },
          { title: 'Diagnostics announcement', body: text(nonce), route: '/you/notifications', announcementId: `diag_${nonce}` },
        ),
      );
      return { messageId };
    }

    case 'restore': {
      const doc = await run.get();
      const data = doc.data() ?? {};
      const had = (data.had ?? {}) as Record<string, unknown>;
      const put = (v: unknown) => (v === null || v === undefined ? FieldValue.delete() : v);
      await settings.set(
        { quietStart: put(had.quietStart), quietEnd: put(had.quietEnd), lastPushAt: put(had.lastPushAt) },
        { merge: true },
      );
      // Deepest first, so a comment goes before the post it is on.
      const created = [...new Set((data.created ?? []) as string[])].sort((a, b) => b.split('/').length - a.split('/').length);
      for (const path of created) await db.doc(path).delete().catch(() => {});
      // The bell rows the bot caused.
      const rows = await db.collection(`users/${uid}/notifications`).where('fromUid', '==', DIAG_BOT).get();
      for (const row of rows.docs) await row.ref.delete();
      await run.delete();
      return { removed: created.length + rows.size };
    }
  }
}
