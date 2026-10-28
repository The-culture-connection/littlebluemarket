import { Parser } from 'htmlparser2';

/**
 * A store page as the app draws it on its own screen, rather than as a web
 * page in a browser (Grace, 2026-10-28, from the QA suite: "I wanted the
 * pages to be posted and able to be opened natively in the app").
 *
 * The store's pages are built from theme sections (a picture and some
 * words, a row of questions, a button), not from one block of text, so this
 * reads the page's main area in order and keeps what a person reads: the
 * headings, the paragraphs, the bullet points, the pictures and the buttons.
 * Everything that is the theme's machinery (scripts, forms, hidden copies
 * for screen readers or for a phone layout) is left behind.
 */
export type PageBlock =
  | { kind: 'heading' | 'text' | 'bullet'; text: string; link?: string }
  | { kind: 'image'; url: string; link?: string }
  | { kind: 'button'; label: string; url: string };

/** Enough for the longest page on the store, with room to spare. */
export const PAGE_BLOCKS_MAX = 300;
const TEXT_MAX = 2_000;

/** Never read inside these. */
const SKIP = new Set([
  'script', 'style', 'noscript', 'svg', 'template', 'form', 'select', 'iframe',
  'video', 'button', 'nav', 'dialog', 'head', 'input', 'textarea', 'object',
]);

/** Tags that never close, so they never go on the stack. */
const VOID = new Set([
  'area', 'base', 'br', 'col', 'embed', 'hr', 'img', 'input', 'link', 'meta',
  'source', 'track', 'wbr',
]);

/** Tags whose start or end is the end of a run of words. */
const BREAKS = new Set([
  'p', 'div', 'section', 'article', 'aside', 'header', 'footer', 'li', 'ul', 'ol',
  'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'blockquote', 'td', 'th', 'tr', 'table',
  'dd', 'dt', 'dl', 'details', 'summary', 'figure', 'figcaption', 'br', 'hr', 'main',
]);

/** Class names themes use for "not shown" or "only for a screen reader". */
const HIDDEN_CLASSES = new Set([
  'hidden', 'visually-hidden', 'sr-only', 'hide', 'no-js', 'no-js-hidden',
  'visually-hidden--inline', 'skip-to-content-link',
]);

const HEADINGS = /^h[1-6]$/;

/** An address on the page made whole: `//cdn…` and `/pages/…` included. */
export function absoluteUrl(raw: string, site: string): string {
  const href = raw.trim();
  if (!href || href.startsWith('#') || /^(javascript|mailto|tel):/i.test(href)) return '';
  if (href.startsWith('//')) return `https:${href}`;
  try {
    const url = new URL(href, site);
    if (url.protocol === 'http:') url.protocol = 'https:';
    return url.protocol === 'https:' ? url.toString() : '';
  } catch {
    return '';
  }
}

function isHidden(attrs: Record<string, string>): boolean {
  if ('hidden' in attrs) return true;
  if (attrs['aria-hidden'] === 'true') return true;
  if (/display\s*:\s*none/i.test(attrs.style ?? '')) return true;
  return (attrs.class ?? '').split(/\s+/).some((c) => HIDDEN_CLASSES.has(c));
}

function isButtonLink(attrs: Record<string, string>): boolean {
  return /(^|[\s_-])(btn|button)([\s_-]|$)/i.test(attrs.class ?? '');
}

/** The picture an `<img>` shows, preferring a decent size over a thumbnail. */
function imageOf(attrs: Record<string, string>, site: string): string {
  const width = Number(attrs.width ?? '');
  if (width && width < 120) return '';
  const raw = attrs.src || attrs['data-src'] || '';
  if (!raw || raw.startsWith('data:') || /\.svg(\?|$)/i.test(raw)) return '';
  const url = absoluteUrl(raw, site);
  if (!url) return '';
  // Shopify sizes a picture by its `width` query; ask for one a phone
  // screen can use, whatever the theme's smallest was.
  try {
    const u = new URL(url);
    if (u.pathname.includes('/cdn/') || u.hostname.endsWith('shopify.com')) {
      u.searchParams.set('width', '1200');
      return u.toString();
    }
  } catch {
    // Kept as it was.
  }
  return url;
}

/**
 * The blocks of a store page, read from its HTML. Pure, so it is tested
 * against saved copies of the real pages.
 */
export function pageBlocks(html: string, site: string): PageBlock[] {
  const blocks: PageBlock[] = [];
  const seenImages = new Set<string>();
  const stack: string[] = [];
  let mainDepth = -1;
  let skipDepth = -1;
  let words = '';
  let wordsKind: 'heading' | 'text' | 'bullet' = 'text';
  let button: { url: string; label: string; depth: number } | null = null;
  // The ordinary link the reader is inside, if any: a gift guide's tiles
  // are a picture and a heading that both go to a collection.
  let anchor: { url: string; depth: number } | null = null;
  let wordsLink = '';

  const inMain = () => mainDepth >= 0;
  const skipping = () => skipDepth >= 0;

  const flush = () => {
    const text = words.replace(/\s+/g, ' ').trim().slice(0, TEXT_MAX);
    words = '';
    const link = wordsLink;
    wordsLink = '';
    if (!text) return;
    const last = blocks[blocks.length - 1];
    // Themes often write the same words twice, one copy per screen size.
    if (last && 'text' in last && last.text === text) return;
    blocks.push(link ? { kind: wordsKind, text, link } : { kind: wordsKind, text });
  };

  const kindHere = (): 'heading' | 'text' | 'bullet' => {
    if (stack.some((t) => HEADINGS.test(t))) return 'heading';
    if (stack.includes('li')) return 'bullet';
    return 'text';
  };

  const parser = new Parser(
    {
      onopentag(name, attrs) {
        const tag = name.toLowerCase();
        if (!VOID.has(tag)) stack.push(tag);
        if (tag === 'main' && mainDepth === -1) mainDepth = stack.length;
        if (!inMain() || skipping()) return;
        if (!VOID.has(tag) && (SKIP.has(tag) || isHidden(attrs))) {
          skipDepth = stack.length;
          return;
        }
        if (tag === 'img') {
          const url = imageOf(attrs, site);
          if (url && !seenImages.has(url.split('?')[0] ?? url)) {
            seenImages.add(url.split('?')[0] ?? url);
            flush();
            blocks.push(anchor ? { kind: 'image', url, link: anchor.url } : { kind: 'image', url });
          }
          return;
        }
        if (tag === 'a' && !button && isButtonLink(attrs)) {
          const url = absoluteUrl(attrs.href ?? '', site);
          if (url) {
            flush();
            button = { url, label: '', depth: stack.length };
            return;
          }
        }
        if (tag === 'a' && !anchor) {
          const url = absoluteUrl(attrs.href ?? '', site);
          if (url) anchor = { url, depth: stack.length };
        }
        if (BREAKS.has(tag)) flush();
      },
      ontext(text) {
        if (!inMain() || skipping()) return;
        if (button) {
          button.label += text;
          return;
        }
        if (!words.trim()) {
          wordsKind = kindHere();
          wordsLink = anchor?.url ?? '';
        }
        words += text;
      },
      onclosetag(name) {
        const tag = name.toLowerCase();
        if (VOID.has(tag)) {
          if (tag === 'br' && inMain() && !skipping() && !button) flush();
          return;
        }
        const depth = stack.length;
        if (button && depth === button.depth) {
          const label = button.label.replace(/\s+/g, ' ').trim();
          if (label) blocks.push({ kind: 'button', label: label.slice(0, 60), url: button.url });
          button = null;
        } else if (anchor && depth === anchor.depth) {
          // A link that is a whole heading or paragraph keeps its address;
          // one inside a sentence is just words.
          if (wordsLink && words.trim()) flush();
          anchor = null;
        } else if (inMain() && !skipping() && BREAKS.has(tag)) {
          flush();
        }
        if (skipDepth === depth) skipDepth = -1;
        if (mainDepth === depth) {
          flush();
          mainDepth = -2; // Only the first <main>; nothing after it is the page.
        }
        // Close back to the matching tag, so a theme's stray end tag does
        // not leave the stack (and so "inside a heading") wrong for the
        // rest of the page.
        const at = stack.lastIndexOf(tag);
        if (at >= 0) stack.length = at;
        if (skipDepth > stack.length) skipDepth = -1;
        if (button && button.depth > stack.length) button = null;
        if (anchor && anchor.depth > stack.length) anchor = null;
      },
    },
    { decodeEntities: true, lowerCaseTags: true },
  );
  parser.write(html);
  parser.end();
  flush();

  // A heading with nothing under it before the next heading is a section
  // title for something the app does not draw (a form, a product grid).
  const kept = blocks.filter((b, i) => {
    if (b.kind !== 'heading') return true;
    const next = blocks[i + 1];
    return next !== undefined && next.kind !== 'heading';
  });
  return kept.slice(0, PAGE_BLOCKS_MAX);
}
