import * as crypto from 'node:crypto';

/**
 * Webhook authenticity.
 *
 * A webhook endpoint is a public URL that moves money data, so verifying the
 * signature is not optional: without it, anyone who guesses the URL can credit
 * themselves revenue by POSTing a JSON body.
 *
 * Two details that are easy to get wrong and hard to notice:
 *
 *  1. **The raw body, not the parsed one.** `JSON.parse` then `stringify` does
 *     not round-trip byte for byte — key order and whitespace change — and the
 *     HMAC is over the exact bytes sent. Express's default JSON parser
 *     discards them, which is why the handlers use the raw body.
 *  2. **A timing-safe comparison.** `===` on a signature leaks, through timing,
 *     how many leading bytes were right, which is enough to forge one a byte at
 *     a time.
 */

/** Timing-safe equality that tolerates different lengths. */
function safeEqual(a: string, b: string): boolean {
  const left = Buffer.from(a, 'utf8');
  const right = Buffer.from(b, 'utf8');
  // timingSafeEqual throws on a length mismatch, which would itself leak the
  // length, so compare hashes of equal size instead.
  const leftHash = crypto.createHash('sha256').update(left).digest();
  const rightHash = crypto.createHash('sha256').update(right).digest();
  return crypto.timingSafeEqual(leftHash, rightHash);
}

/**
 * Whether [rawBody] really came from Shopify.
 *
 * Accepts a list of secrets because there are two ways a webhook can be
 * registered — by the app, signed with the client secret, or in the Shopify
 * admin UI, signed with its own — and a store can have both.
 */
export function verifyShopifyHmac(
  rawBody: Buffer | string,
  headerHmac: string | undefined,
  secrets: Array<string | undefined>,
): boolean {
  if (!headerHmac) return false;

  const body = Buffer.isBuffer(rawBody) ? rawBody : Buffer.from(rawBody, 'utf8');

  for (const secret of secrets) {
    if (!secret) continue;
    const digest = crypto
      .createHmac('sha256', secret)
      .update(body)
      .digest('base64');
    if (safeEqual(digest, headerHmac)) return true;
  }
  return false;
}

/**
 * The topic a webhook is about, e.g. `orders/paid`.
 *
 * Read from the header rather than inferred from the payload, because the
 * payload for `orders/paid` and `orders/updated` is the same shape.
 */
export function webhookTopic(
  headers: Record<string, string | string[] | undefined>,
): string {
  const raw = headers['x-shopify-topic'];
  return Array.isArray(raw) ? (raw[0] ?? '') : (raw ?? '');
}

export function webhookHmacHeader(
  headers: Record<string, string | string[] | undefined>,
): string | undefined {
  const raw = headers['x-shopify-hmac-sha256'];
  return Array.isArray(raw) ? raw[0] : raw;
}
