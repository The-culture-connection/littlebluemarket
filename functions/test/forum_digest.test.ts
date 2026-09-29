import { strict as assert } from 'node:assert';
import { test } from 'node:test';

import {
  type DigestDeps,
  type DigestEntry,
  digestText,
  planDigest,
  sendDigest,
} from '../src/notifications.ts';
import type { NotificationPrefs } from '../src/push.ts';

/**
 * The forum digest (C2, 2026-09-28): replies in threads you are in are
 * rolled into one push every half hour instead of one push each.
 */

// Detroit, late September: 18:00Z is 2 pm, 02:30Z is 10:30 pm the night before.
const AFTERNOON = new Date('2026-09-28T18:00:00Z');
const NIGHT = new Date('2026-09-29T02:30:00Z');

/** A stand-in for Firestore and FCM that remembers what was asked of it. */
function fakes(prefs: NotificationPrefs | undefined = undefined) {
  const pushed: { uid: string; title: string; body: string; route: string }[] = [];
  const cleared: string[][] = [];
  const marked: Date[] = [];
  const deps: DigestDeps = {
    prefs: async () => prefs,
    push: async (uid, p) => {
      pushed.push({ uid, title: p.title, body: p.body, route: p.data.route });
      return { sent: 1 };
    },
    clear: async (_uid, ids) => {
      cleared.push(ids);
    },
    markPushed: async (_uid, at) => {
      marked.push(at);
    },
  };
  return { deps, pushed, cleared, marked };
}

const threeInTwo: DigestEntry[] = [
  { threadId: 't1', count: 2 },
  { threadId: 't2', count: 1 },
];

test('three replies in two threads: one push, "3 new replies in 2 threads"', async () => {
  const f = fakes();
  const result = await sendDigest('maya', threeInTwo, f.deps, AFTERNOON);

  assert.equal(result, 'sent');
  assert.equal(f.pushed.length, 1);
  assert.equal(f.pushed[0].body, '3 new replies in 2 threads');
  assert.equal(f.pushed[0].route, '/community');
  assert.deepEqual(f.cleared, [['t1', 't2']]);
  // The rate limit learns about it.
  assert.deepEqual(f.marked, [AFTERNOON]);
});

test('in quiet hours: nothing sent, entries kept for the morning', async () => {
  const f = fakes();
  const result = await sendDigest('maya', threeInTwo, f.deps, NIGHT);

  assert.equal(result, 'held');
  assert.equal(f.pushed.length, 0);
  assert.equal(f.cleared.length, 0);
});

test('pushed ten minutes ago: held for the next run', async () => {
  const f = fakes({ lastPushAt: new Date(AFTERNOON.getTime() - 10 * 60 * 1000) });
  assert.equal(await sendDigest('maya', threeInTwo, f.deps, AFTERNOON), 'held');
  assert.equal(f.pushed.length, 0);
});

test('forums switched off: nothing sent, and the entries go', async () => {
  const f = fakes({ forums: false });
  assert.equal(await sendDigest('maya', threeInTwo, f.deps, AFTERNOON), 'dropped');
  assert.equal(f.pushed.length, 0);
  assert.deepEqual(f.cleared, [['t1', 't2']]);
});

test('a muted forum\'s thread is left out of the count', () => {
  const { plan, entries } = planDigest(
    { mutedForums: ['f2'] },
    [
      { threadId: 't1', count: 2, forumId: 'f1' },
      { threadId: 't9', count: 5, forumId: 'f2' },
    ],
    AFTERNOON,
  );
  assert.equal(plan, 'send');
  assert.deepEqual(entries.map((e) => e.threadId), ['t1']);
});

test('the words: singular and plural, as Grace reads them', () => {
  assert.equal(digestText([{ threadId: 't1', count: 1 }]).body, '1 new reply in 1 thread');
  assert.equal(digestText([{ threadId: 't1', count: 2 }]).body, '2 new replies in 1 thread');
});
