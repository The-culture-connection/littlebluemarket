import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions';
import { HttpsError } from 'firebase-functions/v2/https';

/**
 * Little Blue Market's own pages, posted to the For you feed: `storePages/{id}`.
 *
 * Grace, 2026-10-28, from the QA suite: "I want to show the shopify pages on
 * the homescreen when they are posted. Add something to the admin portal to
 * select pages from shopify and post them on the for you feed".
 *
 * The list of pages comes from the store's public sitemap, and each page's
 * title, summary and picture from the tags the theme already writes for link
 * previews. Nothing here needs a Shopify credential or a new API scope: these
 * are public pages, read the way any link preview reads them. Always the live
 * store, even on the dev project, because the dev store is password-protected
 * and its pages are not the ones anybody would post.
 */
export const STORE_SITE = 'https://littlebluemarket.com';

export const STORE_PAGE_TITLE_MAX = 80;
export const STORE_PAGE_BLURB_MAX = 180;

/** Pages that exist for the theme's machinery, not to be read. */
const NOT_FOR_READING = /\/pages\/(swym-|seller-profile$|data-sharing-opt-out$)/;

export interface StorePageListing {
  url: string;
  title: string;
  blurb: string;
  imageUrl: string;
}

/** Every `<loc>` in a sitemap, decoded. Pure. */
export function sitemapLocs(xml: string): string[] {
  return [...xml.matchAll(/<loc>([^<]+)<\/loc>/g)].map((m) => decodeEntities((m[1] ?? '').trim()));
}

function decodeEntities(text: string): string {
  return text
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#39;|&#x27;/g, "'")
    .replace(/&nbsp;/g, ' ');
}

/** One `<meta>` tag's content by property or name, or ''. Pure. */
function meta(html: string, key: string): string {
  for (const tag of html.match(/<meta\b[^>]*>/gi) ?? []) {
    const named = new RegExp(`(?:property|name)\\s*=\\s*["']${key}["']`, 'i').test(tag);
    if (!named) continue;
    const content = /content\s*=\s*"([^"]*)"|content\s*=\s*'([^']*)'/i.exec(tag);
    return decodeEntities((content?.[1] ?? content?.[2] ?? '').trim());
  }
  return '';
}

/**
 * What a page says about itself for a link preview. The store's name is
 * taken off the end of the title ("About us – Little Blue Market"). Pure.
 */
export function previewOf(url: string, html: string): StorePageListing {
  const rawTitle =
    meta(html, 'og:title') ||
    decodeEntities(/<title[^>]*>([^<]*)<\/title>/i.exec(html)?.[1]?.trim() ?? '');
  const title = rawTitle.replace(/\s*[–|-]\s*Little Blue Market\s*$/i, '').trim();
  let imageUrl = meta(html, 'og:image:secure_url') || meta(html, 'og:image');
  if (imageUrl.startsWith('//')) imageUrl = `https:${imageUrl}`;
  if (imageUrl.startsWith('http://')) imageUrl = `https://${imageUrl.slice(7)}`;
  return {
    url,
    title: title.slice(0, STORE_PAGE_TITLE_MAX),
    blurb: (meta(html, 'og:description') || meta(html, 'description')).slice(0, STORE_PAGE_BLURB_MAX),
    imageUrl: imageUrl.startsWith('https://') ? imageUrl : '',
  };
}

async function fetchText(url: string, retries = 2): Promise<string> {
  const response = await fetch(url, {
    headers: { 'user-agent': 'LittleBlueCartApp/1.0 (+https://littlebluemarket.com)' },
    signal: AbortSignal.timeout(15_000),
  });
  // Shopify answers 429 when asked for pages too quickly; it means "wait".
  if (response.status === 429 && retries > 0) {
    await new Promise((resolve) => setTimeout(resolve, 2_000));
    return fetchText(url, retries - 1);
  }
  if (!response.ok) throw new Error(`${url} answered ${response.status}`);
  return response.text();
}

/**
 * The store's readable pages, named from their addresses. One request to
 * the sitemap and nothing more: reading every page for its preview got the
 * app rate-limited by Shopify after a couple of tries (2026-10-28), so only
 * the page picked is read, by [previewStorePage].
 */
export async function listStorePages(): Promise<StorePageListing[]> {
  const index = await fetchText(`${STORE_SITE}/sitemap.xml`);
  const pageMaps = sitemapLocs(index).filter((u) => /sitemap_pages_/.test(u));
  const urls: string[] = [];
  for (const map of pageMaps) urls.push(...sitemapLocs(await fetchText(map)));
  const readable = urls.filter((u) => u.startsWith(`${STORE_SITE}/pages/`) && !NOT_FOR_READING.test(u));
  // The policies are pages too, but no sitemap lists them.
  readable.push(`${STORE_SITE}/policies/refund-policy`, `${STORE_SITE}/policies/privacy-policy`);
  return readable
    .map((url) => ({ url, title: handleTitle(url), blurb: '', imageUrl: '' }))
    .sort((x, y) => x.title.localeCompare(y.title));
}

/**
 * One page's own title, summary and picture, for the form to start from.
 * A page that will not load comes back with its address-made title, so it
 * can still be posted with words typed by hand.
 */
export async function previewStorePage(url: string): Promise<StorePageListing> {
  const clean = validateStorePage({ url, title: handleTitle(url) || 'page' });
  try {
    const preview = previewOf(clean.url, await fetchText(clean.url));
    return { ...preview, title: preview.title || clean.title };
  } catch (error) {
    logger.warn('Store page preview failed', { url, error: String(error) });
    return { url: clean.url, title: clean.title, blurb: '', imageUrl: '' };
  }
}

/** "holiday-gift-guide" as "Holiday gift guide", for a page that would not load. */
function handleTitle(url: string): string {
  const handle = url.split('/').pop() ?? '';
  const words = handle.replace(/-\d+$/, '').replace(/-/g, ' ');
  return words.charAt(0).toUpperCase() + words.slice(1);
}

export interface StorePageInput {
  url?: unknown;
  title?: unknown;
  blurb?: unknown;
  imageUrl?: unknown;
}

/** Pure, so the rules are unit-testable without Firestore. */
export function validateStorePage(input: StorePageInput): StorePageListing {
  const url = String(input.url ?? '').trim();
  let parsed: URL;
  try {
    parsed = new URL(url);
  } catch {
    throw new HttpsError('invalid-argument', `That is not a web address. Got ${url || '(nothing)'}`);
  }
  // Only the store's own pages: this card says "from Little Blue Market",
  // and a link anywhere else under that name would be a lie on every phone.
  if (parsed.protocol !== 'https:' || parsed.hostname !== new URL(STORE_SITE).hostname) {
    throw new HttpsError('invalid-argument', `Only pages on ${STORE_SITE} can be posted. Got ${url}`);
  }
  if (!/^\/(pages|policies|blogs)\//.test(parsed.pathname)) {
    throw new HttpsError('invalid-argument', 'Pick one of the store\'s pages, a policy or a blog post.');
  }
  const title = String(input.title ?? '').trim();
  if (!title) throw new HttpsError('invalid-argument', 'Give it a title.');
  if (title.length > STORE_PAGE_TITLE_MAX) {
    throw new HttpsError('invalid-argument', `Keep the title under ${STORE_PAGE_TITLE_MAX} characters.`);
  }
  const blurb = String(input.blurb ?? '').trim();
  if (blurb.length > STORE_PAGE_BLURB_MAX) {
    throw new HttpsError('invalid-argument', `Keep the summary under ${STORE_PAGE_BLURB_MAX} characters.`);
  }
  const imageUrl = String(input.imageUrl ?? '').trim();
  if (imageUrl && !imageUrl.startsWith('https://')) {
    throw new HttpsError('invalid-argument', 'The picture has to be an https address, or leave it empty.');
  }
  return { url: parsed.toString(), title, blurb, imageUrl };
}

export async function postStorePage(input: StorePageInput, byUid: string): Promise<{ id: string }> {
  const clean = validateStorePage(input);
  const ref = getFirestore().collection('storePages').doc();
  await ref.set({
    ...clean,
    active: true,
    createdAt: FieldValue.serverTimestamp(),
    postedBy: byUid,
  });
  logger.info('Store page posted', { id: ref.id, url: clean.url });
  return { id: ref.id };
}

export async function setStorePageActive(id: string, active: boolean): Promise<{ id: string; active: boolean }> {
  if (!id) throw new HttpsError('invalid-argument', 'Which page?');
  const ref = getFirestore().collection('storePages').doc(id);
  if (!(await ref.get()).exists) throw new HttpsError('not-found', `There is no posted page with the id ${id}.`);
  await ref.set({ active, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
  return { id, active };
}

export async function deleteStorePage(id: string): Promise<{ id: string }> {
  if (!id) throw new HttpsError('invalid-argument', 'Which page?');
  await getFirestore().collection('storePages').doc(id).delete();
  return { id };
}
