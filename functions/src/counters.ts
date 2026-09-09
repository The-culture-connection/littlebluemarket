/**
 * Counters move from subcollections, never from a client writing a total.
 *
 * The rules lock every count (`commentCount`, `likeCount`, `memberCount`,
 * `threadCount`, the rating histogram). A client creates the comment, the
 * like, the membership or the thread; the trigger moves the number. That is
 * what keeps two people acting in the same second from losing one of the
 * two, and what keeps a count from being anything a phone typed.
 */

import type { DocumentReference } from 'firebase-admin/firestore';
import { FieldValue } from 'firebase-admin/firestore';

/**
 * Moves one counter on a document that should exist. `update`, not
 * `set(merge)`: when a post is deleted and its comments are then removed,
 * the comment trigger fires for a parent that is gone, and a merge would
 * bring it back as a ghost document with nothing but a count on it. A
 * missing parent is simply nothing to count.
 */
export async function bumpCounter(
  ref: DocumentReference,
  field: string,
  delta: number,
): Promise<void> {
  if (delta === 0) return;
  try {
    await ref.update({ [field]: FieldValue.increment(delta) });
  } catch (error) {
    const code = (error as { code?: number | string })?.code;
    if (code === 5 || code === 'not-found' || /NOT_FOUND/.test(String(error))) return;
    throw error;
  }
}

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
