import { strict as assert } from 'node:assert';
import { test } from 'node:test';

import { previewOf, sitemapLocs, STORE_SITE, validateStorePage } from '../src/store_pages.ts';

// Grace, 2026-10-28 (QA suite): store pages posted to the For you feed.

test('a sitemap is read for its addresses, entities decoded', () => {
  const xml = `<urlset><url><loc>${STORE_SITE}/pages/about</loc></url>
    <url><loc>${STORE_SITE}/sitemap_pages_1.xml?from=1&amp;to=2</loc></url></urlset>`;
  assert.deepEqual(sitemapLocs(xml), [`${STORE_SITE}/pages/about`, `${STORE_SITE}/sitemap_pages_1.xml?from=1&to=2`]);
});

test('a page preview takes the link-preview tags, minus the store name', () => {
  const html = `<html><head><title>Ignored</title>
    <meta property="og:title" content="About us &ndash; x">
    <meta property="og:title" content="Our story – Little Blue Market">
    <meta name="description" content="Small shops, big hearts &amp; more.">
    <meta property="og:image" content="//littlebluemarket.com/cdn/a.jpg">
  </head></html>`;
  const p = previewOf(`${STORE_SITE}/pages/about`, html);
  // The first og:title wins, as a link preview would take it.
  assert.equal(p.title, 'About us &ndash; x');
  assert.equal(p.blurb, 'Small shops, big hearts & more.');
  assert.equal(p.imageUrl, 'https://littlebluemarket.com/cdn/a.jpg');

  const plain = previewOf(`${STORE_SITE}/pages/faqs`, '<title>FAQs – Little Blue Market</title>');
  assert.equal(plain.title, 'FAQs');
  assert.equal(plain.imageUrl, '');
});

test('only the store\'s own pages can be posted', () => {
  const ok = validateStorePage({ url: `${STORE_SITE}/pages/about`, title: 'About us' });
  assert.equal(ok.url, `${STORE_SITE}/pages/about`);
  assert.throws(() => validateStorePage({ url: 'https://example.com/pages/about', title: 'x' }), /Only pages on/);
  assert.throws(() => validateStorePage({ url: `${STORE_SITE}/products/mug`, title: 'x' }), /Pick one of/);
  assert.throws(() => validateStorePage({ url: `${STORE_SITE}/pages/about`, title: '' }), /title/);
  assert.throws(
    () => validateStorePage({ url: `${STORE_SITE}/pages/about`, title: 'x', imageUrl: 'http://a/b.jpg' }),
    /https/,
  );
});
