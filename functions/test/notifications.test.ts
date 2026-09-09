import { strict as assert } from 'node:assert';
import { test } from 'node:test';

import { FAN_OUT_CHUNK, notifyMany } from '../src/notifications.ts';

const input = { type: 'newPost' as const, fromUid: 'author', text: 'hello' };

test('every recipient is reached, in chunks, and one failure does not stop the rest', async () => {
  const uids = Array.from({ length: FAN_OUT_CHUNK * 2 + 3 }, (_, i) => `u${i}`);
  const reached: string[] = [];
  let inFlight = 0;
  let peak = 0;

  const result = await notifyMany(uids, input, async (uid) => {
    inFlight++;
    peak = Math.max(peak, inFlight);
    await new Promise((r) => setTimeout(r, 1));
    inFlight--;
    if (uid === 'u7') throw new Error('token gone');
    reached.push(uid);
  });

  assert.equal(reached.length, uids.length - 1);
  assert.ok(!reached.includes('u7'));
  assert.deepEqual(result, { sent: uids.length - 1, failed: 1 });
  // Parallel inside a chunk, never more than a chunk at once.
  assert.ok(peak > 1, 'sends inside a chunk overlap');
  assert.ok(peak <= FAN_OUT_CHUNK, `at most ${FAN_OUT_CHUNK} in flight, saw ${peak}`);
});

test('nobody to tell is a no-op', async () => {
  let calls = 0;
  const result = await notifyMany([], input, async () => {
    calls++;
  });
  assert.equal(calls, 0);
  assert.deepEqual(result, { sent: 0, failed: 0 });
});
