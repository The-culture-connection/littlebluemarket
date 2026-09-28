/**
 * Who is being treated as the owner of directory listings, and how many.
 *
 * READ ONLY. It writes nothing, anywhere. Reads as a throwaway anonymous
 * account through the REST API, under the deployed rules, exactly as
 * `peek.mjs` does — so it needs no credentials and can see only what any
 * phone can see. The account is deleted at the end.
 *
 * It exists because the failure here is invisible one document at a time.
 * Grace, 2026-09-24: staff enter listings on the businesses' behalf, so one
 * WordPress administrator is the *author* of all of them. An account linked
 * to that WordPress user was read as their *owner* and had the whole
 * directory mirrored under it, with a feed post for each.
 * `listingOwnershipRefusal` stops that happening again; this counts what
 * already happened, so the number is known before anything is released.
 *
 *   node scripts/inspect-directory-owners.mjs --project prod
 *
 * Published listings are world-readable (`firestore.rules:197`), which is
 * what makes this possible without an admin key.
 */
import { arg, firebaseApiKey, identityDelete, identitySignUp, resolveProject } from './lib/shopify-admin.mjs';

const projectId = resolveProject(arg('project', 'dev'));
const apiKey = firebaseApiKey();
if (!apiKey) {
  console.error('No Firebase API key found in lib/firebase_options.dart');
  process.exit(2);
}
const base = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents`;

/** More listings than any one business plausibly has (MAX_OWNED_LISTINGS). */
const SUSPICIOUS = 25;

const who = await identitySignUp(apiKey, {});
const headers = { Authorization: `Bearer ${who.idToken}` };

function unwrap(value) {
  if (value == null) return null;
  const [kind, inner] = Object.entries(value)[0];
  switch (kind) {
    case 'integerValue': return Number(inner);
    case 'arrayValue': return (inner.values ?? []).map(unwrap);
    case 'mapValue': return Object.fromEntries(Object.entries(inner.fields ?? {}).map(([k, v]) => [k, unwrap(v)]));
    case 'nullValue': return null;
    default: return inner;
  }
}
const fields = (doc) => Object.fromEntries(Object.entries(doc.fields ?? {}).map(([k, v]) => [k, unwrap(v)]));

async function getDoc(path) {
  const res = await fetch(`${base}/${path}`, { headers });
  if (!res.ok) return null;
  const json = await res.json();
  return json.error ? null : fields(json);
}

/** Every published listing, paged by document name so nothing is missed. */
async function publishedListings() {
  const all = [];
  let after = null;
  for (;;) {
    const structuredQuery = {
      from: [{ collectionId: 'directoryListings' }],
      where: { fieldFilter: { field: { fieldPath: 'status' }, op: 'EQUAL', value: { stringValue: 'publish' } } },
      orderBy: [{ field: { fieldPath: '__name__' }, direction: 'ASCENDING' }],
      limit: 300,
    };
    if (after) structuredQuery.startAt = { values: [{ referenceValue: after }], before: false };
    const res = await fetch(`${base}:runQuery`, {
      method: 'POST',
      headers: { ...headers, 'Content-Type': 'application/json' },
      body: JSON.stringify({ structuredQuery }),
    });
    const json = await res.json();
    if (json.error) throw new Error(json.error.message);
    const page = json.filter((r) => r.document);
    if (!page.length) break;
    for (const r of page) all.push({ id: r.document.name.split('/').pop(), path: r.document.name, ...fields(r.document) });
    after = page[page.length - 1].document.name;
    if (page.length < 300) break;
  }
  return all;
}

console.log(`Reading ${projectId} as an anonymous phone would (read only)\n`);

const listings = await publishedListings();
const byOwner = new Map();
let unclaimed = 0;
for (const l of listings) {
  const owner = String(l.ownerUid ?? '');
  if (!owner) { unclaimed += 1; continue; }
  if (!byOwner.has(owner)) byOwner.set(owner, []);
  byOwner.get(owner).push(l);
}

console.log(`published listings: ${listings.length}`);
console.log(`  unclaimed:          ${unclaimed}`);
console.log(`  with an owner:      ${listings.length - unclaimed}, across ${byOwner.size} account(s)`);

const rows = [...byOwner.entries()].sort((a, b) => b[1].length - a[1].length);
for (const [uid, owned] of rows) {
  const user = await getDoc(`users/${uid}`);
  const flag = owned.length > SUSPICIOUS ? '   <-- MORE THAN ONE BUSINESS PLAUSIBLY HAS' : '';
  console.log(`\n${uid}${flag}`);
  console.log(`  name      ${user?.name ?? '(profile not readable)'}   ${user?.handle ?? ''}`);
  console.log(`  postCount ${user?.postCount ?? '?'}   unclaimed:${user?.unclaimed ?? '-'}`);
  console.log(`  listings  ${owned.length}`);

  // The feed posts those listings created: `directory_{listingId}`, which is
  // what reads as "she is posting a ton of directory posts".
  let present = 0;
  for (const l of owned.slice(0, 400)) {
    if (await getDoc(`posts/directory_${l.id}`)) present += 1;
  }
  console.log(`  directory_ posts still in the feed: ${present}`);
  console.log(`  first few: ${owned.slice(0, 6).map((l) => `${l.id} ${l.title ?? ''}`).join(' | ')}`);
}

if (!rows.length) console.log('\nNo published listing has an owner.');

await identityDelete(apiKey, who.idToken);
