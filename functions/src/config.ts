import { defineSecret, defineString } from 'firebase-functions/params';

/**
 * Configuration, split by whether it is a credential.
 *
 * Secrets live in Secret Manager and are declared per function, so a function
 * that does not need the client secret never has it in its environment.
 * Everything else is an identifier and lives in `.env.<projectId>` — Secret
 * Manager bills per access, and a shop domain is not worth paying for.
 *
 * Set the secrets with, e.g.:
 *
 *     firebase functions:secrets:set SHOPIFY_CLIENT_SECRET
 *
 * which prompts for the value, so it never lands in shell history.
 */

// ------------------------------------------------------------------ secrets

/**
 * The durable credential. Two jobs:
 *
 *  - exchanged for a short-lived Admin token (the Admin token itself expires
 *    in ~24h, so there is nothing to store),
 *  - and it signs webhook HMACs for webhooks the app registers.
 */
export const SHOPIFY_CLIENT_SECRET = defineSecret('SHOPIFY_CLIENT_SECRET');

/** Server-side cart and checkout creation. */
export const SHOPIFY_STOREFRONT_PRIVATE_TOKEN = defineSecret(
  'SHOPIFY_STOREFRONT_PRIVATE_TOKEN',
);

/**
 * Only for webhooks created in the Shopify admin UI, which are signed with
 * their own secret rather than the client secret. Set whichever path you use;
 * verification tries both.
 */
export const SHOPIFY_WEBHOOK_SECRET = defineSecret('SHOPIFY_WEBHOOK_SECRET');

/** Vendor attribution and tracking. Still outstanding. */
export const SHIPTURTLE_API_KEY = defineSecret('SHIPTURTLE_API_KEY');

/**
 * Signs ShipTurtle's webhooks — if they sign at all. Their webhook
 * registration form asks only for a topic and a URL, so this may have no
 * source; `authenticateShipTurtleWebhook` accepts an empty value and shouts if
 * a signature header ever turns up.
 *
 * Declared here, above [ALL_SECRETS], and not below it: it used to sit after
 * the array, so the array silently omitted it.
 */
export const SHIPTURTLE_WEBHOOK_SECRET = defineSecret(
  'SHIPTURTLE_WEBHOOK_SECRET',
);

// ------------------------------------------------------------------- config

export const SHOPIFY_STORE_DOMAIN = defineString('SHOPIFY_STORE_DOMAIN');

/**
 * Pinned deliberately. Shopify deprecates a version every quarter, and an
 * unpinned client starts failing on their schedule rather than yours.
 */
export const SHOPIFY_API_VERSION = defineString('SHOPIFY_API_VERSION', {
  default: '2026-07',
});

/** Public by design in OAuth. */
export const SHOPIFY_CLIENT_ID = defineString('SHOPIFY_CLIENT_ID');

export const SHIPTURTLE_BASE_URL = defineString('SHIPTURTLE_BASE_URL', {
  default: 'https://api-v2.shipturtle.com',
});

/**
 * The path that lists the merchant's vendors and their user emails, found by
 * `scripts/shipturtle-probe.mjs`. Empty means "not configured": vendor
 * linking then falls back to claim codes and merchant-written mappings.
 */
export const SHIPTURTLE_VENDORS_PATH = defineString('SHIPTURTLE_VENDORS_PATH', {
  default: '',
});

/**
 * The location a seller's stock is written to: the one that fulfils online
 * orders (the shop's main location). The numeric id, e.g. 121092407456.
 * Empty means "work it out" — see `locations.ts`.
 */
export const SHOPIFY_LOCATION_ID = defineString('SHOPIFY_LOCATION_ID', {
  default: '',
});

/** How the token travels: `Authorization` (Bearer), `x-api-key`, or `access-token`. */
export const SHIPTURTLE_AUTH_HEADER = defineString('SHIPTURTLE_AUTH_HEADER', {
  default: 'Authorization',
});

/** Every secret a function might need, for the ones that touch everything. */
export const ALL_SECRETS = [
  SHOPIFY_CLIENT_SECRET,
  SHOPIFY_STOREFRONT_PRIVATE_TOKEN,
  SHOPIFY_WEBHOOK_SECRET,
  SHIPTURTLE_API_KEY,
  SHIPTURTLE_WEBHOOK_SECRET,
];
