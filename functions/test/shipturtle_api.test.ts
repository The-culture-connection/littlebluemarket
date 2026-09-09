import { strict as assert } from 'node:assert';
import { test } from 'node:test';

import { authHeaders, extractVendorUsers } from '../src/shipturtle_api.ts';

/**
 * The roster parser, against the shapes an API like Shipturtle's plausibly
 * returns. The real shape is recorded by the probe; these make sure a
 * reasonable variety does not silently produce an empty roster.
 */

test('a flat list of vendors with emails', () => {
  const users = extractVendorUsers({
    data: [
      { id: 1092484, company_id: 1092484, name: 'Grace', email: 'Grace-S@Example.com' },
      { id: 2, company_id: 2, name: 'Gwynstone', email: 'g@example.com' },
    ],
  });
  assert.deepEqual(users, [
    { companyId: '1092484', email: 'grace-s@example.com', name: 'Grace' },
    { companyId: '2', email: 'g@example.com', name: 'Gwynstone' },
  ]);
});

test('vendors with nested user logins', () => {
  const users = extractVendorUsers({
    vendors: [
      {
        vendor_id: 7,
        company_name: 'Femme & Fawn',
        users: [{ email: 'a@x.com', name: 'A' }, { email: 'b@x.com', name: 'B' }],
      },
    ],
  });
  assert.deepEqual(
    users.map((u) => [u.companyId, u.email]),
    [
      ['7', 'a@x.com'],
      ['7', 'b@x.com'],
    ],
  );
});

test('a bare array, and entries without an email are dropped', () => {
  const users = extractVendorUsers([
    { company_id: 1, email: 'one@x.com' },
    { company_id: 2 },
    { email: 'orphan@x.com' },
  ]);
  assert.deepEqual(users.map((u) => u.companyId), ['1']);
});

test('garbage yields an empty roster, never a throw', () => {
  assert.deepEqual(extractVendorUsers(null), []);
  assert.deepEqual(extractVendorUsers('nope'), []);
  assert.deepEqual(extractVendorUsers({ message: 'Unauthenticated.' }), []);
});

test('auth header styles', () => {
  assert.deepEqual(authHeaders('t', 'Authorization'), { Authorization: 'Bearer t' });
  assert.deepEqual(authHeaders('t', 'x-api-key'), { 'x-api-key': 't' });
  assert.deepEqual(authHeaders('t', 'access-token'), { 'access-token': 't' });
});

/**
 * The roster rebuilt from products + company records (the real account's
 * /users endpoint does not answer). A fake fetch plays Shipturtle.
 */
test('rosterFromCompanies: products give the companies, company records give the emails', async () => {
  process.env.SHIPTURTLE_API_KEY = 'test-key';
  const calls = [];
  const fakeFetch = async (url, init) => {
    calls.push(String(url));
    const u = String(url);
    if (u.endsWith('/api/v3/fetch-product-data/parent')) {
      const { start } = JSON.parse(init.body);
      const data = start === 0
        ? [
            { company_id: 101, vendor: 'Femme & Fawn' },
            { company_id: 101, vendor: 'Femme & Fawn' },
            { company_id: 202, vendor: 'Gwynstone' },
            { company_id: 999, vendor: 'Little Blue Market' },
          ]
        : [];
      return new Response(JSON.stringify({ data }), { status: 200 });
    }
    const m = u.match(/\/api\/v1\/companies\/(\d+)$/);
    if (m) {
      const byId = {
        '101': { brand_name: 'Femme & Fawn', email: 'A@x.com, b@x.com' },
        '202': { company_name: 'Gwynstone', email: 'g@example.com' },
        '999': { brand_name: 'Little Blue Market', email: 'kate@lbc.com' },
      };
      return new Response(JSON.stringify({ data: byId[m[1]] }), { status: 200 });
    }
    return new Response('nope', { status: 404 });
  };
  const { rosterFromCompanies } = await import('../src/shipturtle_api.ts');
  const result = await rosterFromCompanies(fakeFetch, { excludeCompanyId: '999', concurrency: 2 });
  assert.equal(result.complete, true);
  assert.equal(result.pages, 1);
  assert.equal(result.nextStart, 0, 'a finished pass starts over next time');
  assert.equal(result.companies, 2, 'the merchant company itself is left out');
  assert.deepEqual(
    result.users.map((u) => [u.companyId, u.email, u.name]).sort(),
    [
      ['101', 'a@x.com', 'Femme & Fawn'],
      ['101', 'b@x.com', 'Femme & Fawn'],
      ['202', 'g@example.com', 'Gwynstone'],
    ],
  );
  assert.ok(!calls.some((c) => c.includes('/companies/999')), 'no lookup for the excluded company');
});

test('rosterFromCompanies: a company that does not answer is skipped and the result is marked incomplete', async () => {
  process.env.SHIPTURTLE_API_KEY = 'test-key';
  const fakeFetch = async (url, init) => {
    const u = String(url);
    if (u.endsWith('/api/v3/fetch-product-data/parent')) {
      const { start } = JSON.parse(init.body);
      return new Response(JSON.stringify({ data: start === 0 ? [{ company_id: 1, vendor: 'One' }, { company_id: 2, vendor: 'Two' }] : [] }), { status: 200 });
    }
    if (u.endsWith('/companies/1')) return new Response(JSON.stringify({ data: { brand_name: 'One', email: 'one@x.com' } }), { status: 200 });
    return new Response('boom', { status: 500 });
  };
  const { rosterFromCompanies } = await import('../src/shipturtle_api.ts');
  const result = await rosterFromCompanies(fakeFetch, { concurrency: 1 });
  assert.equal(result.complete, false);
  assert.deepEqual(result.users.map((u) => u.email), ['one@x.com']);
});

test('rosterFromCompanies: continues from a cursor and keeps what was already known', async () => {
  process.env.SHIPTURTLE_API_KEY = 'test-key';
  const requested = [];
  const fakeFetch = async (url, init) => {
    const u = String(url);
    if (u.endsWith('/api/v3/fetch-product-data/parent')) {
      const { start, length } = JSON.parse(init.body);
      requested.push(start);
      // Two full pages then a short one: products 0..length*2+1.
      const data = start < length * 2 ? Array.from({ length }, (_, i) => ({ company_id: start === 0 ? 11 : 22, vendor: 'V' + (start + i) })) : [{ company_id: 33, vendor: 'Last' }];
      return new Response(JSON.stringify({ data }), { status: 200 });
    }
    const m = u.match(/\/companies\/(\d+)$/);
    if (m) return new Response(JSON.stringify({ data: { brand_name: 'C' + m[1], email: 'c' + m[1] + '@x.com' } }), { status: 200 });
    return new Response('nope', { status: 404 });
  };
  const { rosterFromCompanies, PRODUCT_PAGE } = await import('../src/shipturtle_api.ts');
  // A previous run already knows company 11 and stopped after the first page.
  const known = [{ companyId: '11', email: 'c11@x.com', name: 'C11' }];
  const result = await rosterFromCompanies(fakeFetch, { startAt: PRODUCT_PAGE, known, concurrency: 2 });
  assert.deepEqual(requested, [PRODUCT_PAGE, PRODUCT_PAGE * 2], 'starts at the cursor, not at zero');
  assert.equal(result.complete, true);
  assert.deepEqual(result.users.map((u) => u.companyId).sort(), ['11', '22', '33'], 'known plus the new companies');
  assert.equal(result.companies, 2, 'only the new companies were looked up');
});

test('rosterFromCompanies: stops before a page it has no time for and reports where to continue', async () => {
  process.env.SHIPTURTLE_API_KEY = 'test-key';
  let calls = 0;
  const fakeFetch = async () => { calls++; return new Response(JSON.stringify({ data: [] }), { status: 200 }); };
  const { rosterFromCompanies } = await import('../src/shipturtle_api.ts');
  const result = await rosterFromCompanies(fakeFetch, { budgetMs: 1000, startAt: 1500 });
  assert.equal(calls, 0, 'a 120 s page does not fit a 1 s budget');
  assert.equal(result.complete, false);
  assert.equal(result.nextStart, 1500);
});
