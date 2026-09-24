import { getFirestore } from 'firebase-admin/firestore';
import { HttpsError } from 'firebase-functions/v2/https';

/**
 * The `@handles` and `#hashtags` in an announcement or an advert.
 *
 * Grace, 2026-09-24: "the ability to @profiles in announcements or
 * advertisements, also hashtags". A post has carried both for a long time;
 * these two had neither, so naming a shop in an advert was plain grey text.
 *
 * Two rules make this worth doing on the backend rather than leaving it to
 * the phone to parse:
 *
 *  1. **A handle that matches nobody is caught here**, when one admin is
 *     looking at a form, rather than becoming a dead link on every phone in
 *     the audience. An advert outlives the moment it was written.
 *  2. **The uid is stored, not just the handle.** Handles change — that is
 *     the whole point of being able to edit one — and an advert that ran in
 *     March should still open the right shop in September. Posts already
 *     solve it this way with `mentionedUids`.
 *
 * The patterns are deliberately the same as `parseMentionHandles` and
 * `parseHashtags` in `lib/models/notification.dart`. If one changes, both
 * change: the phone highlights what these two find.
 */

/** '@kali and @Found.House!' -> ['kali', 'Found.House']. Pure. */
export function parseMentionHandles(text: string): string[] {
  const seen = new Set<string>();
  const out: string[] = [];
  for (const match of text.matchAll(/(?<![\w.])@([A-Za-z0-9_.-]+)/g)) {
    // A full stop that ends a sentence, or a dash between phrases, is
    // punctuation rather than part of a handle. The hyphen is IN the class
    // on purpose: a shop shell handle is `@romantique-books`.
    const handle = (match[1] ?? '').replace(/[.-]+$/, '');
    if (!handle) continue;
    const key = handle.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    out.push(handle);
  }
  return out;
}

/** '#PlasticFree and #plasticfree' -> ['#PlasticFree']. Pure. */
export function parseHashtags(text: string): string[] {
  const seen = new Set<string>();
  const out: string[] = [];
  for (const match of text.matchAll(/#(\w+)/g)) {
    const word = match[1] ?? '';
    if (!word) continue;
    const key = word.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    out.push(`#${word}`);
  }
  return out;
}

/** What a piece of copy names: handle (lowercased) -> uid, and its tags. */
export interface NamedInText {
  /** Keyed lowercase, because that is how a reader will have typed it. */
  mentions: Record<string, string>;
  tags: string[];
}

/**
 * Resolves every `@handle` in [texts] to a uid, and collects the hashtags.
 *
 * Throws naming the ones that match nobody, because the alternative is an
 * advert that quietly does nothing when tapped. The message lists them all
 * rather than the first, so a form with two typos is fixed once.
 */
export async function resolveNamed(...texts: string[]): Promise<NamedInText> {
  const joined = texts.filter(Boolean).join('\n');
  const handles = parseMentionHandles(joined);
  const tags = parseHashtags(joined);
  if (handles.length === 0) return { mentions: {}, tags };

  const users = getFirestore().collection('users');
  const found = await Promise.all(
    handles.map(async (handle) => {
      const key = handle.toLowerCase().replace(/^@/, '');
      const snapshot = await users.where('handleLower', '==', key).limit(1).get();
      return { handle, key, uid: snapshot.docs[0]?.id ?? '' };
    }),
  );

  const missing = found.filter((f) => !f.uid).map((f) => `@${f.handle}`);
  if (missing.length > 0) {
    throw new HttpsError(
      'invalid-argument',
      // No colon anywhere in these: the admin website shows an
      // invalid-argument message with everything before the first ": "
      // stripped off, so a lead-in ending in one would be thrown away.
      missing.length === 1
        ? `Nobody on Little Blue Market has the handle ${missing[0]}. Check the spelling, or take it out.`
        : `Nobody on Little Blue Market has these handles. ${missing.join(', ')}. Check the spelling, or take them out.`,
    );
  }

  const mentions: Record<string, string> = {};
  for (const f of found) mentions[f.key] = f.uid;
  return { mentions, tags };
}
