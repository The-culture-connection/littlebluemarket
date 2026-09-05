import { logger } from 'firebase-functions';
import { CallableRequest, HttpsError } from 'firebase-functions/v2/https';

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
