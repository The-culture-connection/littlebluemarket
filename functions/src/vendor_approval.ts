import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';
import { HttpsError } from 'firebase-functions/v2/https';

import {
  companyBrandName,
  grantDecision,
  vendorStringsByCompany,
} from './roster_grant.ts';
import { grantSellerDirect, normalizeVendorName } from './sellers.ts';
import { listVendorUsers } from './shipturtle_api.ts';

/**
 * Approving a vendor from the admin website.
 *
 * Almost no vendor needs this. A Shipturtle vendor confirms the email on
 * their vendor account in the app and the roster match grants their shop,
 * unprompted, within two hours at worst. Claim codes existed for the cases
 * the match refuses on purpose, and issuing one meant a developer running a
 * script and Grace emailing a string (Grace, 2026-09-24: "is there anyway
 * for vendors to be able to claim their shops... without having to send
 * them a code").
 *
 * So the exception moves to where the admin already is. [vendorStatus]
 * answers "who is this email, and can they be approved" in one call, and
 * [approveVendor] does it. Nothing new is trusted: the grant goes through
 * `grantSellerDirect`, the same transaction the automatic path uses, which
 * reserves the vendor name and refuses a name another account holds.
 *
 * The one thing this can do that the automatic path cannot is decide an
 * ambiguity a machine should not: which of two vendor strings is really
 * theirs, or that an email on two companies belongs to this one. That is a
 * judgement, and it is now a judgement an admin makes on purpose rather
 * than a code they mail out.
 */

export interface VendorStatus {
  email: string;
  /** The app account, if there is one for this address. */
  uid: string | null;
  emailVerified: boolean;
  isSeller: boolean;
  /** The vendor string this account already sells as, if any. */
  currentVendorName: string | null;
  /** Shipturtle companies this email is a user of. */
  companyIds: string[];
  /** The vendor strings those companies' products carry. */
  vendorNames: string[];
  /** For each vendor string, the uid already holding it, if any. */
  heldBy: Record<string, string>;
  /** What the automatic path would do, and why it would not. */
  autoDecision: 'grant' | 'refuse';
  autoReason: string;
  /** Whether an admin may approve from here, and what to say if not. */
  canApprove: boolean;
  blocker: string | null;
}

/** Everything the admin website needs to decide, in one call. */
export async function vendorStatus(
  emailRaw: string,
  fetchImpl: typeof fetch = fetch,
): Promise<VendorStatus> {
  const email = emailRaw.trim().toLowerCase();
  if (!email.includes('@')) {
    throw new HttpsError('invalid-argument', 'That is not an email address.');
  }
  const db = getFirestore();

  // The app account, if they have signed up at all.
  let uid: string | null = null;
  let emailVerified = false;
  let isSeller = false;
  try {
    const account = await getAuth().getUserByEmail(email);
    uid = account.uid;
    emailVerified = account.emailVerified;
    isSeller = account.customClaims?.seller === true;
  } catch {
    // No app account yet. Not an error: it is the most useful thing to know.
  }

  let currentVendorName: string | null = null;
  if (uid) {
    const seller = await db.collection('sellers').doc(uid).get();
    const name = String(seller.data()?.shopifyVendorName ?? '').trim();
    currentVendorName = name || null;
  }

  // The Shipturtle roster: which companies this email is a user of.
  const roster = (await listVendorUsers(fetchImpl)) ?? [];
  const companyIds = [
    ...new Set(roster.filter((u) => u.email === email).map((u) => u.companyId)),
  ];

  // The vendor strings those companies sell under. The brand name is the
  // authority when Shipturtle has one, because a vendor approved five
  // minutes ago has no products yet.
  const vendorNames: string[] = [];
  for (const companyId of companyIds) {
    const brand = await companyBrandName(companyId, fetchImpl);
    if (brand) {
      if (!vendorNames.includes(brand)) vendorNames.push(brand);
      continue;
    }
    const byCompany = await vendorStringsByCompany(fetchImpl);
    for (const name of byCompany.get(companyId) ?? []) {
      if (!vendorNames.includes(name)) vendorNames.push(name);
    }
  }

  // Who already holds each of those names.
  const heldBy: Record<string, string> = {};
  for (const name of vendorNames) {
    const held = await db.collection('vendorNames').doc(normalizeVendorName(name)).get();
    const holder = String(held.data()?.uid ?? '');
    if (holder) heldBy[name] = holder;
  }

  const decision = grantDecision({
    uid: uid ?? '',
    companyMatches: companyIds.length,
    vendorStrings: vendorNames,
    reservedBy: vendorNames.length === 1 ? (heldBy[vendorNames[0]!] ?? null) : null,
  });

  // What stops an admin approving, as opposed to what stops the machine.
  // An admin may pick between two vendor strings; they may not conjure an
  // app account, an unconfirmed address or a name somebody else holds.
  let blocker: string | null = null;
  if (!uid) {
    blocker = 'Nobody has signed up with that email yet. Ask them to create a profile first.';
  } else if (!emailVerified) {
    blocker = 'They have not confirmed that email address yet.';
  } else if (isSeller && currentVendorName) {
    blocker = `That account already sells as "${currentVendorName}".`;
  } else if (vendorNames.length === 0) {
    blocker = companyIds.length === 0
      ? 'That email is not on the Shipturtle vendor list.'
      : 'Shipturtle has them, but no vendor name yet. It appears once they have a product or a brand name.';
  }

  return {
    email,
    uid,
    emailVerified,
    isSeller,
    currentVendorName,
    companyIds,
    vendorNames,
    heldBy,
    autoDecision: decision.grant ? 'grant' : 'refuse',
    autoReason: decision.grant ? 'the automatic check would grant this' : decision.reason,
    canApprove: blocker === null,
    blocker,
  };
}

/**
 * Connects a shop to an account, as an admin, after looking at the facts.
 *
 * Re-checks everything rather than trusting what the website was shown: the
 * page may have been open for an hour, and the name may have been claimed in
 * between.
 */
export async function approveVendor(
  emailRaw: string,
  vendorNameRaw: string,
  byUid: string,
  fetchImpl: typeof fetch = fetch,
): Promise<{ uid: string; vendorName: string }> {
  const vendorName = vendorNameRaw.trim();
  if (!vendorName) {
    throw new HttpsError('invalid-argument', 'Which shop? Pick a vendor name.');
  }
  const status = await vendorStatus(emailRaw, fetchImpl);
  if (!status.uid) {
    throw new HttpsError('failed-precondition', status.blocker ?? 'No app account for that email.');
  }
  if (!status.emailVerified) {
    throw new HttpsError('failed-precondition', 'They have not confirmed that email address yet.');
  }
  // The name has to be one Shipturtle actually associates with them. An
  // admin chooses between the vendor's own names; they do not type a
  // stranger's.
  if (!status.vendorNames.includes(vendorName)) {
    throw new HttpsError(
      'failed-precondition',
      `Shipturtle does not list "${vendorName}" for that email. Pick one of: ${status.vendorNames.join(', ') || 'none found'}.`,
    );
  }
  const holder = status.heldBy[vendorName];
  if (holder && holder !== status.uid) {
    throw new HttpsError('failed-precondition', 'Another account already holds that shop.');
  }

  await grantSellerDirect({
    uid: status.uid,
    email: status.email,
    vendorName,
    shipturtleVendorId: status.companyIds[0] ?? null,
    method: 'application',
    by: byUid,
  });
  return { uid: status.uid, vendorName };
}
