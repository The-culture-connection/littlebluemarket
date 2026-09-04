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

// ------------------------------------------------------------------- config

export const SHOPIFY_STORE_DOMAIN = defineString('SHOPIFY_STORE_DOMAIN');

/**
 * Pinned deliberately. Shopify deprecates a version every quarter, and an
 * unpinned client starts failing on their schedule rather than yours.
 */
export const SHOPIFY_API_VERSION = defineString('SHOPIFY_API_VERSION', {
  default: '2025-07',
});

/** Public by design in OAuth. */
export const SHOPIFY_CLIENT_ID = defineString('SHOPIFY_CLIENT_ID');

export const SHIPTURTLE_BASE_URL = defineString('SHIPTURTLE_BASE_URL', {
  default: 'https://api.shipturtle.com',
});

/** Every secret a function might need, for the ones that touch everything. */
export const ALL_SECRETS = [
  SHOPIFY_CLIENT_SECRET,
  SHOPIFY_STOREFRONT_PRIVATE_TOKEN,
  SHOPIFY_WEBHOOK_SECRET,
  SHIPTURTLE_API_KEY,
];

/** Signs ShipTurtle's webhooks. Shape to be confirmed against their docs. */
export const SHIPTURTLE_WEBHOOK_SECRET = defineSecret(
  'SHIPTURTLE_WEBHOOK_SECRET',
);
