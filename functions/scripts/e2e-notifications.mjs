#!/usr/bin/env node
//
// The notification rules, proved end to end on the DEV project.
//
//   npm run e2e:notify               # about 6 minutes
//   npm run e2e:notify -- --digest   # also waits for the scheduled forum digest (up to ~35 minutes)
//
// What makes this honest rather than hopeful:
//
//  * The receiver is a real FCM device. This process registers with Google's
//    push service exactly as a browser does, writes its token where the app
//    writes a phone's, and only counts a push as delivered when FCM hands
//    this process the message. "The function said it sent" is not a pass.
//  * Every action carries a one-off nonce, and a push only matches a check
//    when its body carries that nonce. A stale or unrelated push cannot pass.
//  * Nothing is faked on the server. Two throwaway accounts write posts,
//    comments, threads and messages through the Firestore API under the
//    deployed security rules, and the deployed triggers do the rest.
//  * Every "no push" check is paired: the bell row for that same action must
//    appear (so the trigger ran and chose not to push), and a positive push
//    must get through on the same channel afterwards (so the silence was not
//    a dead channel). A push that turns up late fails the run at the end.
//  * The channel is checked first. If the test push does not arrive, every
//    other result would mean nothing, so the run stops as INCONCLUSIVE.
//
// Dev only: the keys are read from firebase/config/dev, never from
// lib/firebase_options.dart (which run-live swaps between projects), and the
// run refuses any project that is not little-blue-610e5. Both accounts are
// deleted at the end through the app's own delete-account path.

import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

import { PushReceiver } from '@eneris/push-receiver';

const DEV = 'little-blue-610e5';
const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const WITH_DIGEST = process.argv.includes('--digest');

/** How long a push has to arrive. The probe measured a few seconds. */
const ARRIVE_MS = 90_000;
/** How long a push has to *not* arrive before "held" counts. */
const SILENCE_MS = 45_000;
/** A scheduled run every 30 minutes, plus slack for a cold start. */
const DIGEST_MS = 36 * 60_000;

// ------------------------------------------------------------- dev config

function devWebConfig() {
  const src = readFileSync(join(REPO, 'firebase', 'config', 'dev', 'firebase_options.dart'), 'utf8');
  const web = src.slice(src.indexOf('FirebaseOptions web'));
  const pick = (k) => web.match(new RegExp(`${k}:\\s*'([^']+)'`))?.[1];
  const cfg = {
    apiKey: pick('apiKey'),
    appId: pick('appId'),
    messagingSenderId: pick('messagingSenderId'),
    projectId: pick('projectId'),
  };
  if (cfg.projectId !== DEV) {
    throw new Error(`Refusing to run: firebase/config/dev names "${cfg.projectId}", not ${DEV}.`);
  }
  return cfg;
}

const cfg = devWebConfig();
const IDENTITY = 'https://identitytoolkit.googleapis.com/v1';
const DOCS = `projects/${DEV}/databases/(default)/documents`;
const FIRESTORE = `https://firestore.googleapis.com/v1/${DOCS}`;
const FUNCTIONS = `https://us-central1-${DEV}.cloudfunctions.net`;

// ---------------------------------------------------------------- output

const results = [];
function record(status, name, detail = '') {
  results.push({ status, name, detail });
  const colour = { PASS: 32, FAIL: 31, SKIP: 33, INCONCLUSIVE: 35 }[status] ?? 0;
  console.log(`\x1b[${colour}m${status.padEnd(12)}\x1b[0m ${name}${detail ? `  ·  ${detail}` : ''}`);
}
const say = (line) => console.log(`             ${line}`);

// ------------------------------------------------------------- accounts

async function identity(path, body) {
  const res = await fetch(`${IDENTITY}/${path}?key=${cfg.apiKey}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ returnSecureToken: true, ...body }),
  });
  const json = await res.json();
  if (!res.ok) throw new Error(`${path}: ${json.error?.message ?? res.status}`);
  return json;
}

async function newAccount(label) {
  const email = `e2e-${label}-${Date.now()}@example.com`;
  const password = `e2e-${crypto.randomUUID()}`;
  const { idToken, localId } = await identity('accounts:signUp', { email, password });
  return { label, email, password, uid: localId, token: idToken };
}

async function freshToken(account) {
  const { idToken } = await identity('accounts:signInWithPassword', {
    email: account.email,
    password: account.password,
  });
  account.token = idToken;
}

// ------------------------------------------------------------- firestore

function value(v) {
  if (v === null || v === undefined) return { nullValue: null };
  if (typeof v === 'string') return { stringValue: v };
  if (typeof v === 'boolean') return { booleanValue: v };
  if (typeof v === 'number') return Number.isInteger(v) ? { integerValue: String(v) } : { doubleValue: v };
  if (v instanceof Date) return { timestampValue: v.toISOString() };
  if (Array.isArray(v)) return { arrayValue: { values: v.map(value) } };
  return { mapValue: { fields: Object.fromEntries(Object.entries(v).map(([k, x]) => [k, value(x)])) } };
}
function unwrap(v) {
  if (!v) return null;
  const [kind, inner] = Object.entries(v)[0];
  if (kind === 'integerValue') return Number(inner);
  if (kind === 'arrayValue') return (inner.values ?? []).map(unwrap);
  if (kind === 'mapValue') return Object.fromEntries(Object.entries(inner.fields ?? {}).map(([k, x]) => [k, unwrap(x)]));
  return inner;
}

/**
 * Writes one document the way the app does, with `createdAt` (and any other
 * named fields) set to the server's request time, which the rules insist on.
 */
async function write(account, path, fields, { serverTime = ['createdAt'], merge = false } = {}) {
  const res = await fetch(`${FIRESTORE}:commit`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${account.token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      writes: [
        {
          update: {
            name: `${DOCS}/${path}`,
            fields: Object.fromEntries(Object.entries(fields).map(([k, v]) => [k, value(v)])),
          },
          ...(merge ? { updateMask: { fieldPaths: Object.keys(fields) } } : {}),
          updateTransforms: serverTime.map((fieldPath) => ({ fieldPath, setToServerValue: 'REQUEST_TIME' })),
        },
      ],
    }),
  });
  if (!res.ok) throw new Error(`write ${path}: ${(await res.json()).error?.message ?? res.status}`);
}

async function read(account, path) {
  const res = await fetch(`${FIRESTORE}/${path}`, { headers: { Authorization: `Bearer ${account.token}` } });
  if (res.status === 404) return null;
  const json = await res.json();
  if (json.error) throw new Error(`read ${path}: ${json.error.message}`);
  return Object.fromEntries(Object.entries(json.fields ?? {}).map(([k, v]) => [k, unwrap(v)]));
}

async function list(account, path) {
  const res = await fetch(`${FIRESTORE}/${path}?pageSize=100`, {
    headers: { Authorization: `Bearer ${account.token}` },
  });
  const json = await res.json();
  if (json.error) throw new Error(`list ${path}: ${json.error.message}`);
  return (json.documents ?? []).map((d) => Object.fromEntries(Object.entries(d.fields ?? {}).map(([k, v]) => [k, unwrap(v)])));
}

async function removeField(account, path, field) {
  const res = await fetch(`${FIRESTORE}/${path}?updateMask.fieldPaths=${field}`, {
    method: 'PATCH',
    headers: { Authorization: `Bearer ${account.token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ fields: {} }),
  });
  if (!res.ok) throw new Error(`clear ${path}.${field}: ${(await res.json()).error?.message ?? res.status}`);
}

async function call(account, name, data = {}) {
  const res = await fetch(`${FUNCTIONS}/${name}`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${account.token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ data }),
  });
  const json = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(`${name}: ${json.error?.message ?? res.status}`);
  return json.result;
}

// ------------------------------------------------------------- the device

/** Every push this device has been handed, in order. */
const inbox = [];
let receiver;

function pushes() {
  return inbox.map((n) => ({
    title: n.message?.notification?.title ?? '',
    body: n.message?.notification?.body ?? '',
    type: n.message?.data?.type ?? '',
    at: n.at,
  }));
}

async function waitFor(match, ms) {
  const deadline = Date.now() + ms;
  while (Date.now() < deadline) {
    const hit = pushes().find(match);
    if (hit) return hit;
    await new Promise((r) => setTimeout(r, 500));
  }
  return null;
}

const nonce = (what) => `${what}-${crypto.randomUUID().slice(0, 8)}`;

async function bellRow(account, text, ms = ARRIVE_MS) {
  const deadline = Date.now() + ms;
  while (Date.now() < deadline) {
    const rows = await list(account, `users/${account.uid}/notifications`);
    const row = rows.find((r) => String(r.text ?? '').includes(text));
    if (row) return row;
    await new Promise((r) => setTimeout(r, 2000));
  }
  return null;
}

/** "HH:mm" in Detroit, which is the backend's default zone. */
function detroit(offsetMinutes) {
  const at = new Date(Date.now() + offsetMinutes * 60_000);
  return new Intl.DateTimeFormat('en-GB', {
    timeZone: 'America/Detroit',
    hour: '2-digit',
    minute: '2-digit',
    hourCycle: 'h23',
  }).format(at);
}

/** A quiet window that is certainly not now, so only the rate limit is in play. */
async function quietElsewhere(r) {
  await write(r, `users/${r.uid}/settings/notifications`, { quietStart: detroit(300), quietEnd: detroit(360) }, { serverTime: [], merge: true });
}
async function quietNow(r) {
  await write(r, `users/${r.uid}/settings/notifications`, { quietStart: detroit(-60), quietEnd: detroit(60) }, { serverTime: [], merge: true });
}
async function forgetLastPush(r) {
  await removeField(r, `users/${r.uid}/settings/notifications`, 'lastPushAt');
}

// ---------------------------------------------------------------- checks

/** A push with [text] in its body arrives, and its title matches. */
async function expectPush(name, text, titleTest) {
  const hit = await waitFor((p) => p.body.includes(text), ARRIVE_MS);
  if (!hit) return record('FAIL', name, `no push carrying ${text} within ${ARRIVE_MS / 1000}s`);
  if (!titleTest(hit.title)) return record('FAIL', name, `arrived, but titled "${hit.title}"`);
  record('PASS', name, `"${hit.title}" · ${hit.body}`);
  return hit;
}

/** The action reached the bell, and no push for it arrived. */
const heldBack = [];
async function expectHeld(name, r, text) {
  const row = await bellRow(r, text);
  if (!row) return record('FAIL', name, `no bell row for ${text}: the trigger never ran, so silence proves nothing`);
  const hit = await waitFor((p) => p.body.includes(text), SILENCE_MS);
  if (hit) return record('FAIL', name, `pushed anyway: "${hit.title}"`);
  heldBack.push({ name, text });
  record('PASS', name, `bell row written, no push in ${SILENCE_MS / 1000}s`);
}

// ------------------------------------------------------------------ run

const R = await newAccount('receiver');
const S = await newAccount('sender');
const run = nonce('run');
console.log(`\nNotification rules, end to end, on ${DEV} (${run})`);
say(`receiver ${R.uid} · sender ${S.uid}`);

let aborted = false;
try {
  // Profiles, as account setup writes them (the rules require zeroed counts).
  for (const a of [R, S]) {
    await write(a, `users/${a.uid}`, {
      name: a === R ? 'E2E Receiver' : 'E2E Sender',
      handle: `e2e_${a.label}_${a.uid.slice(0, 6).toLowerCase()}`,
      revenueCents: 0,
      purchaseCount: 0,
      postCount: 0,
    });
  }

  // The device: a real FCM registration, stored where the app stores a phone's.
  receiver = new PushReceiver({ firebase: cfg, persistentIds: [] });
  receiver.onNotification((n) => inbox.push({ ...n, at: Date.now() }));
  await receiver.connect();
  const token = receiver.fcmToken;
  if (!token) throw new Error('FCM gave this process no token');
  // The raw token as the document id, as the app writes it: FCM tokens are
  // letters, digits, dash, underscore and colon, all fine in an id.
  await write(R, `users/${R.uid}/devices/${token}`, { token, platform: 'e2e-node' });
  await quietElsewhere(R);

  // 0. The channel. Without it nothing below means anything.
  const sent = await call(R, 'pushTestMe');
  const channel = await waitFor((p) => p.type === 'test' || p.body === 'This phone is set up for notifications.', ARRIVE_MS);
  if (!channel) {
    record('INCONCLUSIVE', 'channel: pushTestMe reaches this device', `nothing arrived (pushTestMe said ${JSON.stringify(sent)}); every other check would be meaningless`);
    aborted = true;
  } else {
    record('PASS', 'channel: pushTestMe reaches this device', `"${channel.body}"`);
  }

  if (!aborted) {
    // A post of the receiver's for the sender to comment on.
    const postId = nonce('post');
    await write(R, `posts/${postId}`, { kind: 'shoutout', authorId: R.uid, text: `E2E post ${run}`, tags: [], likeCount: 0, commentCount: 0 });

    // 1. A comment pushes, and the rate limit learns about it.
    const c1 = nonce('comment');
    await write(S, `posts/${postId}/comments/${c1}`, { authorId: S.uid, postId, text: `first ${c1}`, likeCount: 0 });
    await expectPush('comment on your post pushes', c1, (t) => /E2E Sender commented/.test(t));
    const settings = await read(R, `users/${R.uid}/settings/notifications`);
    if (settings?.lastPushAt) record('PASS', 'a push that landed stamps lastPushAt', settings.lastPushAt);
    else record('FAIL', 'a push that landed stamps lastPushAt', 'missing: the rate limit would never engage');

    // 2. Rate limit: a second comment inside 20 minutes is held.
    const c2 = nonce('comment');
    await write(S, `posts/${postId}/comments/${c2}`, { authorId: S.uid, postId, text: `second ${c2}`, likeCount: 0 });
    await expectHeld('rate limit: a second comment within 20 min is held', R, c2);

    // 3. A mention is a person talking to you: through, despite the limit.
    const m1 = nonce('mention');
    await write(S, `posts/${nonce('mpost')}`, {
      kind: 'shoutout',
      authorId: S.uid,
      text: `hey ${m1}`,
      mentionedUids: [R.uid],
      tags: [],
      likeCount: 0,
      commentCount: 0,
    });
    await expectPush('a mention gets through the rate limit', m1, (t) => /mentioned you/.test(t));

    // 4. A direct message: through the limit too, titled with the sender.
    const conversationId = [R.uid, S.uid].sort().join('_');
    await write(S, `conversations/${conversationId}`, { participantIds: [S.uid, R.uid], preview: '' });
    const d1 = nonce('dm');
    await write(S, `conversations/${conversationId}/messages/${d1}`, { conversationId, authorId: S.uid, text: `hi ${d1}` });
    await expectPush('a direct message pushes, titled with the sender', d1, (t) => t === 'E2E Sender');

    // 5. Quiet hours: the window around now, the limit cleared so only quiet
    //    hours can be what holds the comment back.
    await quietNow(R);
    await forgetLastPush(R);
    const c3 = nonce('comment');
    await write(S, `posts/${postId}/comments/${c3}`, { authorId: S.uid, postId, text: `night ${c3}`, likeCount: 0 });
    await expectHeld('quiet hours: a comment is held', R, c3);
    const d2 = nonce('dm');
    await write(S, `conversations/${conversationId}/messages/${d2}`, { conversationId, authorId: S.uid, text: `night ${d2}` });
    await expectPush('quiet hours: a direct message still gets through', d2, (t) => t === 'E2E Sender');

    // 6. Forum reply: never pushed directly; waits for the digest.
    await quietElsewhere(R);
    await forgetLastPush(R);
    const threadId = nonce('thread');
    await write(R, `threads/${threadId}`, { forumId: 'e2e', authorId: R.uid, title: `E2E thread ${run}`, body: '', commentCount: 0 });
    const f1 = nonce('reply');
    await write(S, `threads/${threadId}/comments/${f1}`, { authorId: S.uid, text: `reply ${f1}` });
    await expectHeld('a forum reply is not pushed on its own', R, f1);

    if (WITH_DIGEST) {
      say(`waiting for the scheduled digest (every 30 min; up to ${DIGEST_MS / 60_000} min)…`);
      const since = Date.now();
      const digest = await waitFor((p) => p.at >= since && p.title === 'New in your forums', DIGEST_MS);
      if (!digest) record('FAIL', 'the digest arrives: "1 new reply in 1 thread"', 'nothing from forumDigestScheduled');
      else if (digest.body !== '1 new reply in 1 thread') record('FAIL', 'the digest arrives: "1 new reply in 1 thread"', `said "${digest.body}"`);
      else record('PASS', 'the digest arrives: "1 new reply in 1 thread"', `after ${Math.round((digest.at - since) / 60_000)} min`);
    } else {
      record('SKIP', 'the digest arrives', 'run with --digest to wait for the scheduled run (up to ~35 min)');
    }

    // Anything held back must still be held back at the very end.
    for (const { name, text } of heldBack) {
      const late = pushes().find((p) => p.body.includes(text));
      if (late) record('FAIL', `${name} (late)`, `arrived after all: "${late.title}"`);
    }
  }
} catch (error) {
  record('FAIL', 'the run itself', error.message);
} finally {
  receiver?.destroy();
  for (const a of [R, S]) {
    try {
      await freshToken(a);
      await call(a, 'deleteMyAccountNow', { confirm: 'DELETE', scope: 'account' });
    } catch (error) {
      console.log(`             cleanup: ${a.label} not deleted (${error.message}); remove ${a.email} by hand`);
    }
  }
}

const count = (s) => results.filter((r) => r.status === s).length;
console.log(`\n${count('PASS')} PASS, ${count('FAIL')} FAIL, ${count('SKIP')} SKIP${count('INCONCLUSIVE') ? `, ${count('INCONCLUSIVE')} INCONCLUSIVE` : ''}.`);
if (count('FAIL') || count('INCONCLUSIVE')) {
  console.log('Paste this whole block to Claude.');
  process.exit(1);
}
process.exit(0);
