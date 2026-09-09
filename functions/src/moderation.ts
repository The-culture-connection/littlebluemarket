import { getAuth } from 'firebase-admin/auth';
import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions';
import { HttpsError } from 'firebase-functions/v2/https';

/**
 * Banning and unbanning, admin-only (the callables in index.ts check).
 *
 * A ban is four things, in this order so a half-finished one is still a
 * ban: the sign-in is disabled and its sessions revoked (the person is out
 * within the hour, immediately on their next request); the profile is
 * marked; their posts leave the feed (comments and forum threads keep the
 * author's name but their own posts go); every report about them is marked.
 * Unban restores the sign-in and the mark; the posts do not come back.
 */
export async function banUser(
  uid: string,
  by: string,
  options: { reportId?: string; reason?: string } = {},
): Promise<{ postsRemoved: number; reportsMarked: number }> {
  if (!uid) throw new HttpsError('invalid-argument', 'Which account?');
  if (uid === by) throw new HttpsError('failed-precondition', 'You cannot ban yourself.');
  const db = getFirestore();
  const auth = getAuth();

  try {
    await auth.updateUser(uid, { disabled: true });
    await auth.revokeRefreshTokens(uid);
  } catch (error) {
    const code = (error as { code?: string }).code ?? '';
    if (code !== 'auth/user-not-found') throw error;
    // A profile without a sign-in (already deleted): mark it anyway.
  }

  await db.collection('users').doc(uid).set(
    {
      banned: true,
      bannedAt: FieldValue.serverTimestamp(),
      bannedBy: by,
      bannedReason: options.reason ?? null,
      bannedForReport: options.reportId ?? null,
    },
    { merge: true },
  );
  const seller = await db.collection('sellers').doc(uid).get();
  if (seller.exists && !seller.data()?.revokedAt) {
    await seller.ref.set({ revokedAt: FieldValue.serverTimestamp(), revokedBy: by, revokedReason: 'banned' }, { merge: true });
  }

  let postsRemoved = 0;
  const posts = await db.collection('posts').where('authorId', '==', uid).get();
  for (const doc of posts.docs) {
    await db.recursiveDelete(doc.ref);
    postsRemoved += 1;
  }

  let reportsMarked = 0;
  const reports = await db.collection('reports').where('subjectUid', '==', uid).get();
  const batch = db.batch();
  for (const doc of reports.docs) {
    const open = (doc.data().status ?? 'open') === 'open';
    batch.set(
      doc.ref,
      {
        subjectBanned: true,
        ...(open ? { status: 'banned', resolvedAt: FieldValue.serverTimestamp(), resolvedBy: by } : {}),
      },
      { merge: true },
    );
    reportsMarked += 1;
  }
  await batch.commit();

  logger.info('Banned a member', { uid, by, postsRemoved, reportsMarked, reportId: options.reportId ?? null });
  return { postsRemoved, reportsMarked };
}

export async function unbanUser(uid: string, by: string): Promise<void> {
  if (!uid) throw new HttpsError('invalid-argument', 'Which account?');
  const db = getFirestore();
  try {
    await getAuth().updateUser(uid, { disabled: false });
  } catch (error) {
    const code = (error as { code?: string }).code ?? '';
    if (code !== 'auth/user-not-found') throw error;
  }
  await db.collection('users').doc(uid).set(
    { banned: false, unbannedAt: FieldValue.serverTimestamp(), unbannedBy: by },
    { merge: true },
  );
  const reports = await db.collection('reports').where('subjectUid', '==', uid).get();
  const batch = db.batch();
  for (const doc of reports.docs) batch.set(doc.ref, { subjectBanned: false }, { merge: true });
  await batch.commit();
  logger.info('Unbanned a member', { uid, by });
}
