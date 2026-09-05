import { strict as assert } from 'node:assert';
import { test } from 'node:test';

import { grantDecision } from '../src/roster_grant.ts';

/**
 * When a Shipturtle roster match becomes a seller grant. Every refusal here
 * is a case that would otherwise hand someone the wrong shop.
 */

test('one company, one vendor string, unclaimed: grant as that string', () => {
  assert.deepEqual(
    grantDecision({ uid: 'u1', companyMatches: 1, vendorStrings: ['cc'], reservedBy: null }),
    { grant: true, vendorName: 'cc' },
  );
  // Already reserved by the same account (a re-run) is still a grant.
  assert.deepEqual(
    grantDecision({ uid: 'u1', companyMatches: 1, vendorStrings: ['cc', 'cc '], reservedBy: 'u1' }),
    { grant: true, vendorName: 'cc' },
  );
});

test('an email on two companies is ambiguous, and a claim code decides', () => {
  const d = grantDecision({ uid: 'u1', companyMatches: 2, vendorStrings: ['cc'], reservedBy: null });
  assert.equal(d.grant, false);
  assert.match((d as { reason: string }).reason, /more than one vendor company/);
});

test('a company with no products has no vendor string to grant', () => {
  const d = grantDecision({ uid: 'u1', companyMatches: 1, vendorStrings: [], reservedBy: null });
  assert.equal(d.grant, false);
  assert.match((d as { reason: string }).reason, /no products yet/);
});

test('a vendor string another account holds is never handed over', () => {
  const d = grantDecision({ uid: 'u1', companyMatches: 1, vendorStrings: ['cc'], reservedBy: 'u9' });
  assert.equal(d.grant, false);
  assert.match((d as { reason: string }).reason, /another account/);
});

test('two different vendor strings on one company is refused, not guessed', () => {
  const d = grantDecision({ uid: 'u1', companyMatches: 1, vendorStrings: ['cc', 'CC Studio'], reservedBy: null });
  assert.equal(d.grant, false);
  assert.match((d as { reason: string }).reason, /more than one vendor string/);
});
