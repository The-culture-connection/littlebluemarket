import { strict as assert } from 'node:assert';
import { test } from 'node:test';

import { emailsFrom, lookupVendor, pickCompany } from '../src/vendor_directory.ts';

/**
 * The vendor directory's pure parts, and one lookup against a fake
 * Shipturtle: the filtered product list gives the company, the company
 * record gives the emails.
 */

test('pickCompany: the rows that really carry the vendor decide, case and punctuation aside', () => {
  const rows = [
    { company_id: 101, vendor: 'Femme & Fawn' },
    { company_id: 101, vendor: 'femme and fawn' },
    { company_id: 555, vendor: 'Femme & Fawn Studio' },
  ];
  assert.deepEqual(pickCompany('Femme & Fawn', rows), { companyId: '101' });
  assert.deepEqual(pickCompany('Nobody', rows), { reason: 'not-found' });
  assert.deepEqual(pickCompany('Femme & Fawn', [...rows, { company_id: 102, vendor: 'Femme & Fawn' }]), { reason: 'ambiguous' });
});

test('emailsFrom: one field, several addresses, lower-cased and unique', () => {
  assert.deepEqual(
    emailsFrom({ email: 'Kate@lbc.com, erin@lbc.com;  kate@lbc.com', contact_email: 'ops@lbc.com' }),
    ['kate@lbc.com', 'erin@lbc.com', 'ops@lbc.com'],
  );
  assert.deepEqual(emailsFrom({ email: '' }), []);
});

test('lookupVendor: two calls, one entry', async () => {
  process.env.SHIPTURTLE_API_KEY = 'test-key';
  const calls = [];
  const fakeFetch = async (url, init) => {
    const u = String(url);
    calls.push(u);
    if (u.endsWith('/api/v3/fetch-product-data/parent')) {
      const body = JSON.parse(init.body);
      assert.equal(body.columns[0].search.value, 'Grace Shorter', 'searches the vendor column');
      return new Response(JSON.stringify({ data: [{ company_id: 1092484, vendor: 'Grace Shorter' }, { company_id: 1092484, vendor: 'Grace Shorter' }] }), { status: 200 });
    }
    if (u.endsWith('/api/v1/companies/1092484')) {
      return new Response(JSON.stringify({ data: { brand_name: 'Grace Shorter', email: 'grace-s@example.com' } }), { status: 200 });
    }
    return new Response('nope', { status: 404 });
  };
  const result = await lookupVendor('Grace Shorter', fakeFetch);
  assert.deepEqual(result.entry, {
    vendorKey: 'grace-shorter',
    vendorName: 'Grace Shorter',
    companyId: '1092484',
    brandName: 'Grace Shorter',
    emails: ['grace-s@example.com'],
  });
  assert.equal(calls.length, 2);
});

test('lookupVendor: a vendor with no products in Shipturtle is not-found, a silent API is silent', async () => {
  process.env.SHIPTURTLE_API_KEY = 'test-key';
  const empty = async () => new Response(JSON.stringify({ data: [] }), { status: 200 });
  assert.deepEqual(await lookupVendor('Ghost', empty), { reason: 'not-found' });
  const down = async () => { throw new DOMException('timeout', 'TimeoutError'); };
  assert.deepEqual(await lookupVendor('Ghost', down), { reason: 'silent' });
});
