import { logger } from 'firebase-functions';
import { HttpsError, type CallableRequest } from 'firebase-functions/v2/https';

/**
 * Every callable says what went wrong and what to do about it.
 *
 * An `HttpsError` a handler throws on purpose already carries copy meant for
 * a person, so it passes through untouched. Anything else — a fetch that blew
 * up, a bug — would otherwise reach the app as a bare `INTERNAL`, which is the
 * one message nobody can act on. Those become an `internal` error that names
 * the function, quotes the cause, and says what to run next; the app's dev
 * strip shows it verbatim and "Copy for Claude" makes it a bug report.
 */
export function withLoudErrors<Res>(
  name: string,
  handler: (request: CallableRequest) => Promise<Res>,
): (request: CallableRequest) => Promise<Res> {
  return async (request) => {
    try {
      return await handler(request);
    } catch (error) {
      if (error instanceof HttpsError) throw error;

      const message = error instanceof Error ? error.message : String(error);
      logger.error(`${name} threw`, {
        message,
        stack: error instanceof Error ? error.stack : undefined,
      });
      throw new HttpsError(
        'internal',
        `${name} failed: ${message}. ` +
          'Run npm run doctor; if it is all PASS, paste this to Claude.',
        { operation: name },
      );
    }
  };
}

/**
 * A Shopify "Access denied … Required access: `write_products`" message,
 * reworded for a seller. Anything else comes back unchanged. The store
 * owner is the only person who can grant a scope, so the sentence says so
 * instead of showing a field name nobody in the app can act on.
 */
export function friendlyStoreError(message: string): string {
  const scope = /Required access: `?([a-z_]+)`? access scope/i.exec(message)?.[1];
  if (!scope) return message;
  const what = scope.startsWith('write_products')
    ? 'add or change products'
    : scope.startsWith('write_inventory')
      ? 'set stock'
      : scope.startsWith('write_publications') || scope.startsWith('read_publications')
        ? 'put products in the app'
        : scope.startsWith('write_fulfillments')
          ? 'mark orders shipped'
          : 'do that';
  return `The store has not let the app ${what} yet (Shopify permission "${scope}"). ` +
    'The store owner needs to approve that permission in Shopify; nothing on your side is wrong.';
}
