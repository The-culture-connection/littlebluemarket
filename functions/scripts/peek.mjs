#!/usr/bin/env node
// Reads public Firestore documents the way the app does: as a throwaway
// signed-in account, through the REST API, under the deployed rules. Prints
// what the phone would see. Nothing privileged; the account is deleted after.
//
//   node scripts/peek.mjs --doc catalog/123                 # one document
//   node scripts/peek.mjs --collection catalog/123/reviews  # a collection
//   node scripts/peek.mjs --reviews                         # recent review posts + their product's rating
import { arg, firebaseApiKey, hasFlag, identityDelete, identitySignUp, resolveProject } from './lib/shopify-admin.mjs';

const projectId = resolveProject(arg('project', 'dev'));
const apiKey = firebaseApiKey();
if (!apiKey) { console.error('No Firebase API key found in lib/firebase_options.dart'); process.exit(2); }
const base = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents`;

const who = await identitySignUp(apiKey, {}); // anonymous
const headers = { Authorization: `Bearer ${who.idToken}` };

function unwrap(value) {
  if (value == null) return null;
  const [kind, inner] = Object.entries(value)[0];
  switch (kind) {
    case 'integerValue': return Number(inner);
    case 'doubleValue': return inner;
    case 'stringValue': return inner;
    case 'booleanValue': return inner;
    case 'nullValue': return null;
    case 'timestampValue': return inner;
    case 'arrayValue': return (inner.values ?? []).map(unwrap);
    case 'mapValue': return Object.fromEntries(Object.entries(inner.fields ?? {}).map(([k, v]) => [k, unwrap(v)]));
    default: return inner;
  }
}
function fields(doc) {
  return Object.fromEntries(Object.entries(doc.fields ?? {}).map(([k, v]) => [k, unwrap(v)]));
}
async function getDoc(path) {
  const res = await fetch(`${base}/${path}`, { headers });
  if (res.status === 404) return null;
  const json = await res.json();
  if (json.error) throw new Error(`${path}: ${json.error.message}`);
  return fields(json);
}
async function listCol(path, pageSize = 20) {
  const res = await fetch(`${base}/${path}?pageSize=${pageSize}`, { headers });
  const json = await res.json();
  if (json.error) throw new Error(`${path}: ${json.error.message}`);
  return (json.documents ?? []).map((d) => ({ id: d.name.split('/').pop(), ...fields(d) }));
}
async function query(collectionId, filterField, filterValue, limit = 10) {
  const res = await fetch(`${base}:runQuery`, {
    method: 'POST', headers: { ...headers, 'Content-Type': 'application/json' },
    body: JSON.stringify({ structuredQuery: {
      from: [{ collectionId }],
      where: { fieldFilter: { field: { fieldPath: filterField }, op: 'EQUAL', value: { stringValue: filterValue } } },
      limit,
    } }),
  });
  const json = await res.json();
  if (json.error) throw new Error(`${collectionId}: ${json.error.message}`);
  return json.filter((r) => r.document).map((r) => ({ id: r.document.name.split('/').pop(), ...fields(r.document) }));
}

try {
  if (arg('doc')) {
    console.log(JSON.stringify(await getDoc(arg('doc')), null, 2));
  } else if (arg('collection')) {
    console.log(JSON.stringify(await listCol(arg('collection')), null, 2));
  } else if (hasFlag('reviews')) {
    const posts = await query('posts', 'kind', 'review');
    console.log(`${posts.length} review post(s)`);
    const seen = new Set();
    for (const post of posts) {
      console.log(`- post ${post.id}: product ${post.productId} rating ${post.rating} by ${post.authorId} reviewId ${post.reviewId ?? '-'}`);
      if (seen.has(post.productId)) continue;
      seen.add(post.productId);
      const summary = await getDoc(`catalog/${post.productId}/rating/summary`);
      const product = await getDoc(`catalog/${post.productId}`);
      const reviews = await listCol(`catalog/${post.productId}/reviews`);
      console.log(`  rating/summary: ${JSON.stringify(summary)}`);
      console.log(`  catalog doc: rating=${product?.rating} ratingCount=${product?.ratingCount} title=${JSON.stringify(product?.title)}`);
      console.log(`  reviews subcollection: ${reviews.length} -> ${JSON.stringify(reviews.map((r) => ({ id: r.id, rating: r.rating, authorId: r.authorId })))}`);
    }
  } else {
    console.error('pass --doc <path>, --collection <path>, or --reviews');
  }
} finally {
  await identityDelete(apiKey, who.idToken);
}
