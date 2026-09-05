/**
 * Counters move from subcollections, never from a client writing a total.
 *
 * The rules lock every count (`commentCount`, `likeCount`, `memberCount`,
 * `threadCount`, the rating histogram). A client creates the comment, the
 * like, the membership or the thread; the trigger moves the number. That is
 * what keeps two people acting in the same second from losing one of the
 * two, and what keeps a count from being anything a phone typed.
 */

/** +1 when a document appears, -1 when it disappears, 0 for an edit. Pure. */
export function counterDelta(beforeExists: boolean, afterExists: boolean): number {
  if (!beforeExists && afterExists) return 1;
  if (beforeExists && !afterExists) return -1;
  return 0;
}

/** The star a review adds to the histogram, clamped to the five bars. */
export function starKey(rating: unknown): string | null {
  const n = Number(rating);
  if (!Number.isFinite(n)) return null;
  return `stars${Math.min(5, Math.max(1, Math.round(n)))}`;
}
