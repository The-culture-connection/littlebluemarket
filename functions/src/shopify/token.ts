import { getFirestore, Timestamp } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions';

import { SHOPIFY_API_VERSION, SHOPIFY_CLIENT_ID, SHOPIFY_CLIENT_SECRET, SHOPIFY_STORE_DOMAIN } from '../config.ts';

/**
 * Admin API tokens, minted on demand.
 *
 * The store's Admin token comes from the client-credentials grant and expires
 * in about a day, so there is no long-lived token to store. The durable
 * credential is the client secret, and this is the only place it is exchanged.
 *
 * Three things this has to get right, because every seller-side feature
 * depends on it:
 *
 *  1. **Do not stampede.** A cold start burst would otherwise mint one token
 *     per instance. The cross-instance cache lives in Firestore and is written
 *     in a transaction, so the first instance to arrive mints and the rest read.
 *  2. **Refresh early.** At 80% of the lifetime, not at expiry: clock skew
 *     between us and the store otherwise produces intermittent 401s that are
 *     miserable to trace.
 *  3. **Retry exactly once.** A 401 from an Admin call invalidates the cache
 *     and re-mints, then gives up. Looping on a revoked app would spin forever.
 */

interface CachedToken {
  token: string;
  expiresAt: number; // epoch millis
}

/** Warm-instance cache. Survives between invocations on one instance. */
let inProcess: CachedToken | undefined;

/** Where instances agree with each other. Denied to every client by rules. */
const CACHE_DOC = '_internal/shopifyAdminToken';

/** Refresh at 80% of the lifetime rather than at expiry. */
const REFRESH_AT = 0.8;

/** A response missing expires_in is treated as short-lived rather than eternal. */
const FALLBACK_LIFETIME_SECONDS = 60 * 60;

function fresh(cached: CachedToken | undefined): cached is CachedToken {
  return cached !== undefined && Date.now() < cached.expiresAt;
}

/** Exchanges the client secret for a short-lived Admin token. */
async function mint(): Promise<CachedToken> {
  const domain = SHOPIFY_STORE_DOMAIN.value();
  const response = await fetch(`https://${domain}/admin/oauth/access_token`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'client_credentials',
      client_id: SHOPIFY_CLIENT_ID.value(),
      client_secret: SHOPIFY_CLIENT_SECRET.value(),
    }),
  });

  if (!response.ok) {
    // Deliberately does not include the body: an OAuth error response can echo
    // back part of what was sent.
    throw new Error(`Admin token mint failed with ${response.status}`);
  }

  const body = (await response.json()) as {
    access_token?: string;
    expires_in?: number;
  };
  if (!body.access_token) {
    throw new Error('Admin token mint returned no access_token');
  }

  const lifetime = body.expires_in ?? FALLBACK_LIFETIME_SECONDS;
  return {
    token: body.access_token,
    expiresAt: Date.now() + lifetime * 1000 * REFRESH_AT,
  };
}

/**
 * A usable Admin token.
 *
 * Lazy on purpose: a cold start after an idle day pays one mint and nothing
 * else, which is cheaper and simpler than a scheduled refresh that runs all
 * night whether or not anyone is selling.
 */
export async function adminToken(forceRefresh = false): Promise<string> {
  if (!forceRefresh && fresh(inProcess)) return inProcess.token;

  const db = getFirestore();
  const ref = db.doc(CACHE_DOC);

  const cached = await db.runTransaction(async (tx) => {
    if (!forceRefresh) {
      const snapshot = await tx.get(ref);
      const data = snapshot.data() as
        | { token?: string; expiresAt?: Timestamp }
        | undefined;
      const stored: CachedToken | undefined =
        data?.token && data.expiresAt
          ? { token: data.token, expiresAt: data.expiresAt.toMillis() }
          : undefined;

      // Another instance already minted one; use theirs.
      if (fresh(stored)) return stored;
    }

    const minted = await mint();
    tx.set(ref, {
      token: minted.token,
      expiresAt: Timestamp.fromMillis(minted.expiresAt),
      mintedAt: Timestamp.now(),
    });
    logger.info('Minted a Shopify Admin token', {
      expiresAt: new Date(minted.expiresAt).toISOString(),
    });
    return minted;
  });

  inProcess = cached;
  return cached.token;
}

/** Drops both caches, so the next call mints. */
export function invalidateAdminToken(): void {
  inProcess = undefined;
}

/**
 * Runs an Admin GraphQL query, re-minting once on a 401.
 *
 * Every Admin call goes through here; nothing else reads the token. A single
 * retry is deliberate — a revoked app returns 401 forever, and looping on it
 * would turn one misconfiguration into a runaway bill.
 */
export async function adminGraphQL<T>(
  query: string,
  variables: Record<string, unknown> = {},
): Promise<T> {
  const run = async (token: string) => {
    const domain = SHOPIFY_STORE_DOMAIN.value();
    const version = SHOPIFY_API_VERSION.value();
    return fetch(`https://${domain}/admin/api/${version}/graphql.json`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Shopify-Access-Token': token,
      },
      body: JSON.stringify({ query, variables }),
    });
  };

  let response = await run(await adminToken());

  if (response.status === 401) {
    logger.warn('Admin call was rejected; re-minting once');
    invalidateAdminToken();
    response = await run(await adminToken(true));
  }

  if (!response.ok) {
    throw new Error(`Admin API returned ${response.status}`);
  }

  const body = (await response.json()) as {
    data?: T;
    errors?: Array<{ message: string }>;
  };

  if (body.errors?.length) {
    // GraphQL reports failures with a 200, so this is the real error check.
    throw new Error(body.errors.map((e) => e.message).join('; '));
  }
  if (!body.data) throw new Error('Admin API returned no data');
  return body.data;
}
