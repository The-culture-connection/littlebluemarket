#!/usr/bin/env node
//
// Puts every active product on the app's sales channel (the "headless"
// publication the Storefront token belongs to). The mirror does this one
// product at a time as products change (`ensureOnAppChannel` in
// src/collections.ts), but products mirrored before the app had
// `write_publications` were never published, and the checkout then says
// "is not available in the app's shop". This walks the whole store once.
//
//   npm run publish-to-app                    # dry run on dev: counts only
//   npm run publish-to-app -- --apply         # publish on dev
//   npm run publish-to-app:prod               # dry run on the real shop
//   npm run publish-to-app:prod -- --apply    # publish on the real shop
//   ... --id 15858572001440                   # one product
//   ... --title "Mobile App Development"       # products whose title contains this
//   ... --limit 200                           # stop after N products
//
// Read-only unless --apply is given. Prints no secret.

import {
  adminGraphQL,
  arg,
  hasFlag,
  resolveProject,
  shopifyContext,
} from './lib/shopify-admin.mjs';

const projectId = resolveProject(arg('project', 'dev'));
const apply = hasFlag('apply');
const onlyId = arg('id');
const onlyTitle = arg('title');
const limit = Number(arg('limit', '0')) || Infinity;

const ctx = await shopifyContext(projectId, { allowSecretAccess: true });
console.log(`publish-to-app · ${projectId} · ${ctx.domain} · ${apply ? 'APPLY' : 'dry run'}`);

// The same choice the functions make (pickAppPublication): the headless one.
const pubs = await adminGraphQL(ctx, `{ publications(first: 20) { nodes { id name } } }`);
for (const p of pubs.publications.nodes) console.log(`  channel  ${p.name}`);
const headless = pubs.publications.nodes.find((p) => /headless/i.test(p.name));
if (!headless) {
  console.error(
    'FAIL  no "Headless" sales channel on this store, so the app cannot sell anything.\n' +
      '      fix -> Shopify admin -> Sales channels -> add "Headless" (or "Hydrogen"), create a storefront,\n' +
      '      and put its private access token in SHOPIFY_STOREFRONT_PRIVATE_TOKEN.',
  );
  process.exit(1);
}
console.log(`  using    ${headless.name} (${headless.id})`);

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// Shopify's leaky bucket says "Throttled"; wait and try again.
async function gql(query, variables, attempt = 0) {
  try {
    return await adminGraphQL(ctx, query, variables);
  } catch (error) {
    if (/throttl/i.test(String(error)) && attempt < 6) {
      await sleep(1500 * (attempt + 1));
      return gql(query, variables, attempt + 1);
    }
    throw error;
  }
}

const LIST = `
  query Active($after: String, $pub: ID!, $q: String) {
    products(first: 100, after: $after, query: $q) {
      pageInfo { hasNextPage endCursor }
      nodes { id title status publishedOnPublication(publicationId: $pub) }
    }
  }
`;

const PUBLISH = `
  mutation Publish($id: ID!, $input: [PublicationInput!]!) {
    publishablePublish(id: $id, input: $input) { userErrors { field message } }
  }
`;

let seen = 0;
let already = 0;
let missing = 0;
let published = 0;
let failed = 0;
const examples = [];

async function publish(node) {
  if (!apply) return;
  const data = await gql(PUBLISH, { id: node.id, input: [{ publicationId: headless.id }] });
  const errors = data.publishablePublish.userErrors;
  if (errors.length) {
    failed += 1;
    console.log(`  FAIL  ${node.title}: ${errors.map((e) => e.message).join('; ')}`);
    return;
  }
  published += 1;
  await sleep(60);
}

const onlyQuery = arg('query');
if (onlyTitle || onlyQuery) {
  // --query takes Shopify's own search syntax, e.g. "created_at:>2026-09-09".
  const data = await gql(
    `query($q: String!, $pub: ID!) { products(first: 10, query: $q, sortKey: CREATED_AT, reverse: true) { nodes { id title status vendor createdAt publishedOnPublication(publicationId: $pub) } } }`,
    { q: onlyQuery ?? `title:*${onlyTitle.replace(/"/g, '')}*`, pub: headless.id },
  );
  if (!data.products.nodes.length) console.log(`  no product with "${onlyTitle}" in its title`);
  for (const node of data.products.nodes) {
    seen += 1;
    console.log(`  ${node.id.replace('gid://shopify/Product/', '')} · ${node.title} · ${node.vendor} · ${node.status} · created ${node.createdAt} · on app channel: ${node.publishedOnPublication}`);
    if (node.publishedOnPublication) already += 1;
    else if (node.status === 'ACTIVE') {
      missing += 1;
      await publish(node);
    } else console.log('        not ACTIVE in Shopify, so it cannot be sold anywhere until the merchant makes it Active');
  }
} else if (onlyId) {
  const data = await gql(
    `query($id: ID!, $pub: ID!) { product(id: $id) { id title status publishedOnPublication(publicationId: $pub) } }`,
    { id: `gid://shopify/Product/${onlyId}`, pub: headless.id },
  );
  const node = data.product;
  if (!node) {
    console.error(`FAIL  no product ${onlyId} on ${ctx.domain}`);
    process.exit(1);
  }
  console.log(`  ${node.title} · ${node.status} · on app channel: ${node.publishedOnPublication}`);
  if (!node.publishedOnPublication) {
    missing = 1;
    await publish(node);
  }
} else {
  let after = null;
  while (seen < limit) {
    const page = await gql(LIST, { after, pub: headless.id, q: 'status:active' });
    for (const node of page.products.nodes) {
      if (seen >= limit) break;
      seen += 1;
      if (node.publishedOnPublication) {
        already += 1;
        continue;
      }
      missing += 1;
      if (examples.length < 5) examples.push(node.title);
      await publish(node);
    }
    if (seen % 1000 < 100) console.log(`  … ${seen} checked, ${missing} off the channel, ${published} published`);
    if (!page.products.pageInfo.hasNextPage) break;
    after = page.products.pageInfo.endCursor;
  }
}

console.log('');
console.log(`checked ${seen} active product(s): ${already} already on the app's channel, ${missing} not.`);
if (examples.length) console.log(`  e.g. ${examples.map((t) => JSON.stringify(t)).join(', ')}`);
if (apply) console.log(`published ${published}, failed ${failed}.`);
else if (missing) console.log(`dry run: nothing changed. Re-run with --apply to publish them.`);
process.exit(failed ? 1 : 0);
