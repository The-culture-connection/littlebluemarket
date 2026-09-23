import { strict as assert } from 'node:assert';
import { test } from 'node:test';

import { bumpCounterFloored, counterDelta } from '../src/counters.ts';

/**
 * A count of things that exist cannot be negative, and one that is stays
 * that way: nothing pushes it back up but the things themselves.
 *
 * 2026-09-24, production: a repair deleted 263 posts written before
 * `postCount` existed, so the count went 0 → -263 and a real profile read
 * "-263 Posts".
 */

/** The smallest thing that behaves like the bits of Firestore used here. */
function fakeDoc(start: Record<string, unknown> | null) {
  let data = start;
  const ref: Record<string, unknown> = {
    id: 'u1',
    async update(patch: Record<string, unknown>) {
      if (!data) {
        const error = new Error('NOT_FOUND') as Error & { code: number };
        error.code = 5;
        throw error;
      }
      data = { ...data, ...patch };
    },
  };
  ref.firestore = {
    async runTransaction(body: (tx: unknown) => Promise<void>) {
      const tx = {
        async get() {
          return {
            exists: data !== null,
            get: (field: string) => data?.[field],
          };
        },
        update(_ref: unknown, patch: Record<string, unknown>) {
          data = { ...(data ?? {}), ...patch };
        },
      };
      await body(tx);
    },
  };
  return { ref, read: () => data };
}

void test('a decrement stops at zero instead of going under', async () => {
  const doc = fakeDoc({ postCount: 0 });
  await bumpCounterFloored(doc.ref as never, 'postCount', -1);
  assert.equal(doc.read()!.postCount, 0);
});

void test('the exact shape of the bug: many deletes from zero', async () => {
  const doc = fakeDoc({ postCount: 0 });
  for (let i = 0; i < 263; i++) {
    await bumpCounterFloored(doc.ref as never, 'postCount', -1);
  }
  assert.equal(doc.read()!.postCount, 0, 'never -263');
});

void test('an ordinary decrement still counts down', async () => {
  const doc = fakeDoc({ postCount: 3 });
  await bumpCounterFloored(doc.ref as never, 'postCount', -1);
  assert.equal(doc.read()!.postCount, 2);
});

void test('a decrement past zero lands on zero, not on the remainder', async () => {
  const doc = fakeDoc({ postCount: 2 });
  await bumpCounterFloored(doc.ref as never, 'postCount', -5);
  assert.equal(doc.read()!.postCount, 0);
});

void test('a missing count is treated as zero, not as NaN', async () => {
  const doc = fakeDoc({ name: 'someone' });
  await bumpCounterFloored(doc.ref as never, 'postCount', -1);
  assert.equal(doc.read()!.postCount, 0);
});

void test('a document that is gone is nothing to count', async () => {
  const doc = fakeDoc(null);
  await bumpCounterFloored(doc.ref as never, 'postCount', -1);
  assert.equal(doc.read(), null);
});

void test('zero does nothing at all', async () => {
  const doc = fakeDoc({ postCount: 4 });
  await bumpCounterFloored(doc.ref as never, 'postCount', 0);
  assert.equal(doc.read()!.postCount, 4);
});

void test('the delta a write produces is unchanged', () => {
  assert.equal(counterDelta(false, true), 1);
  assert.equal(counterDelta(true, false), -1);
  assert.equal(counterDelta(true, true), 0);
});
