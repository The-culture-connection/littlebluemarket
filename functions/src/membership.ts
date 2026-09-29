import { createSign } from 'node:crypto';

import { FieldValue, getFirestore, Timestamp } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions';
import { HttpsError } from 'firebase-functions/v2/https';

import {
  ANDROID_PACKAGE_NAME,
  APPLE_BUNDLE_ID,
  APPLE_IAP_KEY,
  APPLE_ISSUER_ID,
  APPLE_KEY_ID,
  MEMBERSHIP_APPLE_PRODUCT_ID,
  MEMBERSHIP_PLAY_PRODUCT_ID,
  MEMBERSHIP_PRICE_CENTS,
  PLAY_SERVICE_ACCOUNT,
} from './config.ts';
import { fundingMonth } from './donation_lines.ts';

/**
 * The monthly membership, verified with the store that sold it.
 *
 * The rule this file exists to keep: **a membership is a grant, never a
 * client write.** A phone says "I bought this, here is the receipt"; the
 * server asks Apple or Google whether that is true and writes the entitlement
 * itself. `users/{uid}.memberUntil` is server-only in the rules for exactly
 * the reason `revenueCents` is.
 *
 * Both stores are asked the same question and answer in different shapes, so
 * the shape-reading is pure and tested ([membershipFrom*]) and only the
 * network calls are not.
 */

/** What a verified receipt amounts to. */
export interface Entitlement {
  /** The moment the membership lapses, from the store, not from our clock. */
  expiresAt: Date;
  /** Whether it is good right now. */
  active: boolean;
  /** The store's own id for this subscription period, for idempotency. */
  periodId: string;
  store: 'apple' | 'google';
}

/** Which store's ids are configured. Empty means the card stays hidden. */
export function membershipProductIds(): { apple: string; google: string } {
  return {
    apple: MEMBERSHIP_APPLE_PRODUCT_ID.value().trim(),
    google: MEMBERSHIP_PLAY_PRODUCT_ID.value().trim(),
  };
}

// ------------------------------------------------------------------ Google

/**
 * A Play `subscriptionsv2` response becomes an entitlement. Pure.
 *
 * Play reports the state in words and the expiry per line item, because one
 * subscription can carry several. There is one here, and taking the latest
 * expiry rather than the first is the difference between an upgrade being
 * honoured and being cut short.
 */
export function membershipFromPlay(
  body: Record<string, any>,
  now: Date = new Date(),
): Entitlement {
  const state = String(body.subscriptionState ?? '');
  const lines = (body.lineItems ?? []) as Array<Record<string, any>>;
  let latest = 0;
  for (const line of lines) {
    const when = Date.parse(String(line.expiryTime ?? ''));
    if (!Number.isNaN(when) && when > latest) latest = when;
  }
  if (!latest) {
    throw new HttpsError('failed-precondition', 'Play sent no expiry time.');
  }
  const expiresAt = new Date(latest);
  return {
    expiresAt,
    // `IN_GRACE_PERIOD` is a member whose card failed and who Google is still
    // retrying: they paid, so they keep what they paid for while Google sorts
    // it out. `ON_HOLD` and `CANCELED` are not, though a cancelled
    // subscription stays good until it expires, which the date carries.
    active:
      expiresAt > now &&
      (state === 'SUBSCRIPTION_STATE_ACTIVE' ||
        state === 'SUBSCRIPTION_STATE_IN_GRACE_PERIOD' ||
        state === 'SUBSCRIPTION_STATE_CANCELED'),
    periodId: String(body.latestOrderId ?? body.linkedPurchaseToken ?? latest),
    store: 'google',
  };
}

/** A Google service account JWT, exchanged for an access token. */
async function playAccessToken(): Promise<string> {
  const raw = PLAY_SERVICE_ACCOUNT.value();
  if (!raw.trim()) {
    throw new HttpsError('failed-precondition', 'No Play service account is set.');
  }
  let key: { client_email?: string; private_key?: string };
  try {
    key = JSON.parse(raw);
  } catch {
    throw new HttpsError(
      'failed-precondition',
      'PLAY_SERVICE_ACCOUNT is not the JSON file Google downloaded.',
    );
  }
  if (!key.client_email || !key.private_key) {
    throw new HttpsError(
      'failed-precondition',
      'The Play service account JSON has no client_email or private_key.',
    );
  }

  const issued = Math.floor(Date.now() / 1000);
  const claim = {
    iss: key.client_email,
    scope: 'https://www.googleapis.com/auth/androidpublisher',
    aud: 'https://oauth2.googleapis.com/token',
    iat: issued,
    exp: issued + 3600,
  };
  const signed = signJwt({ alg: 'RS256', typ: 'JWT' }, claim, key.private_key, 'RSA-SHA256');

  const response = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: signed,
    }),
  });
  const body = (await response.json()) as { access_token?: string; error_description?: string };
  if (!response.ok || !body.access_token) {
    // Never the key, and never the assertion: both are the secret.
    throw new HttpsError(
      'failed-precondition',
      `Google refused the service account: ${body.error_description ?? response.status}`,
    );
  }
  return body.access_token;
}

/** Asks Play whether this purchase token is a live subscription. */
export async function verifyPlayPurchase(purchaseToken: string): Promise<Entitlement> {
  const token = await playAccessToken();
  const pkg = ANDROID_PACKAGE_NAME.value().trim();
  const url =
    `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/` +
    `${encodeURIComponent(pkg)}/purchases/subscriptionsv2/tokens/` +
    `${encodeURIComponent(purchaseToken)}`;

  const response = await fetch(url, {
    headers: { Authorization: `Bearer ${token}` },
  });
  const body = (await response.json()) as Record<string, any>;
  if (!response.ok) {
    const reason = String(body?.error?.message ?? response.status);
    // Play's permissions take hours to propagate after the service account is
    // invited, and the failure then is a flat 401. Saying so here saves the
    // half hour of looking for a bug that is not there.
    throw new HttpsError(
      'failed-precondition',
      `Google would not confirm that purchase: ${reason}. If the service ` +
        'account was invited in the last day, this is usually Play still ' +
        'granting it access.',
    );
  }
  return membershipFromPlay(body);
}

// ------------------------------------------------------------------- Apple

/**
 * An App Store `signedTransactionInfo` payload becomes an entitlement. Pure.
 *
 * Apple gives the dates as milliseconds since the epoch and calls the
 * subscription period's identity `originalTransactionId`.
 */
export function membershipFromApple(
  payload: Record<string, any>,
  now: Date = new Date(),
): Entitlement {
  const expires = Number(payload.expiresDate ?? 0);
  if (!expires) {
    throw new HttpsError('failed-precondition', 'Apple sent no expiry date.');
  }
  const expiresAt = new Date(expires);
  const revoked = Number(payload.revocationDate ?? 0) > 0;
  return {
    expiresAt,
    active: expiresAt > now && !revoked,
    periodId: String(payload.transactionId ?? payload.originalTransactionId ?? expires),
    store: 'apple',
  };
}

/**
 * The middle segment of a JWS, as an object.
 *
 * Not a signature check, and it is not standing in for one: the payload
 * arrives inside an HTTPS response from Apple's own host, to a request Apple
 * authenticated with our key. That is the trust boundary. Decoding a token
 * that arrived anywhere else would need the certificate chain.
 */
export function decodeJwsPayload(jws: string): Record<string, any> {
  const middle = jws.split('.')[1];
  if (!middle) throw new HttpsError('internal', 'Apple sent a token with no payload.');
  const json = Buffer.from(middle, 'base64url').toString('utf8');
  return JSON.parse(json) as Record<string, any>;
}

/** The short-lived token the App Store Server API wants. */
function appleToken(): string {
  const key = APPLE_IAP_KEY.value();
  const issuer = APPLE_ISSUER_ID.value().trim();
  const keyId = APPLE_KEY_ID.value().trim();
  if (!key.trim() || !issuer || !keyId) {
    throw new HttpsError(
      'failed-precondition',
      'The App Store Connect key, issuer id or key id is not set.',
    );
  }
  const issued = Math.floor(Date.now() / 1000);
  return signJwt(
    { alg: 'ES256', kid: keyId, typ: 'JWT' },
    {
      iss: issuer,
      iat: issued,
      exp: issued + 600,
      aud: 'appstoreconnect-v1',
      bid: APPLE_BUNDLE_ID.value().trim(),
    },
    key,
    'SHA256',
    'ieee-p1363',
  );
}

/** Asks Apple whether this transaction is a live subscription. */
export async function verifyAppleTransaction(
  transactionId: string,
  { sandbox = false }: { sandbox?: boolean } = {},
): Promise<Entitlement> {
  const host = sandbox
    ? 'https://api.storekit-sandbox.itunes.apple.com'
    : 'https://api.storekit.itunes.apple.com';
  const response = await fetch(
    `${host}/inApps/v1/subscriptions/${encodeURIComponent(transactionId)}`,
    { headers: { Authorization: `Bearer ${appleToken()}` } },
  );

  // A production key asked about a sandbox purchase gets a 404 with this
  // code. TestFlight buys in the sandbox, so without this every test purchase
  // looks like a lie.
  if (response.status === 404 && !sandbox) {
    const body = (await response.json().catch(() => ({}))) as { errorCode?: number };
    if (body.errorCode === 4040010 || body.errorCode === 4040005) {
      return verifyAppleTransaction(transactionId, { sandbox: true });
    }
  }
  if (!response.ok) {
    throw new HttpsError(
      'failed-precondition',
      `Apple would not confirm that purchase (${response.status}).`,
    );
  }

  const body = (await response.json()) as {
    data?: Array<{ lastTransactions?: Array<{ signedTransactionInfo?: string }> }>;
  };
  const signed = body.data?.[0]?.lastTransactions?.[0]?.signedTransactionInfo;
  if (!signed) {
    throw new HttpsError('failed-precondition', 'Apple knows no such subscription.');
  }
  return membershipFromApple(decodeJwsPayload(signed));
}

// ------------------------------------------------------------------ the grant

/**
 * Writes the entitlement, and counts the money once per period.
 *
 * The period id is the whole of the idempotency: a phone that verifies at
 * every launch, or a renewal seen twice, must move the transparency tiles
 * once. It is a document id under the member's own record, so "have we
 * counted this one" is a read rather than a guess.
 */
export async function grantMembership(
  uid: string,
  entitlement: Entitlement,
): Promise<{ active: boolean; expiresAt: Date; counted: boolean }> {
  const db = getFirestore();
  const memberRef = db.collection('memberships').doc(uid);
  const periodRef = memberRef.collection('periods').doc(entitlement.periodId);
  const priceCents = MEMBERSHIP_PRICE_CENTS.value();
  const month = fundingMonth(entitlement.expiresAt);

  const counted = await db.runTransaction(async (tx) => {
    const seen = (await tx.get(periodRef)).exists;

    tx.set(
      memberRef,
      {
        store: entitlement.store,
        memberUntil: Timestamp.fromDate(entitlement.expiresAt),
        active: entitlement.active,
        lastVerifiedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    // The one field the app reads, on the person, so a profile and a feed
    // know without a second read. Server-only in the rules.
    tx.set(
      db.collection('users').doc(uid),
      {
        memberUntil: Timestamp.fromDate(entitlement.expiresAt),
        // A member has chipped in, and the feed should stop asking.
        chippedInAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    if (seen || !entitlement.active) return false;

    tx.set(periodRef, {
      store: entitlement.store,
      priceCents,
      expiresAt: Timestamp.fromDate(entitlement.expiresAt),
      countedAt: FieldValue.serverTimestamp(),
    });

    // Gross, like the Shopify side: this is what the member gave, not what
    // arrived after the store took its cut. `sources` keeps the two apart so
    // the page can say which is which (addendum, 2026-09-29).
    tx.set(
      db.collection('funding').doc(month),
      {
        raisedCents: FieldValue.increment(priceCents),
        sources: { membership: FieldValue.increment(priceCents) },
        lastGiftAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    return true;
  });

  if (counted) {
    logger.info('Membership period counted', {
      uid,
      store: entitlement.store,
      month,
    });
  }
  return {
    active: entitlement.active,
    expiresAt: entitlement.expiresAt,
    counted,
  };
}

// ----------------------------------------------------------------- plumbing

/** A signed JWT from a header, a claim and a PEM key. */
function signJwt(
  header: Record<string, unknown>,
  claim: Record<string, unknown>,
  key: string,
  algorithm: string,
  dsaEncoding?: 'ieee-p1363',
): string {
  const encode = (value: Record<string, unknown>) =>
    Buffer.from(JSON.stringify(value)).toString('base64url');
  const body = `${encode(header)}.${encode(claim)}`;
  const signer = createSign(algorithm);
  signer.update(body);
  // ES256 wants the raw r|s pair; Node signs DER unless told otherwise, and a
  // DER signature is refused by every JWT reader without explaining why.
  const signature = signer.sign(
    dsaEncoding ? { key: normalisePem(key), dsaEncoding } : normalisePem(key),
  );
  return `${body}.${signature.toString('base64url')}`;
}

/**
 * A PEM that survived a trip through an environment variable.
 *
 * A .p8 or a service account's private_key is multi-line, and every way of
 * getting one into a secret turns the newlines into the two characters `\n`
 * at least some of the time. The failure is an unreadable "error:1E08010C"
 * from OpenSSL, so it is worth the two lines here.
 */
export function normalisePem(key: string): string {
  return key.includes('\\n') ? key.replace(/\\n/g, '\n') : key;
}
