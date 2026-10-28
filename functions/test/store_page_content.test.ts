import { strict as assert } from 'node:assert';
import { test } from 'node:test';

import { absoluteUrl, pageBlocks } from '../src/store_page_content.ts';

// Grace, 2026-10-28 (QA suite): "I wanted the pages to be posted and able to
// be opened natively in the app". The shapes below are cut down from the
// store's own About, Shopper FAQ, gift guide and refund policy pages.

const SITE = 'https://littlebluemarket.com';

const page = (main: string) => `<!doctype html><html><head>
  <title>About – Little Blue Market</title><script>var theme = {};</script>
</head><body>
  <a class="skip-to-content-link button visually-hidden" href="#MainContent">Skip to content</a>
  <header><nav><a href="/">Home</a><a href="/collections/all">Shop</a></nav></header>
  <main id="MainContent" class="content-for-layout" role="main">${main}</main>
  <footer><p>© 2026 Little Blue Market</p></footer>
</body></html>`;

test('only the main area is read, in order, and the theme is left behind', () => {
  const blocks = pageBlocks(
    page(`
      <div class="image-with-text">
        <img src="//littlebluemarket.com/cdn/shop/files/Hero.png?v=1&width=360" width="1500" alt="">
        <div class="image-with-text__text typeset rte">
          <h2>Our <em>Mission</em></h2>
          <p>Little Blue Market exists to   empower
             conscious shoppers.</p>
          <ul><li>Shop confidently</li><li><p>Support makers</p></li></ul>
        </div>
      </div>
      <script>window.track()</script>
      <form action="/contact"><p>Your email</p><input name="email"></form>
      <span class="visually-hidden">Opens in a new window</span>
      <p aria-hidden="true">Decoration</p>
    `),
    SITE,
  );
  assert.deepEqual(blocks, [
    { kind: 'image', url: 'https://littlebluemarket.com/cdn/shop/files/Hero.png?v=1&width=1200' },
    { kind: 'heading', text: 'Our Mission' },
    { kind: 'text', text: 'Little Blue Market exists to empower conscious shoppers.' },
    { kind: 'bullet', text: 'Shop confidently' },
    { kind: 'bullet', text: 'Support makers' },
  ]);
});

test('a button keeps its words and where it goes', () => {
  const blocks = pageBlocks(
    page(`<h2>Custom gifts</h2><p>Made by hand.</p>
      <a class="btn btn--primary" href="/collections/custom-personalized-gifts">Shop <b>Personalized</b> Gifts</a>`),
    SITE,
  );
  assert.deepEqual(blocks.at(-1), {
    kind: 'button',
    label: 'Shop Personalized Gifts',
    url: 'https://littlebluemarket.com/collections/custom-personalized-gifts',
  });
});

test('a tile that is all one link keeps the link on its picture and its heading', () => {
  const blocks = pageBlocks(
    page(`<a href="/collections/for-the-book-lover" class="collection-card">
        <img src="//littlebluemarket.com/cdn/shop/collections/books.jpg" alt="">
        <h3>For the Book Lover</h3>
      </a>
      <p>Read the <a href="/pages/track-your-order">Track Your Order</a> page.</p>`),
    SITE,
  );
  const link = 'https://littlebluemarket.com/collections/for-the-book-lover';
  assert.deepEqual(blocks[0], {
    kind: 'image',
    url: 'https://littlebluemarket.com/cdn/shop/collections/books.jpg?width=1200',
    link,
  });
  assert.deepEqual(blocks[1], { kind: 'heading', text: 'For the Book Lover', link });
  // A link inside a sentence is words, and does not split the sentence.
  assert.deepEqual(blocks[2], { kind: 'text', text: 'Read the Track Your Order page.' });
});

test('words written twice for two screen sizes are kept once, the same picture too', () => {
  const blocks = pageBlocks(
    page(`<p>Welcome!</p><p>Welcome!</p>
      <img src="//littlebluemarket.com/cdn/a.jpg?width=300"><img src="//littlebluemarket.com/cdn/a.jpg?width=900">`),
    SITE,
  );
  assert.equal(blocks.filter((b) => b.kind === 'text').length, 1);
  assert.equal(blocks.filter((b) => b.kind === 'image').length, 1);
});

test('a heading over nothing the app can draw is dropped', () => {
  // The Track Your Order page: a heading over a lookup form.
  const blocks = pageBlocks(page(`<h1>Track your order</h1><form><input name="order"></form>`), SITE);
  assert.deepEqual(blocks, []);
});

test('icons, data pictures and tiny thumbnails are not pictures to read', () => {
  const blocks = pageBlocks(
    page(`<img src="/cdn/icon.svg"><img src="data:image/png;base64,AAAA"><img src="/cdn/dot.png" width="24"><p>Words</p>`),
    SITE,
  );
  assert.deepEqual(blocks, [{ kind: 'text', text: 'Words' }]);
});

test('a page with no main area reads as nothing, which opens the web page', () => {
  assert.deepEqual(pageBlocks('<html><body><p>Hello</p></body></html>', SITE), []);
});

test('addresses are made whole and https, and the ones that go nowhere are dropped', () => {
  assert.equal(absoluteUrl('/pages/about', SITE), 'https://littlebluemarket.com/pages/about');
  assert.equal(absoluteUrl('//cdn.shopify.com/a.jpg', SITE), 'https://cdn.shopify.com/a.jpg');
  assert.equal(absoluteUrl('http://example.com/x', SITE), 'https://example.com/x');
  assert.equal(absoluteUrl('#top', SITE), '');
  assert.equal(absoluteUrl('mailto:hello@littlebluecart.com', SITE), '');
  assert.equal(absoluteUrl('javascript:void(0)', SITE), '');
});
