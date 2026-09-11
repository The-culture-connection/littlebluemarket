import { getAuth } from 'firebase-admin/auth';
import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions';
import { HttpsError } from 'firebase-functions/v2/https';

/**
 * "Delete my account", and "delete my data but keep my account".
 *
 * Both stores require a page anyone can reach, signed in or not, where a
 * person asks for their information to be removed. The page files a request
 * here; a person acts on it. Deletion is not automatic on purpose: an account
 * can be a shop with live orders behind it, and an irreversible one-tap
 * wipe triggered by a stranger who typed an address is worse than a day's
 * wait.
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
  options: { requestId?: string; keepAccount?: boolean } = {},
): Promise<{ postsRemoved: number; profileRemoved: boolean }> {
  if (!uid) throw new HttpsError('invalid-argument', 'Which account?');
  if (uid === by) {
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
