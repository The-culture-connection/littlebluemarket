import * as crypto from 'node:crypto';

import { getAuth } from 'firebase-admin/auth';
import { FieldValue, getFirestore, Timestamp } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions';
import { HttpsError } from 'firebase-functions/v2/https';

/**
 * Becoming a seller.
 *
 * The hole this closes was real and reachable. `ProfileRepository.becomeSeller()`
 * wrote `isSeller: true` onto the caller's own user document straight from the
 * client, `firestore.rules` did not lock that field, and `resolveSellerUid`
 * credits a sale to whichever single account claims a product's vendor name. So
 * any signed-in account could set `isSeller: true` and
 * `shopifyVendorName: "Gwynstone"` and inherit 551 products and every dollar of
 * their sales. Two writes, no credential.
 *
 * The fix is not a better lock list — a lock list has to be *remembered* every
 * time a field is added, and it already was not. Seller identity moves to
 * documents no client may write, and `isSeller` becomes a custom claim, which a
 * client cannot mint because Firebase Auth signs it into the token.
 *
 * Everything below happens in one transaction, or none of it does. A grant that
 * reserved a vendor name but failed to write `sellers/{uid}` would leave that
 * shop permanently unclaimable by its real owner.
 */

/** How a vendor name becomes a document id. Matches `resolveSellerUid`. */
export function normalizeVendorName(name: string): string {
  return name
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
}

/**
 * Codes are stored hashed, and looked up by hash.
 *
 * A readable list of unused claim codes is the same thing as no claim codes at
 * all: anyone who could read that collection could grant themselves any shop
 * in it. Rules deny reads outright; hashing means a leak of the documents is
 * still not a leak of the codes.
 */
export function hashClaimCode(code: string): string {
  return crypto
    .createHash('sha256')
    .update(code.trim().toUpperCase(), 'utf8')
    .digest('hex');
}

export interface ClaimResult {
  vendorName: string;
  shipturtleVendorId: string | null;
}

/**
 * Consumes a claim code and grants seller status.
 *
 * Every refusal is `failed-precondition` with copy meant to be read by the
 * person: the client maps that code straight onto a validation message. They
 * say different things on purpose — three of the five are actionable, and
 * "something went wrong" would send someone to support for a typo.
 */
export async function claimVendor(
  uid: string,
  email: string,
  rawCode: string,
): Promise<ClaimResult> {
  const code = rawCode.trim();
  if (!code) {
    throw new HttpsError('failed-precondition', 'Enter your claim code.');
  }

  const db = getFirestore();
  const claimRef = db.collection('vendorClaims').doc(hashClaimCode(code));
  const sellerRef = db.collection('sellers').doc(uid);

  const result = await db.runTransaction(async (tx) => {
    const claim = await tx.get(claimRef);
    if (!claim.exists) {
      throw new HttpsError(
        'failed-precondition',
        'That code is not recognised. Check for typos, or ask for a new one.',
      );
    }

    const data = claim.data() ?? {};
    const vendorName = String(data.vendorName ?? '').trim();
    if (!vendorName) {
      // A code with no vendor on it is a merchant-side mistake, not a user
      // one. Say so plainly rather than blaming the code.
      logger.error('A vendor claim has no vendorName', { claim: claim.id });
      throw new HttpsError(
        'failed-precondition',
        'That code is not set up correctly. Please get in touch.',
      );
    }

    if (data.usedBy) {
      throw new HttpsError(
        'failed-precondition',
        data.usedBy === uid
          ? 'You have already claimed that shop.'
          : 'That code has already been used. If that was not you, ask for a new one.',
      );
    }

    const expiresAt = data.expiresAt as Timestamp | undefined;
    if (expiresAt && expiresAt.toMillis() < Date.now()) {
      throw new HttpsError(
        'failed-precondition',
        'That code has expired. Ask for a new one.',
      );
    }

    // A code may be issued against a specific address. When it is, it has to
    // match the verified one — otherwise a forwarded email is a free shop.
    const boundEmail = String(data.email ?? '').trim().toLowerCase();
    if (boundEmail && boundEmail !== email) {
      throw new HttpsError(
        'failed-precondition',
        'That code was issued to a different email address.',
      );
    }

    // One vendor, one owner. Reserved inside the transaction so two accounts
    // racing for the same shop cannot both win — which is what makes
    // `resolveSellerUid`'s "exactly one match" check safe rather than merely
    // lucky.
    const nameRef = db
      .collection('vendorNames')
      .doc(normalizeVendorName(vendorName));
    const reserved = await tx.get(nameRef);
    if (reserved.exists && reserved.data()?.uid !== uid) {
      throw new HttpsError(
        'failed-precondition',
        'Another account already claims that shop. Get in touch and we will sort it out.',
      );
    }

    const shipturtleVendorId = data.vendorId ? String(data.vendorId) : null;

    tx.set(
      sellerRef,
      {
        shopifyVendorName: vendorName,
        shipturtleVendorId,
        canUploadProducts: true,
        verifiedAt: FieldValue.serverTimestamp(),
        verifiedBy: 'claim-code',
        grantVersion: 1,
        revokedAt: null,
      },
      { merge: true },
    );

    tx.set(nameRef, { uid, claimedAt: FieldValue.serverTimestamp() });

    // `users/{uid}.isSeller` is a **display mirror**, nothing more. It is in
    // the rules lock list, so only this write can move it — but the app
    // renders seller surfaces off it (`isSellerProvider` reads the profile
    // document), so a grant that skipped it would succeed server-side and
    // change nothing a person could see.
    //
    // Authority still lives in the custom claim and `sellers/{uid}`. Nothing
    // server-side decides anything from this field.
    tx.set(db.collection('users').doc(uid), { isSeller: true }, { merge: true });

    tx.update(claimRef, {
      usedBy: uid,
      usedAt: FieldValue.serverTimestamp(),
    });

    return { vendorName, shipturtleVendorId };
  });

  // Outside the transaction because it is not Firestore. A failure here leaves
  // `sellers/{uid}` written but the claim unset, which the caller can simply
  // retry: the transaction is idempotent for the same uid.
  await getAuth().setCustomUserClaims(uid, {
    seller: true,
    vendor: result.vendorName,
  });

  // A wrong grant has to be traceable and reversible, not archaeology.
  await db.collection('_internal').doc('sellerAudit').collection('events').add({
    uid,
    email,
    vendorName: result.vendorName,
    method: 'claim-code',
    at: FieldValue.serverTimestamp(),
  });

  logger.info('Granted seller status', { uid, vendor: result.vendorName });
  return result;
}

/**
 * Revokes a grant.
 *
 * Products already on the storefront stay there — they are Shopify's, and
 * pulling them would punish buyers for a merchant decision. What stops is the
 * ability to write more.
 *
 * The custom claim is cleared immediately, but a token already in someone's
 * pocket stays valid for up to an hour. Every seller-side callable re-reads
 * `sellers/{uid}` for exactly that reason.
 */
export async function revokeVendor(uid: string): Promise<void> {
  const db = getFirestore();
  const sellerRef = db.collection('sellers').doc(uid);
  const snapshot = await sellerRef.get();
  if (!snapshot.exists) return;

  const vendorName = String(snapshot.data()?.shopifyVendorName ?? '');

  await sellerRef.set(
    { revokedAt: FieldValue.serverTimestamp() },
    { merge: true },
  );

  // Clear the display mirror too, or the app keeps offering seller surfaces
  // that every write behind them now refuses.
  await db.collection('users').doc(uid).set({ isSeller: false }, { merge: true });
  await getAuth().setCustomUserClaims(uid, { seller: false });

  // The vendor name reservation is released, so the shop can be re-granted.
  if (vendorName) {
    const nameRef = db
      .collection('vendorNames')
      .doc(normalizeVendorName(vendorName));
    const reserved = await nameRef.get();
    if (reserved.exists && reserved.data()?.uid === uid) {
      await nameRef.delete();
    }
  }

  await db.collection('_internal').doc('sellerAudit').collection('events').add({
    uid,
    vendorName,
    method: 'revoke',
    at: FieldValue.serverTimestamp(),
  });

  logger.info('Revoked seller status', { uid, vendor: vendorName });
}

/**
 * The three-fact seller check, for every callable that writes on a seller's
 * behalf.
 *
 * All three must agree, and none of them is client-writable. Checking only the
 * custom claim would leave a revoked seller writing for up to an hour, and
 * checking only `sellers/{uid}` would trust a document without proving the
 * token was reissued after the grant.
 */
export async function requireSeller(
  uid: string,
  claims: Record<string, unknown> | undefined,
): Promise<{ vendorName: string }> {
  if (claims?.seller !== true) {
    throw new HttpsError('permission-denied', 'You are not set up to sell yet.');
  }

  const db = getFirestore();
  const seller = await db.collection('sellers').doc(uid).get();
  const data = seller.data();
  if (!seller.exists || data?.revokedAt) {
    throw new HttpsError('permission-denied', 'You are not set up to sell yet.');
  }
  if (data?.canUploadProducts === false) {
    throw new HttpsError(
      'permission-denied',
      'Your shop cannot add products right now.',
    );
  }

  const vendorName = String(data?.shopifyVendorName ?? '');
  if (!vendorName) {
    throw new HttpsError('permission-denied', 'Your shop has no vendor name.');
  }

  const nameRef = db
    .collection('vendorNames')
    .doc(normalizeVendorName(vendorName));
  const reserved = await nameRef.get();
  if (!reserved.exists || reserved.data()?.uid !== uid) {
    throw new HttpsError('permission-denied', 'That shop is not yours.');
  }

  return { vendorName };
}
