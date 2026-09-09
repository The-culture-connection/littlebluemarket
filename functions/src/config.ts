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

/**
 * littlebluecart.com (WordPress + WooCommerce), Stage 10. All three are made
 * on the *staging* site for the dev project and again on the live site at
 * cutover. Declared above [ALL_SECRETS] for the same reason as the one above.
 *
 * A WordPress Application Password for an administrator: looking a member up
 * by email (`/wp/v2/users?search=…&context=edit`) needs `list_users`.
 */
export const WP_APP_PASSWORD = defineSecret('WP_APP_PASSWORD');

/** A WooCommerce REST key pair with Read permission: a customer's orders. */
export const WC_CONSUMER_KEY = defineSecret('WC_CONSUMER_KEY');
export const WC_CONSUMER_SECRET = defineSecret('WC_CONSUMER_SECRET');

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
 * Where a new seller applies, on the website. Differs between the dev store
 * and the real one, so it lives in the env, not the app.
 */
export const REGISTRATION_URL = defineString('REGISTRATION_URL', { default: '' });

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

// ------------------------------------------------------- littlebluecart.com

/**
 * The WordPress site behind the directory. For the dev project this is the
 * Cloudways *staging* copy of littlebluecart.com, never the live site (the
 * doctor fails on the live host). Empty means the directory features are off,
 * and every directory callable says so instead of guessing.
 */
export const WP_BASE_URL = defineString('WP_BASE_URL', { default: '' });

/** The WordPress administrator login the Application Password belongs to. */
export const WP_APP_USER = defineString('WP_APP_USER', { default: '' });

/**
 * `yes` lets the dev project read the LIVE littlebluecart.com. Grace's call
 * (2026-09-08): there is no staging copy to be had without a Cloudways login,
 * and the app never writes to WordPress (adding a listing goes through the
 * website's own form; the WooCommerce key is Read). The doctor still says so
 * in yellow on every run, so it is never forgotten.
 */
export const WP_LIVE_OK = defineString('WP_LIVE_OK', { default: '' });

/**
 * Where a business adds itself to the directory: the website form, because
 * the plans, the payment and the review queue live there. Dev points at the
 * staging copy, prod at littlebluecart.com.
 */
export const DIRECTORY_ADD_LISTING_URL = defineString('DIRECTORY_ADD_LISTING_URL', {
  default: '',
});

/** Every secret a function might need, for the ones that touch everything. */
export const ALL_SECRETS = [
  SHOPIFY_CLIENT_SECRET,
  SHOPIFY_STOREFRONT_PRIVATE_TOKEN,
  SHOPIFY_WEBHOOK_SECRET,
  SHIPTURTLE_API_KEY,
  SHIPTURTLE_WEBHOOK_SECRET,
  WP_APP_PASSWORD,
  WC_CONSUMER_KEY,
  WC_CONSUMER_SECRET,
];

/** The three the directory functions need; nothing else. */
export const WP_SECRETS = [WP_APP_PASSWORD, WC_CONSUMER_KEY, WC_CONSUMER_SECRET];

// ------------------------------------------------------------------- mail

/**
 * The branded confirmation email (Stage 16).
 *
 * Firebase's own "verify your email" mail is plain text from a Google
 * address, so the app sends its own instead: the link comes from the Admin
 * SDK, the HTML from `verify_email.ts`, and delivery goes over SMTP. Any
 * mailbox that offers SMTP works: a Google Workspace address with an App
 * Password, Brevo, SendGrid's SMTP relay, Resend's SMTP endpoint.
 *
 * Only the password is a secret; the host, port, login and From line are
 * identifiers and live in `.env.<projectId>`. While `SMTP_HOST` is empty or
 * `SMTP_PASS` is still the `unset` placeholder, `sendVerificationEmail`
 * says so and the app falls back to Firebase's plain mail, so nobody is
 * ever left without a link.
 */
export const SMTP_PASS = defineSecret('SMTP_PASS');

export const SMTP_HOST = defineString('SMTP_HOST', { default: '' });
export const SMTP_PORT = defineString('SMTP_PORT', { default: '465' });
export const SMTP_USER = defineString('SMTP_USER', { default: '' });

/** The From line, e.g. `Little Blue Market <hello@littlebluecart.com>`. */
export const MAIL_FROM = defineString('MAIL_FROM', { default: '' });

/**
 * Where the confirmation page and the email's cart image are served from:
 * the project's Firebase Hosting site (`hosting/` in the repo). Empty means
 * `https://<projectId>.web.app`, which every project has without setup.
 */
export const PUBLIC_WEB_URL = defineString('PUBLIC_WEB_URL', { default: '' });
