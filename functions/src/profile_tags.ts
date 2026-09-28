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

/**
 * The same mirror, on a post.
 *
 * A post's hashtags are stored as typed (`#WomanOwned`) and Firestore's
 * `array-contains` is exact, so a tag page looking for `womanowned` found
 * nothing. It used to guess: `#womanowned`, `#WOMANOWNED`, `#Womanowned`.
 * None of those is `#WomanOwned`, and no list of guesses ever could be —
 * almost every hashtag on this market is two words with an inner capital
 * (#BIPOCOwned, #PlasticFree, #MadeInDetroit), so the tag pages were empty
 * of everything (Grace, 2026-09-28).
 *
 * The key, not the tag: no `#`, lowercased, which is what `hashtags/{key}`
 * is keyed by and what the tag route carries. That way one query answers
 * "everything under this tag" however each post spelled it.
 */
export function tagKeys(tags: unknown): string[] {
  if (!Array.isArray(tags)) return [];
  const seen = new Set<string>();
  for (const raw of tags) {
    if (typeof raw !== 'string') continue;
    const key = raw.trim().replace(/^#/, '').toLowerCase();
    if (key) seen.add(key);
  }
  return [...seen];
}

/** `{ tagsLower }` when a post's mirror has drifted, else null. Pure. */
export function tagKeyMirrorPatch(
  after: Record<string, unknown>,
): Record<string, unknown> | null {
  const wanted = tagKeys(after.tags);
  const current = Array.isArray(after.tagsLower)
    ? after.tagsLower.filter((t): t is string => typeof t === 'string')
    : [];
  return sameTags(wanted, current) ? null : { tagsLower: wanted };
}

/**
 * Writes a document's `tagsLower` when it has drifted. Returns whether it
 * wrote. The write re-enters the trigger once, finds the two in step, and
 * stops.
 *
 * Two collections need this, for the same reason: a post and a catalogue
 * product both store their hashtags as typed, and both are reached by the
 * key. Products are much the bigger half — on the live market nothing had
 * ever tagged a post, and every hashtag on it belongs to something for sale
 * (Grace, 2026-09-28: #CanTEditHistory on a shirt, and an empty page).
 */
export async function syncTagKeyMirror(
  collection: string,
  id: string,
  after: Record<string, unknown> | undefined,
): Promise<boolean> {
  if (!collection || !id || !after) return false;
  const patch = tagKeyMirrorPatch(after);
  if (!patch) return false;
  await getFirestore().collection(collection).doc(id).set(patch, { merge: true });
  return true;
}

/**
 * Fills `tagsLower` in on documents written before it existed, a page at a
 * time. Used for both `posts` and `catalog`.
 *
 * Resumable, and it returns its cursor, because a callable's client gives up
 * at 70 seconds while the function runs to 540: a backfill that only reports
 * at the end reports to nobody. Call it again with the cursor it hands back
 * until `done` is true.
 */
export async function backfillTagKeyMirror(
  collection: string,
  options: { after?: string; limit?: number } = {},
): Promise<{
  checked: number;
  updated: number;
  renamed: number;
  cursor: string | null;
  done: boolean;
}> {
  const db = getFirestore();
  const limit = Math.min(Math.max(options.limit ?? 400, 1), 2000);
  let query = db.collection(collection).orderBy('__name__').limit(limit);
  if (options.after) query = query.startAfter(options.after);

  const snapshot = await query.get();
  let batch = db.batch();
  let pending = 0;
  let updated = 0;
  for (const doc of snapshot.docs) {
    const patch = tagKeyMirrorPatch(doc.data());
    if (!patch) continue;
    batch.set(doc.ref, patch, { merge: true });
    updated += 1;
    pending += 1;
    if (pending === 400) {
      await batch.commit();
      batch = db.batch();
      pending = 0;
    }
  }
  if (pending) await batch.commit();

  // While we are here, put right how each tag is spelled. `hashtags/{key}`
  // holds that, and two things had written the key into it instead of a
  // spelling, so pages came out headed "departmentofdefense". A stored
  // value that does not begin with '#' is one of those; a real one is left
  // exactly as it is, so the first spelling seen still wins.
  const spellings = new Map<string, string>();
  for (const doc of snapshot.docs) {
    for (const raw of (doc.data().tags ?? []) as unknown[]) {
      if (typeof raw !== 'string') continue;
      const trimmed = raw.trim();
      if (!trimmed.startsWith('#')) continue;
      const key = tagKeys([trimmed])[0];
      if (key && !spellings.has(key)) spellings.set(key, trimmed);
    }
  }
  let renamed = 0;
  const keys = [...spellings.keys()];
  for (let i = 0; i < keys.length; i += 200) {
    const slice = keys.slice(i, i + 200);
    const existing = await db.getAll(
      ...slice.map((key) => db.collection('hashtags').doc(key)),
    );
    const fix = db.batch();
    let queued = 0;
    for (const [at, key] of slice.entries()) {
      const stored = existing[at]?.data()?.tag;
      if (typeof stored === 'string' && stored.startsWith('#')) continue;
      fix.set(db.collection('hashtags').doc(key), { tag: spellings.get(key)! }, { merge: true });
      queued += 1;
    }
    if (queued) {
      await fix.commit();
      renamed += queued;
    }
  }

  const done = snapshot.size < limit;
  const cursor = snapshot.empty ? null : snapshot.docs[snapshot.docs.length - 1]!.id;
  logger.info('Tag key mirror backfilled', { collection, checked: snapshot.size, updated, renamed, done });
  return { checked: snapshot.size, updated, renamed, cursor: done ? null : cursor, done };
}
