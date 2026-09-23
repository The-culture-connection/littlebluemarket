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

/**
 * The same, but never below zero.
 *
 * A count of things that exist cannot be negative, and one that is stays
 * that way: nothing pushes it back up but the things themselves. On
 * 2026-09-24 a repair deleted 263 posts that had been written before this
 * counter existed, so the count went from 0 to **-263** and a profile read
 * "-263 Posts".
 *
 * This is the one counter that reads before it writes, against the rule in
 * the file header, and the trade is deliberate: a lost decrement under
 * contention is invisible and the reindex corrects it, while a negative is
 * visible to the person whose profile it is and corrects itself never.
 * Deletes are rare next to creates, so the contention this risks is rare
 * too. Increments still go the fast way.
 */
export async function bumpCounterFloored(
  ref: DocumentReference,
  field: string,
  delta: number,
): Promise<void> {
  if (delta === 0) return;
  if (delta > 0) return bumpCounter(ref, field, delta);
  try {
    await ref.firestore.runTransaction(async (tx) => {
      const snapshot = await tx.get(ref);
      if (!snapshot.exists) return; // a missing parent is nothing to count
      const current = Number(snapshot.get(field) ?? 0) || 0;
      tx.update(ref, { [field]: Math.max(0, current + delta) });
    });
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
