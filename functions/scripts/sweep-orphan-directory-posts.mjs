/**
 * Removes directory feed posts that assert an ownership nobody holds.
 *
 *   node scripts/sweep-orphan-directory-posts.mjs --project prod --uid <uid>
 *   node scripts/sweep-orphan-directory-posts.mjs --project prod --uid <uid> --delete
 *
 * The 2026-09-24 directory-ownership bug attributed the whole of
 * littlebluecart.com to one account, which posted a `kind: 'directory'` feed
 * post for every listing. Releasing the listings fixed `directoryListings`
 * and left those posts behind, so the market's feed was almost entirely one
 * account's mistake.
 *
 * **It sweeps by fact, not by id range.** A hand-typed list of ids is wrong
 * twice over: it misses the ones nobody scrolled far enough to see (the first
 * list covered 85 of 169), and a range takes the neighbours, which are real
 * businesses that really do own their listing. So this refuses to run unless
 * the account owns **no** directory listings at all, and then deletes only
 * its directory posts: at that point every one of them is an orphan by
 * construction, and the account's own shoutouts, carts and reviews are
 * untouched because they are a different kind.
 *
 * Safe to run twice, and safe to run early: it deletes nothing while the
 * account still owns something.
 */
import {
  arg,
  firebaseApiKey,
  firebaseCli,
  hasFlag,
  identityDelete,
  identitySignUp,
  resolveProject,
} from './lib/shopify-admin.mjs';

const projectId = resolveProject(arg('project', 'prod'));
const uid = arg('uid', '');
const doIt = hasFlag('delete');

if (!uid) {
  console.error('Which account? Pass --uid <uid>.');
  process.exit(1);
}

const apiKey = firebaseApiKey();
const probe = await identitySignUp(apiKey, {
  email: `sweep-${Date.now()}@example.com`,
  password: `Sweep-${Date.now()}!`,
});
if (!probe.idToken) {
  console.error('Could not sign in to read the data.');
  process.exit(1);
}

const base = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents`;
const headers = {
  Authorization: `Bearer ${probe.idToken}`,
  'Content-Type': 'application/json',
};
const equals = (field, value) => ({
  fieldFilter: {
    field: { fieldPath: field },
    op: 'EQUAL',
    value: { stringValue: value },
  },
});

async function query(structuredQuery) {
  const response = await fetch(`${base}:runQuery`, {
    method: 'POST',
    headers,
    body: JSON.stringify({ structuredQuery }),
  });
  const body = await response.json();
  return Array.isArray(body) ? body.filter((d) => d.document) : [];
}

// The safety check, and the whole basis of the sweep: an account that still
// owns listings may legitimately have posted about them.
const owned = await query({
  from: [{ collectionId: 'directoryListings' }],
  where: equals('ownerUid', uid),
  limit: 1,
});
if (owned.length) {
  console.error(
    `\nREFUSING: ${uid} still owns at least one directory listing, so its ` +
      'directory posts are not orphans. Release the listings first.',
  );
  await identityDelete(apiKey, probe.idToken);
  process.exit(1);
}

const posts = await query({
  from: [{ collectionId: 'posts' }],
  where: equals('authorId', uid),
  limit: 1000,
});
const orphans = posts
  .filter((d) => d.document.fields?.kind?.stringValue === 'directory')
  .map((d) => d.document.name.split('/').pop());
const kept = posts.length - orphans.length;

console.log(`\nproject ${projectId} · account ${uid}`);
console.log(`  owns 0 directory listings, so its directory posts are orphans`);
console.log(`  ${orphans.length} directory posts to remove`);
console.log(`  ${kept} other posts by this account, which stay\n`);

if (!doIt) {
  console.log('showing only, nothing deleted (add --delete)');
  await identityDelete(apiKey, probe.idToken);
  process.exit(0);
}

let removed = 0;
let failed = 0;
for (const id of orphans) {
  // Recursive: a post's comments go with the post. Without this the ones
  // somebody had commented on survive and the rest do not, which is the
  // worst of both.
  const out = firebaseCli([
    'firestore:delete',
    `posts/${id}`,
    '--project',
    projectId,
    '--force',
    '-r',
  ]);
  if (out.ok) {
    removed++;
    if (removed % 20 === 0) console.log(`  ${removed} deleted…`);
  } else {
    failed++;
    console.log(`  FAILED  posts/${id}  ${(out.stderr ?? '').split('\n')[0]}`);
  }
}

console.log(`\n${removed} deleted, ${failed} failed.`);
console.log(
  "onPostWritten walks the author's postCount down as each one goes, so the " +
    'profile count follows without a second pass.',
);
await identityDelete(apiKey, probe.idToken);
