import { getAuth } from 'firebase-admin/auth';
import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions';
import { HttpsError } from 'firebase-functions/v2/https';

/**
 * "Delete my account", and "delete my data but keep my account".
 *
 * Both stores require a page anyone can reach, signed in or not, where a
 * person asks for their information to be removed. There are two doors:
 *
 *  * **Signed in, it happens at once** (`deleteMyAccount`, added
 *    2026-09-14 at Grace's request). Waiting on a person to act is a review
 *    risk, and the original objection to automating it does not apply here:
 *    it was about "an irreversible one-tap wipe triggered by a stranger who
 *    typed an address", and this door can only be opened by the account
 *    itself, having signed in minutes ago, having typed the word, and not
 *    holding the admin claim.
 *  * **Signed out, it is still a request** (`requestAccountDeletion`):
 *    somebody who cannot get in has only an address to offer, which is
 *    exactly the case that must not be automatic. A person checks it.
 *
 * The address is taken from the signed-in account when there is one, so a
 * request filed from inside the app can never name somebody else.
 */

const NOTE_MAX = 1000;

export interface DeletionRequestInput {
  email?: unknown;
  scope?: unknown;
  note?: unknown;
}

/** 'account' | 'data'. Anything else is treated as the whole account. Pure. */
export function deletionScope(raw: unknown): 'account' | 'data' {
  return String(raw ?? '') === 'data' ? 'data' : 'account';
}

/** Loose on purpose: a person reads these, and a typo beats a refusal. Pure. */
export function plausibleEmail(raw: unknown): string {
  const email = String(raw ?? '').trim().toLowerCase();
  if (email.length < 5 || email.length > 320) return '';
  if (!email.includes('@') || !email.includes('.') || /\s/.test(email)) return '';
  return email;
}

export async function requestAccountDeletion(
  input: DeletionRequestInput,
  auth: { uid?: string; token?: Record<string, unknown> } | undefined,
): Promise<{ id: string }> {
  const db = getFirestore();
  const uid = auth?.uid ?? null;

  // Signed in: the address is the account's, never what was typed.
  const fromToken = plausibleEmail(auth?.token?.email);
  const email = fromToken || plausibleEmail(input.email);
  if (!email) {
    throw new HttpsError('invalid-argument', 'That does not look like an email address.');
  }

  const note = String(input.note ?? '').slice(0, NOTE_MAX);
  const scope = deletionScope(input.scope);

  // One open request per address is enough; a second tap should not fill the
  // list with duplicates.
  const existing = await db
    .collection('deletionRequests')
    .where('email', '==', email)
    .where('status', '==', 'open')
    .limit(1)
    .get();
  const open = existing.docs[0];
  if (open) {
    await open.ref.set(
      { scope, note: note || open.data().note || '', updatedAt: FieldValue.serverTimestamp() },
      { merge: true },
    );
    return { id: open.id };
  }

  let name = '';
  if (uid) {
    const profile = await db.collection('users').doc(uid).get();
    name = String(profile.data()?.name ?? '');
  }

  const doc = db.collection('deletionRequests').doc();
  await doc.set({
    email,
    uid,
    name,
    scope,
    note,
    status: 'open',
    createdAt: FieldValue.serverTimestamp(),
  });
  logger.info('Account deletion requested', { id: doc.id, scope, signedIn: Boolean(uid) });
  return { id: doc.id };
}

/**
 * Carries out a deletion. Admin only.
 *
 * What goes: the sign-in, the profile and everything filed under it (devices,
 * settings, notifications, addresses, the copy of their purchases, who they
 * follow), and their posts with the comments and likes underneath them.
 *
 * What stays, and why: orders. They are the merchant's financial records and
 * the seller's record of a sale, and both are kept for tax and dispute
 * reasons. The privacy policy says so. The buyer's own copy under their
 * profile does go.
 */
export async function deleteAccountData(
  uid: string,
  by: string,
  options: { requestId?: string; keepAccount?: boolean; self?: boolean } = {},
): Promise<{ postsRemoved: number; profileRemoved: boolean }> {
  if (!uid) throw new HttpsError('invalid-argument', 'Which account?');
  // An admin deleting themselves is almost always a slip, and there may be
  // no other admin to undo it. Deleting your OWN account from the app is a
  // different act and says so explicitly.
  if (uid === by && !options.self) {
    throw new HttpsError('failed-precondition', 'Use another admin account to delete this one.');
  }
  const db = getFirestore();

  let postsRemoved = 0;
  const posts = await db.collection('posts').where('authorId', '==', uid).get();
  for (const doc of posts.docs) {
    await db.recursiveDelete(doc.ref);
    postsRemoved += 1;
  }

  const seller = await db.collection('sellers').doc(uid).get();
  if (seller.exists && !seller.data()?.revokedAt) {
    await seller.ref.set(
      { revokedAt: FieldValue.serverTimestamp(), revokedBy: by, revokedReason: 'account deleted' },
      { merge: true },
    );
  }

  let profileRemoved = false;
  if (!options.keepAccount) {
    // The profile and every subcollection under it.
    await db.recursiveDelete(db.collection('users').doc(uid));
    profileRemoved = true;
    try {
      await getAuth().deleteUser(uid);
    } catch (error) {
      const code = (error as { code?: string }).code ?? '';
      if (code !== 'auth/user-not-found') throw error;
    }
  } else {
    // Keeping the account: strip what is theirs to remove, leave the shell.
    await db.collection('users').doc(uid).set(
      {
        bio: '',
        tags: [],
        tagsLower: [],
        avatarUrl: null,
        cityState: '',
        lat: null,
        lng: null,
        geohash: null,
        dataErasedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  }

  if (options.requestId) {
    await db.collection('deletionRequests').doc(options.requestId).set(
      {
        status: 'done',
        handledAt: FieldValue.serverTimestamp(),
        handledBy: by,
        postsRemoved,
      },
      { merge: true },
    );
  }

  logger.info('Account data deleted', { uid, by, postsRemoved, profileRemoved });
  return { postsRemoved, profileRemoved };
}

// ------------------------------------------------------- deleting your own

/** The word someone types to mean it. Checked here, not just in the app. */
export const DELETE_CONFIRMATION = 'DELETE';

/**
 * How recently they must have signed in. Short enough that a phone left on
 * a table cannot be used to wipe an account, long enough to read the screen
 * and think about it.
 */
export const REAUTH_WINDOW_MS = 10 * 60_000;

export interface SelfDeleteInput {
  confirm?: unknown;
  scope?: unknown;
}

/**
 * Was this token minted from a sign-in recent enough to trust with
 * something irreversible? Pure, so the window is testable.
 *
 * `auth_time` is when the person actually signed in, not when the token was
 * refreshed, which is the whole point: a token that refreshes itself every
 * hour must not keep the door open for ever.
 */
export function signedInRecently(
  token: Record<string, unknown> | undefined,
  now = Date.now(),
  window = REAUTH_WINDOW_MS,
): boolean {
  const seconds = Number(token?.auth_time);
  if (!Number.isFinite(seconds) || seconds <= 0) return false;
  const age = now - seconds * 1000;
  // A clock a little ahead of ours is not a reason to refuse.
  return age < window && age > -5 * 60_000;
}

/**
 * Deletes the caller's own account, or just their data, at once.
 *
 * Four things have to be true, and all four are checked here rather than in
 * the app, because a screen can be skipped and a callable cannot:
 *
 *  1. They are signed in, and it is their own account by construction: the
 *     uid comes from the verified token and is never passed in.
 *  2. They signed in within [REAUTH_WINDOW_MS]. Otherwise a borrowed,
 *     unlocked phone is enough to erase somebody.
 *  3. They typed [DELETE_CONFIRMATION]. Two taps are easy to do by
 *     accident; typing a word is not.
 *  4. They do not hold the admin claim. Removing the merchant account would
 *     take the Admin screen, the announcements and the moderation queue with
 *     it, possibly with nobody left able to put it back.
 *
 * What goes and what stays is exactly what the admin path does, including
 * keeping orders as financial records, because it IS the admin path: this
 * only opens the door.
 */
export async function deleteMyAccount(
  uid: string,
  token: Record<string, unknown> | undefined,
  input: SelfDeleteInput = {},
  now = Date.now(),
): Promise<{ postsRemoved: number; profileRemoved: boolean; scope: 'account' | 'data' }> {
  if (!uid) throw new HttpsError('unauthenticated', 'Sign in first.');

  if (token?.admin === true) {
    throw new HttpsError(
      'failed-precondition',
      'This is the Little Blue Market admin account. Remove the admin flag from it first, ' +
        'or delete it from the Firebase console, so the app is not left without a merchant.',
    );
  }

  if (String(input.confirm ?? '') !== DELETE_CONFIRMATION) {
    throw new HttpsError(
      'invalid-argument',
      `Type ${DELETE_CONFIRMATION} to confirm.`,
    );
  }

  if (!signedInRecently(token, now)) {
    throw new HttpsError(
      'failed-precondition',
      'For your safety, sign out and sign in again, then delete within ten minutes.',
    );
  }

  const scope = deletionScope(input.scope);
  const result = await deleteAccountData(uid, uid, {
    keepAccount: scope === 'data',
    self: true,
  });

  // Any request they had already filed is now answered, so it should not sit
  // in the merchant's list waiting for somebody to act on it.
  const db = getFirestore();
  const email = plausibleEmail(token?.email);
  if (email) {
    const open = await db
      .collection('deletionRequests')
      .where('email', '==', email)
      .where('status', '==', 'open')
      .get();
    for (const doc of open.docs) {
      await doc.ref.set(
        {
          status: 'done',
          handledAt: FieldValue.serverTimestamp(),
          handledBy: 'self',
          postsRemoved: result.postsRemoved,
        },
        { merge: true },
      );
    }
  }

  logger.info('Account deleted by its owner', { uid, scope, postsRemoved: result.postsRemoved });
  return { ...result, scope };
}
