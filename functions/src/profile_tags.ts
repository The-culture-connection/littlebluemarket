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
  const patch = profileMirrorPatch(after);
  if (!patch) return false;
  await getFirestore().collection('users').doc(uid).set(patch, { merge: true });
  return true;
}

/** '  Kali Makes ' -> 'kali makes'. Pure. */
export function nameLower(name: unknown): string {
  return typeof name === 'string' ? name.trim().toLowerCase() : '';
}

/**
 * What a profile's search mirrors should be, or null when they are already
 * right.
 *
 * Two of them now: `tagsLower` for the hashtag search, and `nameLower` for
 * the shop-name prefix scan — people search what a shop calls itself, not
 * its @handle (Grace, 2026-09-23). Pure, so the trigger and the backfill
 * cannot disagree about what "in step" means.
 */
export function profileMirrorPatch(
  after: Record<string, unknown>,
): Record<string, unknown> | null {
  const wantedTags = lowerTags(after.tags);
  const wantedName = nameLower(after.name);
  const tagsDrifted = !sameTags(wantedTags, lowerTags(after.tagsLower));
  const nameDrifted = wantedName !== nameLower(after.nameLower);
  if (!tagsDrifted && !nameDrifted) return null;
  return {
    ...(tagsDrifted ? { tagsLower: wantedTags } : {}),
    ...(nameDrifted ? { nameLower: wantedName } : {}),
  };
}

/** How many posts each author has right now, from the posts themselves. */
export async function postCountsByAuthor(): Promise<Map<string, number>> {
  const snapshot = await getFirestore().collection('posts').select('authorId').get();
  const counts = new Map<string, number>();
  for (const doc of snapshot.docs) {
    const author = doc.get('authorId');
    if (typeof author !== 'string' || !author) continue;
    counts.set(author, (counts.get(author) ?? 0) + 1);
  }
  return counts;
}

/**
 * How many purchases each account has, from the purchase documents.
 *
 * `purchaseCount` is incremented by the order pipeline, which is right, but
 * the one-time store backfill also *sets* it, and a count that can be both
 * incremented and assigned is a count that can drift. This is what the
 * profile grid underneath it actually shows, so it is the answer.
 */
export async function purchaseCountsByBuyer(): Promise<Map<string, number>> {
  const snapshot = await getFirestore().collectionGroup('purchases').select().get();
  const counts = new Map<string, number>();
  for (const doc of snapshot.docs) {
    const uid = doc.ref.parent.parent?.id;
    if (!uid) continue;
    counts.set(uid, (counts.get(uid) ?? 0) + 1);
  }
  return counts;
}

/**
 * Every profile, once: what the admin "Reindex profiles" button runs.
 *
 * Two things, because they are the same walk over `users`: the lowercase
 * hashtag mirror, and `postCount`. The count is written as a total rather
 * than incremented — this is the one place allowed to, because it is derived
 * from the posts and not from a delta, and it is what repairs every profile
 * that posted before the trigger existed.
 */
export async function backfillProfileTagsLower(): Promise<{
  checked: number;
  updated: number;
}> {
  const db = getFirestore();
  const [snapshot, posts, purchases] = await Promise.all([
    db.collection('users').get(),
    postCountsByAuthor(),
    purchaseCountsByBuyer(),
  ]);
  let batch = db.batch();
  let pending = 0;
  let updated = 0;
  for (const doc of snapshot.docs) {
    const data = doc.data();
    const mirrors = profileMirrorPatch(data);
    const wantedPosts = posts.get(doc.id) ?? 0;
    const postsDrifted = Number(data.postCount ?? 0) !== wantedPosts;
    const wantedBuys = purchases.get(doc.id) ?? 0;
    const buysDrifted = Number(data.purchaseCount ?? 0) !== wantedBuys;
    if (!mirrors && !postsDrifted && !buysDrifted) continue;
    batch.set(
      doc.ref,
      {
        ...(mirrors ?? {}),
        ...(postsDrifted ? { postCount: wantedPosts } : {}),
        ...(buysDrifted ? { purchaseCount: wantedBuys } : {}),
      },
      { merge: true },
    );
    updated += 1;
    pending += 1;
    if (pending === 400) {
      await batch.commit();
      batch = db.batch();
      pending = 0;
    }
  }
  if (pending > 0) await batch.commit();
  logger.info('Reindexed profiles', { checked: snapshot.size, updated });
  return { checked: snapshot.size, updated };
}
