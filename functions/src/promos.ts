import { FieldValue, getFirestore, Timestamp } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions';
import { HttpsError } from 'firebase-functions/v2/https';

import { parseHashtags, parseMentionHandles, resolveNamed } from './mentions.ts';
import { isAudience, type Audience } from './push.ts';

/**
 * Adverts and Little Blue announcements: `promos/{id}`.
 *
 * Grace asked for two features on the same day and described the second as
 * "exactly like" the first, so they are one collection with a `kind` on it.
 * The difference is only what else happens when one is posted: an
 * announcement also goes through `sendAnnouncement` (the bell, the push),
 * an advert does not, because an advert is not news.
 *
 * Every write here is admin-only and goes through a callable, so the rules
 * can keep `promos` at `allow write: if false` and the phone can still add
 * to the two counters (`promoRecord` below). Nothing a client sends is
 * trusted: the caps, the kinds and both URLs are checked here.
 */

export const PROMO_TITLE_MAX = 60;
export const PROMO_CAPTION_MAX = 180;
export const PROMO_CTA_LABEL_MAX = 24;
export const PROMO_PHOTOS_MAX = 4;

export const PROMO_KINDS = ['ad', 'announcement'] as const;
export type PromoKind = (typeof PROMO_KINDS)[number];

export function isPromoKind(value: unknown): value is PromoKind {
  return typeof value === 'string' && (PROMO_KINDS as readonly string[]).includes(value);
}

export interface PromoInput {
  kind: PromoKind;
  title: string;
  caption: string;
  audience: Audience;
  imageUrls?: unknown;
  ctaLabel?: string;
  ctaUrl?: string;
  /** ISO strings from the admin website, or nothing for "no bound". */
  startsAt?: string;
  endsAt?: string;
}

export interface CleanPromo {
  kind: PromoKind;
  title: string;
  caption: string;
  audience: Audience;
  imageUrls: string[];
  ctaLabel: string;
  ctaUrl: string;
  startsAt: Timestamp | null;
  endsAt: Timestamp | null;
}

/**
 * Only `https` reaches a phone. A popup's button opens whatever this says in
 * an external browser, so a `javascript:` or `intent:` string here would be
 * a hole in the app rather than a typo in a form. `http` is rejected too:
 * every host worth linking to has had TLS for a decade.
 */
export function cleanUrl(raw: unknown, field: string): string {
  const text = typeof raw === 'string' ? raw.trim() : '';
  if (!text) return '';
  const withScheme = /^[a-z][a-z0-9+.-]*:/i.test(text) ? text : `https://${text}`;
  let url: URL;
  try {
    url = new URL(withScheme);
  } catch {
    throw new HttpsError('invalid-argument', `${field} is not a web address: ${text}`);
  }
  if (url.protocol !== 'https:') {
    throw new HttpsError('invalid-argument', `${field} has to start with https:// (got ${url.protocol}).`);
  }
  if (!url.hostname) {
    throw new HttpsError('invalid-argument', `${field} has no website in it: ${text}`);
  }
  return url.toString();
}

function cleanTime(raw: unknown, field: string): Timestamp | null {
  if (raw === undefined || raw === null || raw === '') return null;
  if (typeof raw !== 'string') {
    throw new HttpsError('invalid-argument', `${field} should be a date.`);
  }
  const ms = Date.parse(raw);
  if (!Number.isFinite(ms)) {
    throw new HttpsError('invalid-argument', `${field} is not a date I can read: ${raw}`);
  }
  return Timestamp.fromMillis(ms);
}

/** Pure, so the caps and the URL rules are unit-testable without Firestore. */
export function validatePromo(input: PromoInput): CleanPromo {
  if (!isPromoKind(input.kind)) {
    throw new HttpsError('invalid-argument', 'Pick whether this is an advert or an announcement.');
  }
  if (!isAudience(input.audience)) {
    throw new HttpsError('invalid-argument', 'Pick who this goes to: all, sellers, buyers or directory.');
  }
  const title = String(input.title ?? '').trim();
  const caption = String(input.caption ?? '').trim();
  if (!title) throw new HttpsError('invalid-argument', 'Give it a title.');
  if (title.length > PROMO_TITLE_MAX) {
    throw new HttpsError('invalid-argument', `Keep the title under ${PROMO_TITLE_MAX} characters.`);
  }
  if (!caption) throw new HttpsError('invalid-argument', 'Write a caption for it.');
  if (caption.length > PROMO_CAPTION_MAX) {
    throw new HttpsError('invalid-argument', `Keep the caption under ${PROMO_CAPTION_MAX} characters.`);
  }

  const photos = Array.isArray(input.imageUrls) ? input.imageUrls : [];
  if (photos.length > PROMO_PHOTOS_MAX) {
    throw new HttpsError('invalid-argument', `At most ${PROMO_PHOTOS_MAX} photos.`);
  }
  const imageUrls = photos.map((u, i) => cleanUrl(u, `Photo ${i + 1}`)).filter((u) => u !== '');

  const ctaLabel = String(input.ctaLabel ?? '').trim();
  if (ctaLabel.length > PROMO_CTA_LABEL_MAX) {
    throw new HttpsError('invalid-argument', `Keep the button's wording under ${PROMO_CTA_LABEL_MAX} characters.`);
  }
  const ctaUrl = cleanCtaTarget(input.ctaUrl);
  // A button with no link is a dead end, and a link with no button is
  // invisible. Both or neither.
  if (Boolean(ctaLabel) !== Boolean(ctaUrl)) {
    throw new HttpsError(
      'invalid-argument',
      'A button needs both its wording and its link, or leave both empty.',
    );
  }

  const startsAt = cleanTime(input.startsAt, 'The start date');
  const endsAt = cleanTime(input.endsAt, 'The end date');
  if (startsAt && endsAt && endsAt.toMillis() <= startsAt.toMillis()) {
    throw new HttpsError('invalid-argument', 'The end date has to be after the start date.');
  }

  return { kind: input.kind, title, caption, audience: input.audience, imageUrls, ctaLabel, ctaUrl, startsAt, endsAt };
}

/**
 * Creates one, or replaces the fields of an existing one. The counters are
 * never written here, so editing an advert does not reset what it has
 * earned.
 */
export async function savePromo(
  input: PromoInput,
  byUid: string,
  id?: string,
): Promise<{ id: string }> {
  const clean = validatePromo(input);
  // The @handles and #hashtags in the title and the caption. Resolved before
  // anything is written, so a mistyped handle is a message in the form
  // rather than a dead link on every phone in the audience.
  // The button's target joins them when it names something in the app, so
  // an @handle on the button is refused here if it matches nobody and
  // carries a uid afterwards. Only then: a web address can contain both an
  // @ and a #, and `https://instagram.com/@someone` resolved as a mention
  // would refuse a perfectly good link.
  const ctaNames = /^[@#]/.test(clean.ctaUrl) ? clean.ctaUrl : '';
  const named = await resolveNamed(clean.title, clean.caption, ctaNames);
  const db = getFirestore();
  const ref = id ? db.collection('promos').doc(id) : db.collection('promos').doc();
  const existing = id ? await ref.get() : null;
  if (id && !existing?.exists) {
    throw new HttpsError('not-found', `There is no promo with the id ${id}.`);
  }
  await ref.set(
    {
      ...clean,
      ...named,
      // A new one starts live; an edit leaves Pause alone.
      ...(existing?.exists ? {} : { active: true, impressions: 0, clicks: 0, createdAt: FieldValue.serverTimestamp() }),
      updatedAt: FieldValue.serverTimestamp(),
      updatedBy: byUid,
    },
    { merge: true },
  );
  logger.info('Promo saved', { id: ref.id, kind: clean.kind, audience: clean.audience, edit: Boolean(id) });
  return { id: ref.id };
}

/** Pause or resume, without losing the numbers. */
export async function setPromoActive(id: string, active: boolean): Promise<{ id: string; active: boolean }> {
  if (!id) throw new HttpsError('invalid-argument', 'Which promo?');
  const ref = getFirestore().collection('promos').doc(id);
  if (!(await ref.get()).exists) {
    throw new HttpsError('not-found', `There is no promo with the id ${id}.`);
  }
  await ref.set({ active, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
  return { id, active };
}

export async function deletePromo(id: string): Promise<{ id: string }> {
  if (!id) throw new HttpsError('invalid-argument', 'Which promo?');
  await getFirestore().collection('promos').doc(id).delete();
  logger.info('Promo deleted', { id });
  return { id };
}

export const PROMO_EVENTS = ['seen', 'tap'] as const;
export type PromoEvent = (typeof PROMO_EVENTS)[number];

export function isPromoEvent(value: unknown): value is PromoEvent {
  return typeof value === 'string' && (PROMO_EVENTS as readonly string[]).includes(value);
}

/**
 * One phone saw a promo, or tapped its button.
 *
 * Open to any signed-in caller, because that is who sees a popup. It can
 * only add one to one of two numbers on a document that already exists, so
 * the worst a bad actor can do is inflate Grace's own statistics; nothing
 * about the app's behaviour reads these fields. `increment` rather than
 * read-modify-write, per the counters rule.
 */
export async function recordPromoEvent(id: string, event: unknown): Promise<{ ok: true }> {
  if (!id || typeof id !== 'string') {
    throw new HttpsError('invalid-argument', 'Which promo?');
  }
  if (!isPromoEvent(event)) {
    throw new HttpsError('invalid-argument', "An event is 'seen' or 'tap'.");
  }
  const field = event === 'seen' ? 'impressions' : 'clicks';
  try {
    await getFirestore()
      .collection('promos')
      .doc(id)
      .update({ [field]: FieldValue.increment(1) });
  } catch (error) {
    // A promo deleted while a phone was looking at it. Not worth an error on
    // the phone, and not worth a log line at error level either.
    logger.info('Promo count skipped', { id, event, message: (error as Error).message });
  }
  return { ok: true };
}

/**
 * Where the button goes: somewhere in the app, or out to the web.
 *
 * Grace, 2026-09-24: "can we also add cta links for things within the app?
 * I would like to add it to be a search of a hashtag or a person's profile."
 * Sending someone to a browser to find a shop that is three taps away was
 * the only thing the button could do, and for an advert about a shop on
 * this market that is the wrong door.
 *
 * The syntax is the one already in use in the copy, so there is nothing new
 * to learn and the admin website's preview already highlights it:
 *
 *   `@polly-politics`  that profile
 *   `#WomenOwned`      that search
 *   anything else      an https address, as before
 *
 * Stored raw, as typed. The phone decides from the first character, and a
 * handle is turned into a uid by `resolveNamed` at save time, alongside the
 * ones in the title and the caption, so a renamed shop keeps working and a
 * handle that matches nobody is refused here rather than becoming a dead
 * button on every phone in the audience.
 */
export function cleanCtaTarget(raw: unknown): string {
  const text = typeof raw === 'string' ? raw.trim() : '';
  if (!text) return '';

  if (text.startsWith('@')) {
    // One handle, not a sentence. Anything else is a typo worth catching
    // while somebody is looking at the form.
    const handles = parseMentionHandles(text);
    if (handles.length !== 1 || `@${handles[0]}` !== text) {
      throw new HttpsError(
        'invalid-argument',
        `The button link has to be one handle on its own, like @polly-politics. Got ${text}`,
      );
    }
    return text;
  }

  if (text.startsWith('#')) {
    const tags = parseHashtags(text);
    if (tags.length !== 1 || tags[0] !== text) {
      throw new HttpsError(
        'invalid-argument',
        `The button link has to be one hashtag on its own, like #WomenOwned. Got ${text}`,
      );
    }
    return text;
  }

  return cleanUrl(text, 'The button link');
}
