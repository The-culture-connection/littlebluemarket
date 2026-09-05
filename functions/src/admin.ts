import { getAuth } from 'firebase-admin/auth';
import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions';
import { HttpsError } from 'firebase-functions/v2/https';

/**
 * The admin claim, without a service-account key.
 *
 * Admin-only callables (catalog backfill, collection sync, revoking a seller)
 * check `request.auth.token.admin`. Nothing client-side can mint that claim,
 * and CLAUDE.md forbids a service-account key on a laptop — so the authority
 * is a Firestore document only a project owner can write, in the console:
 *
 *   _internal/admins   { emails: ['grace-s@…'] }
 *
 * `_internal` is denied to every client by rules. A signed-in, verified
 * account whose email is on that list may claim the flag for itself.
 */

export const ADMINS_DOC = '_internal/admins';

/** Pure: is this verified email on the allowlist? */
export function isAllowedAdmin(
  email: string | undefined,
  doc: { emails?: unknown } | undefined,
): boolean {
  if (!email) return false;
  const list = Array.isArray(doc?.emails) ? doc!.emails : [];
  const wanted = email.trim().toLowerCase();
  return list.some((e) => typeof e === 'string' && e.trim().toLowerCase() === wanted);
}

/**
 * Grants `admin: true` to the caller when their verified email is listed.
 * Existing claims (the seller grant) are kept.
 */
export async function claimAdmin(
  uid: string,
  email: string | undefined,
  verified: boolean,
): Promise<{ admin: true }> {
  if (!email || !verified) {
    throw new HttpsError('failed-precondition', 'Confirm your email address first.');
  }
  const db = getFirestore();
  const doc = (await db.doc(ADMINS_DOC).get()).data();
  if (!isAllowedAdmin(email, doc)) {
    throw new HttpsError(
      'permission-denied',
      `${email} is not on the admin list. A project owner adds it in the Firebase ` +
        `console: Firestore -> collection _internal -> document admins -> field emails (array).`,
    );
  }

  const auth = getAuth();
  const user = await auth.getUser(uid);
  await auth.setCustomUserClaims(uid, { ...(user.customClaims ?? {}), admin: true });
  await db.collection('_internal').doc('adminAudit').collection('events').add({
    uid,
    email,
    method: 'allowlist',
    at: FieldValue.serverTimestamp(),
  });
  logger.info('Granted admin', { uid });
  return { admin: true };
}

/** The three-fact check every admin callable runs. */
export function requireAdmin(claims: Record<string, unknown> | undefined): void {
  if (claims?.admin !== true) {
    throw new HttpsError(
      'permission-denied',
      'Admins only. Diagnostics -> Claim admin, after your email is on the admin list.',
    );
  }
}
