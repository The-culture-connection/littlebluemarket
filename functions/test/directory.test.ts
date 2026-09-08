import { strict as assert } from 'node:assert';
import { test } from 'node:test';

import { Timestamp } from 'firebase-admin/firestore';

import {
  AUTO_MIN_AGE_MS,
  INDEX_DELTA_MIN_AGE_MS,
  INDEX_FULL_TTL_MS,
  MANUAL_MIN_AGE_MS,
  NOT_FOUND_RECHECK_MS,
  directoryPostFor,
  indexRefreshKind,
  listingIdsOf,
  listingMirrorDoc,
  mergeIndex,
  mergeOrders,
  reuseStored,
  termIdsNeeded,
  wcTimestamp,
} from '../src/directory.ts';
import { indexEntriesFromWp, isSiteFallbackImage, listingFromWp } from '../src/wordpress.ts';
import type { DirectoryListingRecord, WcOrderRecord } from '../src/wordpress.ts';

test('the owner index is built from listing pages, folded by id, and answers "whose listings"', () => {
  const rows = indexEntriesFromWp([
    { id: 47516, author: 6371, modified_gmt: '2026-09-08T19:51:18', status: 'publish' },
    { id: 47494, author: 6415, modified_gmt: '2026-09-05T03:39:37', status: 'publish' },
    { id: 47509, author: 6466, modified_gmt: '2026-09-07T10:00:00', status: 'pending' },
    { id: 'junk' },
  ]);
  assert.equal(rows.length, 3);
  let index = mergeIndex({}, rows);
  // A delta that moves a listing to a new owner and adds one wins over the old row.
  index = mergeIndex(index, indexEntriesFromWp([{ id: 47494, author: 6371, modified_gmt: '2026-09-08T20:00:00', status: 'publish' }, { id: 47600, author: 6371, modified_gmt: '2026-09-08T20:01:00', status: 'draft' }]));
  assert.deepEqual(listingIdsOf(index, 6371).sort(), [47494, 47516, 47600]);
  assert.deepEqual(listingIdsOf(index, 6415), []);
});

test('the index is rebuilt every six hours, topped up every ten minutes, and reused between', () => {
  const now = Date.parse('2026-09-08T12:00:00Z');
  assert.equal(indexRefreshKind(undefined, now), 'full');
  assert.equal(indexRefreshKind({ fullAt: now - INDEX_FULL_TTL_MS - 1, updatedAt: now }, now), 'full');
  assert.equal(indexRefreshKind({ fullAt: now - 3_600_000, updatedAt: now - INDEX_DELTA_MIN_AGE_MS - 1 }, now), 'delta');
  assert.equal(indexRefreshKind({ fullAt: now - 3_600_000, updatedAt: now - 60_000 }, now), 'none');
});

test('the description comes from the SEO field and the site logo is never a listing photo', () => {
  const l = listingFromWp({
    id: 47516, author: 6371, status: 'publish', title: { rendered: 'FoundHouse' }, featured_media: 0,
    yoast_head_json: { og_description: 'Develop your business website with FoundHouse', og_image: [{ url: 'https://littlebluecart.com/wp-content/uploads/2025/09/Little-Blue-Cart-Header-Logo-1.png' }] },
  });
  assert.ok(l);
  assert.equal(l.description, 'Develop your business website with FoundHouse');
  assert.equal(l.ogImageUrl, '');
  assert.equal(isSiteFallbackImage('https://littlebluecart.com/wp-content/uploads/2026/09/IMG_1063.webp'), false);
  const withPhoto = listingFromWp({ id: 1, author: 2, yoast_head_json: { og_image: [{ url: 'https://littlebluecart.com/wp-content/uploads/2026/09/IMG_1063.webp' }] } });
  assert.equal(withPhoto?.ogImageUrl, 'https://littlebluecart.com/wp-content/uploads/2026/09/IMG_1063.webp');
});

const NOW = Date.parse('2026-09-08T12:00:00Z');
const at = (msAgo: number) => Timestamp.fromMillis(NOW - msAgo);

function order(id: number, createdAt: string, billingEmail: string): WcOrderRecord {
  return {
    id, number: String(1000 + id), status: 'completed', createdAt, totalCents: 100, currency: 'USD',
    billingEmail, customerId: 0, items: [], viewUrl: '',
  };
}

test('a fresh linked answer is reused: ten minutes for a tap, six hours for the silent call', () => {
  const doc = { status: 'linked', wpLogin: 'grace', orderCount: 3, listingCount: 1, refreshedAt: at(60_000) };
  const tapped = reuseStored(doc, { auto: false, now: NOW });
  assert.equal(tapped?.status, 'alreadyLinked');
  assert.equal(tapped?.orders, 3);
  assert.match(tapped?.note ?? '', /few minutes/);
  const silent = reuseStored(doc, { auto: true, now: NOW });
  assert.equal(silent?.status, 'alreadyLinked');
  assert.equal(silent?.note, undefined);

  const older = { ...doc, refreshedAt: at(MANUAL_MIN_AGE_MS + 1) };
  assert.equal(reuseStored(older, { auto: false, now: NOW }), null);
  assert.equal(reuseStored(older, { auto: true, now: NOW })?.status, 'alreadyLinked');
  assert.equal(reuseStored({ ...doc, refreshedAt: at(AUTO_MIN_AGE_MS + 1) }, { auto: true, now: NOW }), null);
});

test('a stored "not found" is reused by the silent call for a week, never by a tap', () => {
  const doc = { status: 'notFound', checkedAt: at(86_400_000) };
  assert.equal(reuseStored(doc, { auto: true, now: NOW })?.status, 'notFound');
  assert.equal(reuseStored(doc, { auto: false, now: NOW }), null);
  assert.equal(reuseStored({ status: 'notFound', checkedAt: at(NOT_FOUND_RECHECK_MS + 1) }, { auto: true, now: NOW }), null);
  assert.equal(reuseStored(undefined, { auto: true, now: NOW }), null);
  assert.equal(reuseStored({}, { auto: true, now: NOW }), null);
});

test('mergeOrders keeps the customer\'s orders, adds exact-email guest orders, dedupes, newest first', () => {
  const byCustomer = [order(1, '2026-01-01T00:00:00', 'grace@example.test'), order(2, '2026-03-01T00:00:00', 'other@example.test')];
  const byEmail = [
    order(2, '2026-03-01T00:00:00', 'grace@example.test'),
    order(3, '2026-02-01T00:00:00', 'grace@example.test'),
    // A loose search hit on a note or a name, not this person's order.
    order(4, '2026-04-01T00:00:00', 'someone.else@example.test'),
  ];
  const merged = mergeOrders(byCustomer, byEmail, 'grace@example.test');
  assert.deepEqual(merged.map((o) => o.id), [2, 3, 1]);
});

const RECORD: DirectoryListingRecord = {
  wpPostId: 47494, slug: 'field-trips', status: 'publish', link: 'https://example.test/listing/field-trips/',
  title: 'Field Trips Travel & Vacations', wpAuthorId: 6415, featuredMediaId: 47490,
  categoryIds: [725, 999], tagIds: [652], locationIds: [833],
  website: 'https://www.example.test', email: 'owner@example.test', phone: '555-0100', storeLink: '',
  locationLabel: '*Online/Virtual Business',
  businessAddress: { street: '1851 Massachusetts Ave NE', city: 'St. Petersburg', state: 'FL', zip: '33703', display: '1851 Massachusetts Ave NE, St. Petersburg, FL 33703' },
  plan: 'DIRECTORY SHOWCASE PLAN', planId: 26361, modified: '2026-09-05T03:39:37',
  description: 'World traveler, points and miles pro.', ogImageUrl: '',
};

test('listingMirrorDoc names the terms it knows and drops the ids it does not', () => {
  const doc = listingMirrorDoc(RECORD, 'uid-1', {
    vendors_dir_cat: { '725': 'Travel' },
    vendors_dir_tag: { '652': 'Woman-Owned' },
    vendors_loc_loc: { '833': 'Online/Virtual' },
  }, 'https://cdn.example.test/img.webp');
  assert.equal(doc.ownerUid, 'uid-1');
  assert.equal(doc.wpUserId, 6415);
  assert.equal(doc.status, 'publish');
  assert.deepEqual(doc.categories, ['Travel']);
  assert.deepEqual(doc.tags, ['Woman-Owned']);
  assert.deepEqual(doc.locations, ['Online/Virtual']);
  assert.equal(doc.state, 'FL');
  assert.equal(doc.address, '1851 Massachusetts Ave NE, St. Petersburg, FL 33703');
  assert.equal(doc.imageUrl, 'https://cdn.example.test/img.webp');
  assert.equal(doc.description, 'World traveler, points and miles pro.');
  assert.equal((doc.updatedAt as Timestamp).toDate().toISOString(), '2026-09-05T03:39:37.000Z');
  // Never anything the public endpoint did not return.
  assert.ok(!('wpEmailLower' in doc) && !('planId' in doc));
});

test('directoryPostFor posts as the owner, keyed to the listing, with the counters left to the social functions', () => {
  const post = directoryPostFor(RECORD, 'uid-1');
  assert.equal(post.kind, 'directory');
  assert.equal(post.authorId, 'uid-1');
  assert.equal(post.listingId, '47494');
  assert.equal(post.title, 'Field Trips Travel & Vacations');
  assert.equal(post.auto, true);
  assert.deepEqual(post.tags, []);
  // createdAt is the caller's, added only the first time.
  assert.ok(!('createdAt' in post));
});

test('termIdsNeeded collects each taxonomy once across listings', () => {
  const needed = termIdsNeeded([RECORD, { ...RECORD, wpPostId: 2, categoryIds: [725, 1], tagIds: [], locationIds: [] }]);
  assert.deepEqual(needed.vendors_dir_cat, [725, 999, 1]);
  assert.deepEqual(needed.vendors_dir_tag, [652]);
  assert.deepEqual(needed.vendors_loc_loc, [833]);
});

test('WooCommerce GMT dates without a zone marker are read as UTC', () => {
  assert.equal(wcTimestamp('2026-09-01T12:00:00')?.toDate().toISOString(), '2026-09-01T12:00:00.000Z');
  assert.equal(wcTimestamp('2026-09-01T12:00:00Z')?.toDate().toISOString(), '2026-09-01T12:00:00.000Z');
  assert.equal(wcTimestamp(''), null);
  assert.equal(wcTimestamp('not a date'), null);
});
