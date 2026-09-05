import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions';
import { HttpsError } from 'firebase-functions/v2/https';

import { grantSellerDirect } from './sellers.ts';

/**
 * Becoming a seller without a code and without being in Shipturtle yet.
 *
 * The applicant writes `sellerApplications/{uid}` themselves (rules: once,
 * their own, with the email their token carries). An admin approves it in
 * the app, naming the vendor string the shop will sell as, and the same
 * grant the claim code makes is made here. The admin approving a verified
 * app account *is* the identity check a claim code used to be.
 */

export type Decision =
  | { approve: true; vendorName: string }
  | { approve: false; reason: string };

/** Pure: what an admin's answer must carry to be acted on. */
export function parseDecision(data: Record<string, unknown> | undefined): Decision {
  const approve = data?.approve === true;
  if (approve) {
    const vendorName = String(data?.vendorName ?? '').trim();
    if (!vendorName) throw new HttpsError('invalid-argument', 'Approving needs the vendor string the shop sells as.');
    return { approve: true, vendorName };
  }
  const reason = String(data?.reason ?? '').trim();
  if (!reason) throw new HttpsError('invalid-argument', 'Declining needs a reason the applicant will read.');
  return { approve: false, reason };
}

export async function decideApplication(
  adminUid: string,
  applicantUid: string,
  decision: Decision,
): Promise<{ status: 'approved' | 'declined'; vendorName?: string }> {
  if (!applicantUid) throw new HttpsError('invalid-argument', 'Which application?');
  const db = getFirestore();
  const ref = db.collection('sellerApplications').doc(applicantUid);
  const snap = await ref.get();
  const data = snap.data();
  if (!snap.exists || !data) throw new HttpsError('not-found', 'That application no longer exists.');
  if (data.status === 'approved') {
    throw new HttpsError('failed-precondition', 'That application was already approved.');
  }

  if (decision.approve) {
    const email = String(data.appliedEmail ?? '');
    await grantSellerDirect({
      uid: applicantUid,
      email,
      vendorName: decision.vendorName,
      shipturtleVendorId: data.shipturtleVendorId ? String(data.shipturtleVendorId) : null,
      method: 'application',
      by: adminUid,
    });
    await ref.set(
      { status: 'approved', vendorName: decision.vendorName, decidedBy: adminUid, decidedAt: FieldValue.serverTimestamp(), reason: null },
      { merge: true },
    );
    logger.info('Approved a seller application', { applicantUid, vendorName: decision.vendorName, adminUid });
    return { status: 'approved', vendorName: decision.vendorName };
  }

  await ref.set(
    { status: 'declined', reason: decision.reason, decidedBy: adminUid, decidedAt: FieldValue.serverTimestamp() },
    { merge: true },
  );
  logger.info('Declined a seller application', { applicantUid, adminUid });
  return { status: 'declined' };
}
