import { strict as assert } from 'node:assert';
import { test } from 'node:test';

import {
  basicAuth,
  decodeEntities,
  isLiveWpHost,
  listingFromWp,
  orderFromWc,
  pickWpUser,
  wpFetch,
  wpUrl,
  type WpCredentials,
} from '../src/wordpress.ts';

const BASE = 'https://wordpress-1234.cloudwaysapps.com';
const CREDS: WpCredentials = {
  appUser: 'grace',
  appPassword: 'abcd efgh ijkl mnop',
  wcKey: 'ck_test',
  wcSecret: 'cs_test',
};

/**
 * One directory listing exactly as the live site returned it on 2026-09-08
 * (`GET /wp-json/wp/v2/vendors_dir_ltg`, no credential), with the contact
 * details replaced. The `drts_fields` layout is the point of the fixture.
 */
const LISTING = {
  id: 47494,
  date: '2026-09-04T23:39:37',
  modified: '2026-09-04T23:39:37',
  modified_gmt: '2026-09-05T03:39:37',
  slug: 'field-trips-travel-vacations',
  status: 'publish',
  type: 'vendors_dir_ltg',
  link: 'https://littlebluecart.com/directory-vendors/listing/field-trips-travel-vacations/',
  title: { rendered: 'Field Trips Travel &amp; Vacations' },
  author: 6415,
  featured_media: 47490,
  vendors_dir_cat: [725],
  vendors_dir_tag: [652],
  vendors_loc_loc: [833],
  drts_fields: {
    field_phone: ['555-0100'],
    field_email: ['Owner@Example.test'],
    field_website: ['https://www.example.test/advisor/erica'],
    location_address: [
      {
        address: '', street: '', street2: '', city: '', province: '', zip: '', country: '',
        timezone: '', zoom: 10, lat: 0, lng: 0, term_id: 833, display_address: '*Online/Virtual Business',
      },
    ],
    payment_plan: { plan_id: 26361, plan_name: 'DIRECTORY SHOWCASE PLAN', active: true },
    field_little_blue_market_store_link: [],
    field_business_owners_address: [
      {
        address: '', street: '1851 Massachusetts Ave NE', street2: '', city: 'St. Petersburg', province: 'FL',
        zip: '33703', country: '', timezone: 'America/New_York', zoom: 10, lat: 0, lng: 0, term_id: 0,
        display_address: '1851 Massachusetts Ave NE, St. Petersburg, FL 33703',
      },
    ],
  },
};

test('wpUrl joins base, wp-json and the path, and skips undefined query values', () => {
  const url = wpUrl(`${BASE}/`, '/wp/v2/users', { search: 'a+b@x.test', context: 'edit', page: undefined, per_page: 100 });
  assert.equal(url, `${BASE}/wp-json/wp/v2/users?search=a%2Bb%40x.test&context=edit&per_page=100`);
});

test('basicAuth is the standard header and the live host is recognised in every spelling', () => {
  assert.equal(basicAuth('u', 'p'), `Basic ${Buffer.from('u:p').toString('base64')}`);
  assert.equal(isLiveWpHost('littlebluecart.com'), true);
  assert.equal(isLiveWpHost('www.littlebluecart.com'), true);
  assert.equal(isLiveWpHost('staging.littlebluecart.com'), true);
  assert.equal(isLiveWpHost('wordpress-1234.cloudwaysapps.com'), false);
});

test('pickWpUser wants exactly one member with exactly that email', () => {
  const page = [
    { id: 1, email: 'Grace@Example.test', slug: 'grace', name: 'Grace', roles: ['administrator'] },
    { id: 2, email: 'grace.other@example.test', slug: 'grace2', name: 'Also Grace', roles: ['subscriber'] },
  ];
  const user = pickWpUser(page, 'grace@example.test');
  assert.deepEqual(user, { id: 1, email: 'grace@example.test', slug: 'grace', name: 'Grace', roles: ['administrator'] });
  // A loose search hit on the display name is not a match.
  assert.equal(pickWpUser(page, 'nobody@example.test'), null);
  // Two members on one email: link neither.
  assert.equal(pickWpUser([...page, { id: 3, email: 'grace@example.test' }], 'grace@example.test'), null);
  assert.equal(pickWpUser({ not: 'an array' }, 'grace@example.test'), null);
});

test('listingFromWp reads the recorded Directories Pro shape', () => {
  const l = listingFromWp(LISTING);
  assert.ok(l);
  assert.equal(l.wpPostId, 47494);
  assert.equal(l.wpAuthorId, 6415);
  assert.equal(l.status, 'publish');
  assert.equal(l.title, 'Field Trips Travel & Vacations');
  assert.equal(l.website, 'https://www.example.test/advisor/erica');
  assert.equal(l.email, 'owner@example.test');
  assert.equal(l.phone, '555-0100');
  assert.equal(l.storeLink, '');
  assert.equal(l.locationLabel, '*Online/Virtual Business');
  assert.deepEqual(l.businessAddress, {
    street: '1851 Massachusetts Ave NE',
    city: 'St. Petersburg',
    state: 'FL',
    zip: '33703',
    display: '1851 Massachusetts Ave NE, St. Petersburg, FL 33703',
  });
  assert.equal(l.plan, 'DIRECTORY SHOWCASE PLAN');
  assert.equal(l.planId, 26361);
  assert.deepEqual(l.categoryIds, [725]);
  assert.deepEqual(l.tagIds, [652]);
  assert.deepEqual(l.locationIds, [833]);
  assert.equal(l.featuredMediaId, 47490);
  assert.equal(l.modified, '2026-09-05T03:39:37');
});

test('listingFromWp survives a plan that omits fields, and rejects a shape without an id', () => {
  const l = listingFromWp({ id: 9, author: 2, title: 'Plain', status: 'pending', drts_fields: { payment_plan: [{ plan_id: 1, plan_name: 'FREE' }] } });
  assert.ok(l);
  assert.equal(l.title, 'Plain');
  assert.equal(l.status, 'pending');
  assert.equal(l.website, '');
  assert.equal(l.businessAddress, null);
  assert.equal(l.plan, 'FREE');
  assert.equal(listingFromWp({ title: 'no id' }), null);
  assert.equal(listingFromWp(null), null);
});

test('decodeEntities handles the entities WordPress actually emits', () => {
  assert.equal(decodeEntities('Tom &amp; Jerry&#8217;s &#8220;Shop&#8221; &hellip;'), 'Tom & Jerry’s “Shop” …');
});

test('orderFromWc turns a WooCommerce order into integer cents', () => {
  const o = orderFromWc(
    {
      id: 88, number: '1088', status: 'completed', date_created_gmt: '2026-09-01T12:00:00', total: '45.00', currency: 'USD',
      customer_id: 6415, billing: { email: 'Buyer@Example.test' },
      line_items: [{ id: 1, name: 'Tax the Rich Hoodie', quantity: 1, total: '40.00', product_id: 32452 }, { id: 2, name: 'Sticker', quantity: 2, total: '5.00', product_id: 0 }],
    },
    `${BASE}/`,
  );
  assert.ok(o);
  assert.equal(o.totalCents, 4500);
  assert.equal(o.billingEmail, 'buyer@example.test');
  assert.equal(o.items.length, 2);
  assert.equal(o.items[0]!.totalCents, 4000);
  assert.equal(o.items[1]!.productId, null);
  assert.equal(o.viewUrl, `${BASE}/my-account/view-order/88/`);
});

function fakeFetch(responses: Array<{ status: number; body: unknown; total?: number }>) {
  const seen: Array<{ url: string; authorization: string | undefined }> = [];
  const impl = (async (input: string | URL | Request, init?: RequestInit) => {
    const next = responses.shift();
    if (!next) throw new Error('fakeFetch: no more responses');
    const headers = (init?.headers ?? {}) as Record<string, string>;
    seen.push({ url: String(input), authorization: headers.authorization });
    const h = new Headers();
    if (next.total !== undefined) h.set('x-wp-total', String(next.total));
    return new Response(typeof next.body === 'string' ? next.body : JSON.stringify(next.body), { status: next.status, headers: h });
  }) as unknown as typeof fetch;
  return { impl, seen };
}

test('wpFetch sends Basic auth for the app credential, reads X-WP-Total, and retries a 503', async () => {
  const { impl, seen } = fakeFetch([
    { status: 503, body: '<html>maintenance</html>' },
    { status: 200, body: [{ id: 1 }], total: 1733 },
  ]);
  const page = await wpFetch<unknown[]>('wp/v2/vendors_dir_ltg', { auth: 'app', base: BASE, query: { per_page: 1 }, fetchImpl: impl, delaysMs: [0, 0] }, CREDS);
  assert.deepEqual(page.data, [{ id: 1 }]);
  assert.equal(page.total, 1733);
  assert.equal(seen.length, 2);
  assert.equal(seen[0]!.authorization, basicAuth('grace', 'abcd efgh ijkl mnop'));
});

test('wpFetch does not retry a 401, quotes WordPress\'s reason, and never the credential', async () => {
  const { impl, seen } = fakeFetch([
    { status: 401, body: { code: 'rest_not_logged_in', message: 'You are not currently logged in.' } },
    { status: 200, body: [] },
  ]);
  await assert.rejects(
    wpFetch('wp/v2/users/me', { auth: 'app', base: BASE, fetchImpl: impl, delaysMs: [0, 0] }, CREDS),
    (error: Error) => {
      assert.match(error.message, /^WP 401 wp\/v2\/users\/me: rest_not_logged_in You are not currently logged in\./);
      assert.doesNotMatch(error.message, /abcd|Basic /);
      return true;
    },
  );
  assert.equal(seen.length, 1);
});

test('wpFetch refuses to run without a base or without the credential it needs', async () => {
  const { impl } = fakeFetch([]);
  await assert.rejects(wpFetch('wp/v2/users', { base: '', fetchImpl: impl }, CREDS), /WP_BASE_URL is empty/);
  await assert.rejects(wpFetch('wc/v3/orders', { auth: 'wc', base: BASE, fetchImpl: impl }, { ...CREDS, wcKey: '' }), /WC_CONSUMER_KEY/);
  await assert.rejects(wpFetch('wp/v2/users', { auth: 'app', base: BASE, fetchImpl: impl }, { ...CREDS, appPassword: '' }), /WP_APP_PASSWORD is empty/);
});
