#!/usr/bin/env node
//
// Registers the Shopify webhooks this backend needs, idempotently.
//
// Doing this by hand is fine once and error-prone every time after, and a
// subscription that quietly stops existing looks exactly like "nothing is
// selling" — the catalog mirror freezes, revenue stops attributing, and no
// error is raised anywhere. So it is a script, and it is safe to re-run on
// every deploy: it reads what exists first and creates only what is missing.
//
//   node scripts/register-webhooks.mjs --url https://<region>-<project>.cloudfunctions.net/shopifyWebhook
//
// Credentials come from the environment, or from functions/.env.<project-id>
// for the two non-secret params. The client secret is never read from a file:
//
//   SHOPIFY_CLIENT_SECRET=... node scripts/register-webhooks.mjs --url ...
//
// Deliberately standalone — it does not import the compiled functions, because
// `adminGraphQL` mints its token through Firestore and expects to be running
// inside the Functions runtime. Same client-credentials grant, no Firebase.

import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

/** The topics this backend actually handles, per `shopifyWebhook`'s router. */
const TOPICS = [
  'PRODUCTS_CREATE',
  'PRODUCTS_UPDATE',
  'PRODUCTS_DELETE',
  'ORDERS_PAID',
  'FULFILLMENTS_CREATE',
  'FULFILLMENTS_UPDATE',
];

const HERE = dirname(fileURLToPath(import.meta.url));

function arg(name) {
  const i = process.argv.indexOf(`--${name}`);
  return i === -1 ? undefined : process.argv[i + 1];
}

/**
 * Params from `functions/.env.<project-id>`, which is where Firebase keeps the
 * non-secret ones. Env wins, so a one-off run can override without editing.
 */
function loadParams(projectId) {
  const out = {};
  if (projectId) {
    try {
      const text = readFileSync(join(HERE, '..', `.env.${projectId}`), 'utf8');
      for (const line of text.split('\n')) {
        const match = line.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*)$/);
        if (match && match[2].trim()) out[match[1]] = match[2].trim();
      }
    } catch {
      // Absent is fine; the env may carry everything.
    }
  }
  return { ...out, ...process.env };
}

/** A short-lived Admin token, the same grant `functions/src/shopify/token.ts` uses. */
async function mintAdminToken({ domain, clientId, clientSecret }) {
  const response = await fetch(`https://${domain}/admin/oauth/access_token`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      grant_type: 'client_credentials',
      client_id: clientId,
      client_secret: clientSecret,
    }),
  });
  if (!response.ok) {
    throw new Error(
      `Could not mint an Admin token (${response.status}). Check ` +
        'SHOPIFY_CLIENT_ID / SHOPIFY_CLIENT_SECRET, and that the app is ' +
        'installed on this store.',
    );
  }
  const body = await response.json();
  if (!body.access_token) throw new Error('No access_token in the grant response');
  return body.access_token;
}

async function graphql({ domain, version, token }, query, variables) {
  const response = await fetch(
    `https://${domain}/admin/api/${version}/graphql.json`,
    {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Shopify-Access-Token': token,
      },
      body: JSON.stringify({ query, variables }),
    },
  );
  const body = await response.json();
  if (body.errors) {
    throw new Error(`Admin API: ${JSON.stringify(body.errors)}`);
  }
  return body.data;
}

const EXISTING = `
  query Existing($after: String) {
    webhookSubscriptions(first: 100, after: $after) {
      pageInfo { hasNextPage endCursor }
      nodes {
        id
        topic
        endpoint { ... on WebhookHttpEndpoint { callbackUrl } }
      }
    }
  }
`;

const CREATE = `
  mutation Create($topic: WebhookSubscriptionTopic!, $url: URL!) {
    webhookSubscriptionCreate(
      topic: $topic
      webhookSubscription: { callbackUrl: $url, format: JSON }
    ) {
      webhookSubscription { id }
      userErrors { field message }
    }
  }
`;

async function main() {
  const url = arg('url');
  const projectId = arg('project');
  if (!url) {
    console.error(
      'Missing --url.\n\n' +
        '  node scripts/register-webhooks.mjs \\\n' +
        '    --url https://<region>-<project>.cloudfunctions.net/shopifyWebhook \\\n' +
        '    --project little-blue-610e5\n\n' +
        'The URL is printed at the end of `npm run deploy:dev`.',
    );
    process.exit(1);
  }

  const params = loadParams(projectId);
  const domain = params.SHOPIFY_STORE_DOMAIN;
  const clientId = params.SHOPIFY_CLIENT_ID;
  const clientSecret = params.SHOPIFY_CLIENT_SECRET;
  const version = params.SHOPIFY_API_VERSION ?? '2026-07';

  const missing = [
    !domain && 'SHOPIFY_STORE_DOMAIN',
    !clientId && 'SHOPIFY_CLIENT_ID',
    !clientSecret && 'SHOPIFY_CLIENT_SECRET (env only — never from a file)',
  ].filter(Boolean);

  if (missing.length) {
    console.error(`Missing config: ${missing.join(', ')}`);
    process.exit(1);
  }

  const token = await mintAdminToken({ domain, clientId, clientSecret });
  const ctx = { domain, version, token };

  // Read first. Re-running this must not produce a second copy of every hook.
  const existing = new Set();
  let after = null;
  for (;;) {
    const page = await graphql(ctx, EXISTING, { after });
    for (const node of page.webhookSubscriptions.nodes) {
      if (node.endpoint?.callbackUrl === url) existing.add(node.topic);
    }
    if (!page.webhookSubscriptions.pageInfo.hasNextPage) break;
    after = page.webhookSubscriptions.pageInfo.endCursor;
  }

  let created = 0;
  let failures = 0;
  for (const topic of TOPICS) {
    if (existing.has(topic)) {
      console.log(`  already present  ${topic}`);
      continue;
    }
    const data = await graphql(ctx, CREATE, { topic, url });
    const errors = data.webhookSubscriptionCreate.userErrors;
    if (errors.length) {
      console.log(`  FAILED           ${topic} — ${errors.map((e) => e.message).join('; ')}`);
      failures += 1;
    } else {
      console.log(`  created          ${topic}`);
      created += 1;
    }
  }

  console.log(
    `\n${TOPICS.length} topics, ${existing.size} already present, ` +
      `${created} created, ${failures} failed\n-> ${url}`,
  );
  if (failures) process.exit(1);
}

main().catch((error) => {
  console.error(error.message ?? error);
  process.exit(1);
});
