import { getFirestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions';

/**
 * The lowercase hashtag mirror on a profile.
 *
 * A profile's initiative hashtags are stored as they were typed
 * (`#WomanOwned`), and Firestore's `array-contains` is exact, so a search for
 * `#womanowned` missed them. `tagsLower` is the same list folded to lowercase
 * with one leading `#`, which is what the search reads.
 *
 * Maintained by the `users` trigger rather than trusted from the phone,
 * because the directory sync writes a business's tags server-side too.
 */

/** '#WomanOwned', 'woman owned' -> '#womanowned'. Deduped. Pure. */
export function lowerTags(tags: unknown): string[] {
  if (!Array.isArray(tags)) return [];
  const seen = new Set<string>();
  for (const raw of tags) {
    if (typeof raw !== 'string') continue;
    const tag = raw.trim().toLowerCase();
    if (!tag) continue;
    seen.add(tag.startsWith('#') ? tag : `#${tag}`);
  }
  return [...seen];
}

/** Same members, whatever the order. Pure. */
export function sameTags(a: string[], b: string[]): boolean {
  if (a.length !== b.length) return false;
  const set = new Set(a);
  return b.every((tag) => set.has(tag));
}

/**
 * Writes `tagsLower` when it has drifted from `tags`. Returns whether it
 * wrote. The write re-enters this trigger once, finds the two in step, and
 * stops, so there is no loop.
 */
export async function syncProfileTagsLower(
  uid: string,
  after: Record<string, unknown> | undefined,
): Promise<boolean> {
  if (!uid || !after) return false;
  const wanted = lowerTags(after.tags);
  if (sameTags(wanted, lowerTags(after.tagsLower))) return false;
  await getFirestore()
    .collection('users')
    .doc(uid)
    .set({ tagsLower: wanted }, { merge: true });
  return true;
}

/** Every profile, once: what the admin "Reindex hashtags" button runs. */
export async function backfillProfileTagsLower(): Promise<{
  checked: number;
  updated: number;
}> {
  const db = getFirestore();
  const snapshot = await db.collection('users').get();
  let batch = db.batch();
  let pending = 0;
  let updated = 0;
  for (const doc of snapshot.docs) {
    const data = doc.data();
    const wanted = lowerTags(data.tags);
    if (sameTags(wanted, lowerTags(data.tagsLower))) continue;
    batch.set(doc.ref, { tagsLower: wanted }, { merge: true });
    updated += 1;
    pending += 1;
    if (pending === 400) {
      await batch.commit();
      batch = db.batch();
      pending = 0;
    }
  }
  if (pending > 0) await batch.commit();
  logger.info('Reindexed profile hashtags', { checked: snapshot.size, updated });
  return { checked: snapshot.size, updated };
}
