import { strict as assert } from 'node:assert';
import { test } from 'node:test';

import {
  MISS_TTL_MS,
  forgetVendorCache,
  resolveSellerUid,
} from '../src/vendors.ts';

/**
 * The attribution cache. A miss cached forever is how a seller who has just
 * claimed their shop keeps getting no credit until the instance dies.
 */

test('a line attribute wins without any lookup', async () => {
  let calls = 0;
  const uid = await resolveSellerUid(
    { lineAttribute: 'maya', vendor: 'Gwynstone' },
    async () => {
      calls += 1;
      return 'wrong';
    },
  );
  assert.equal(uid, 'maya');
  assert.equal(calls, 0);
});

test('a hit is cached for the instance', async () => {
  forgetVendorCache();
  let calls = 0;
  const lookup = async () => {
    calls += 1;
    return 'kali';
  };
  assert.equal(await resolveSellerUid({ vendor: 'Gwynstone' }, lookup), 'kali');
  assert.equal(await resolveSellerUid({ vendor: 'Gwynstone' }, lookup), 'kali');
  assert.equal(calls, 1);
});

test('a miss is retried after the short TTL, not cached forever', async () => {
  forgetVendorCache();
  let now = 1_000_000;
  let answer = '';
  let calls = 0;
  const lookup = async () => {
    calls += 1;
    return answer;
  };
  const clock = () => now;

  assert.equal(await resolveSellerUid({ vendor: 'Newshop' }, lookup, clock), '');
  assert.equal(await resolveSellerUid({ vendor: 'Newshop' }, lookup, clock), '');
  assert.equal(calls, 1, 'within the TTL the miss is served from cache');

  // The vendor claims their shop; the next lookup after the TTL must see it.
  answer = 'newuid';
  now += MISS_TTL_MS + 1;
  assert.equal(await resolveSellerUid({ vendor: 'Newshop' }, lookup, clock), 'newuid');
  assert.equal(calls, 2);
});

test('forgetVendorCache drops both hits and misses', async () => {
  forgetVendorCache();
  let calls = 0;
  const lookup = async () => {
    calls += 1;
    return calls === 1 ? '' : 'granted';
  };
  assert.equal(await resolveSellerUid({ vendor: 'X' }, lookup), '');
  forgetVendorCache();
  assert.equal(await resolveSellerUid({ vendor: 'X' }, lookup), 'granted');
});
