// Shared helpers for the operator scripts (doctor, register-webhooks,
// touch-products, replay-order, probes).
//
// Deliberately standalone: none of this imports the compiled functions,
// because `adminGraphQL` in src/ mints its token through Firestore and expects
// to be running inside the Functions runtime. Same client-credentials grant,
// no Firebase Admin SDK, no service-account key.
//
// Secrets are never read from a file. They come from the environment, or,
// for the doctor only, from `firebase functions:secrets:access`, held in
// memory and never printed.

import { spawnSync } from 'node:child_process';
import { existsSync, readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
export const FUNCTIONS_DIR = join(HERE, '..', '..');
export const REPO_DIR = join(FUNCTIONS_DIR, '..');

// ------------------------------------------------------------------ argv

export function arg(name, fallback) {
  const i = process.argv.indexOf(`--${name}`);
  if (i === -1) return fallback;
  const next = process.argv[i + 1];
  return next === undefined || next.startsWith('--') ? fallback : next;
}

export function hasFlag(name) {
  return process.argv.includes(`--${name}`);
}

// --------------------------------------------------------------- project

/** `dev` becomes `little-blue-610e5` via .firebaserc. A project id passes through. */
export function resolveProject(aliasOrId = 'dev') {
  const rc = join(REPO_DIR, '.firebaserc');
  if (existsSync(rc)) {
    try {
      const projects = JSON.parse(readFileSync(rc, 'utf8')).projects ?? {};
      if (projects[aliasOrId]) return projects[aliasOrId];
    } catch {
      // A broken .firebaserc is reported by the doctor, not here.
    }
  }
  return aliasOrId;
}

/**
 * Non-secret params from `functions/.env.<project-id>`, which is where
 * Firebase keeps them. The environment wins, so a one-off run can override.
 */
export function loadParams(projectId) {
  const out = {};
  const file = join(FUNCTIONS_DIR, `.env.${projectId}`);
  const exists = existsSync(file);
  if (exists) {
    for (const line of readFileSync(file, 'utf8').split('\n')) {
      const match = line.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*)$/);
      if (match && match[2].trim()) {
        out[match[1]] = match[2].trim().replace(/^"(.*)"$/, '$1');
      }
    }
  }
  return { ...out, ...process.env, _envFile: file, _envFileExists: exists };
}

// ---------------------------------------------------------- firebase cli

/** Quotes one shell argument when it needs it. */
export function shellQuote(value) {
  return /^[w.:/@=-]+$/.test(value) ? value : `"${String(value).replace(/"/g, '\\"')}"`;
}

/** Runs one command line through the shell (so .cmd/.bat shims resolve on Windows). */
export function shellRun(cmd, args = []) {
  const line = [cmd, ...args.map(shellQuote)].join(' ');
  const result = spawnSync(line, {
    shell: true,
    encoding: 'utf8',
    windowsHide: true,
    maxBuffer: 16 * 1024 * 1024,
  });
  return {
    ok: result.status === 0,
    stdout: result.stdout ?? '',
    stderr: result.stderr ?? '',
  };
}

export function firebaseCli(args) {
  return shellRun('firebase', args);
}

/**
 * Reads a secret's value into memory through the CLI. The caller must never
 * log it. Returns '' when the secret is missing or the CLI fails.
 */
export function secretValue(name, projectId) {
  const { ok, stdout } = firebaseCli([
    'functions:secrets:access',
    name,
    '--project',
    projectId,
  ]);
  if (!ok) return '';
  const lines = stdout
    .split(/\r?\n/)
    .map((l) => l.trim())
    .filter(Boolean);
  return lines.at(-1) ?? '';
}

/** Metadata only: does the secret exist and have an enabled version? */
export function secretExists(name, projectId) {
  const { ok, stdout } = firebaseCli([
    'functions:secrets:get',
    name,
    '--project',
    projectId,
  ]);
  return ok && /ENABLED/i.test(stdout);
}

/** Names of the functions currently deployed to the project, or null on failure. */
export function deployedFunctions(projectId) {
  const { ok, stdout } = firebaseCli([
    'functions:list',
    '--project',
    projectId,
    '--json',
  ]);
  if (!ok) return null;
  try {
    const start = stdout.indexOf('{');
    const parsed = JSON.parse(stdout.slice(start));
    const rows = Array.isArray(parsed.result) ? parsed.result : [];
    const names = rows.map((r) => r.id ?? r.name ?? '').filter(Boolean);
    if (names.length) return names;
  } catch {
    // fall through to scraping the table
  }
  return [...stdout.matchAll(/([A-Za-z][A-Za-z0-9]+)\s*\W+\s*v2\s/g)].map(
    (m) => m[1],
  );
}

/** Every `export const name = …` in src/index.ts. */
export function exportedFunctions() {
  const src = readFileSync(join(FUNCTIONS_DIR, 'src', 'index.ts'), 'utf8');
  return [...src.matchAll(/^export const (\w+)\s*=/gm)].map((m) => m[1]);
}

export function functionUrl(projectId, name, region = 'us-central1') {
  return `https://${region}-${projectId}.cloudfunctions.net/${name}`;
}

export function defaultWebhookUrl(projectId, region = 'us-central1') {
  return functionUrl(projectId, 'shopifyWebhook', region);
}

// ---------------------------------------------------------------- shopify

/** A short-lived Admin token, the same grant `src/shopify/token.ts` uses. */
export async function mintAdminToken({ domain, clientId, clientSecret }) {
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
      `Could not mint an Admin token (HTTP ${response.status}) for ${domain}. ` +
        'Either SHOPIFY_CLIENT_ID / SHOPIFY_CLIENT_SECRET are wrong, or the app ' +
        'is not installed on that store. Fix: install the app on the store in ' +
        'the Shopify Dev Dashboard, then re-set the secret with ' +
        'firebase functions:secrets:set SHOPIFY_CLIENT_SECRET --project dev',
    );
  }
  const body = await response.json();
  if (!body.access_token) throw new Error('No access_token in the grant response');
  return body.access_token;
}

export async function adminGraphQL({ domain, version, token }, query, variables = {}) {
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
  if (!response.ok) {
    throw new Error(
      `Admin API returned HTTP ${response.status} for ${domain} (API ${version}). ` +
        'A 404 or 301 usually means SHOPIFY_STORE_DOMAIN is wrong in ' +
        'functions/.env.<project-id>.',
    );
  }
  const body = await response.json();
  if (body.errors) {
    throw new Error(`Admin API: ${body.errors.map((e) => e.message ?? e).join('; ')}`);
  }
  return body.data;
}

export async function storefrontGraphQL({ domain, version, token }, query, variables = {}) {
  const response = await fetch(`https://${domain}/api/${version}/graphql.json`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Shopify-Storefront-Private-Token': token,
    },
    body: JSON.stringify({ query, variables }),
  });
  if (!response.ok) {
    throw new Error(
      `Storefront API returned HTTP ${response.status} for ${domain}. A 401 means ` +
        'SHOPIFY_STOREFRONT_PRIVATE_TOKEN is wrong: ' +
        'firebase functions:secrets:set SHOPIFY_STOREFRONT_PRIVATE_TOKEN --project dev',
    );
  }
  const body = await response.json();
  if (body.errors?.length) {
    throw new Error(`Storefront API: ${body.errors.map((e) => e.message).join('; ')}`);
  }
  return body.data;
}

/** The topics `shopifyWebhook` handles. Keep in sync with src/index.ts. */
export const WEBHOOK_TOPICS = [
  'PRODUCTS_CREATE',
  'PRODUCTS_UPDATE',
  'PRODUCTS_DELETE',
  'ORDERS_PAID',
  'FULFILLMENTS_CREATE',
  'FULFILLMENTS_UPDATE',
];

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

/** Every subscription on the store, plus the set of topics pointed at `url`. */
export async function listWebhookSubscriptions(ctx, url) {
  const all = [];
  let after = null;
  for (;;) {
    const page = await adminGraphQL(ctx, EXISTING, { after });
    all.push(...page.webhookSubscriptions.nodes);
    if (!page.webhookSubscriptions.pageInfo.hasNextPage) break;
    after = page.webhookSubscriptions.pageInfo.endCursor;
  }
  const atUrl = new Set(
    all.filter((n) => n.endpoint?.callbackUrl === url).map((n) => n.topic),
  );
  return { all, atUrl, missing: WEBHOOK_TOPICS.filter((t) => !atUrl.has(t)) };
}

/**
 * Builds the Shopify context for a script: params from .env, the client
 * secret from the environment or (opt-in) from Secret Manager via the CLI.
 */
export async function shopifyContext(projectId, { allowSecretAccess = false } = {}) {
  const params = loadParams(projectId);
  const domain = params.SHOPIFY_STORE_DOMAIN;
  const clientId = params.SHOPIFY_CLIENT_ID;
  const version = params.SHOPIFY_API_VERSION ?? '2026-07';
  let clientSecret = params.SHOPIFY_CLIENT_SECRET;
  if (!clientSecret && allowSecretAccess) {
    clientSecret = secretValue('SHOPIFY_CLIENT_SECRET', projectId);
  }
  const missing = [
    !domain && 'SHOPIFY_STORE_DOMAIN',
    !clientId && 'SHOPIFY_CLIENT_ID',
    !clientSecret && 'SHOPIFY_CLIENT_SECRET',
  ].filter(Boolean);
  if (missing.length) {
    throw new Error(
      `Missing: ${missing.join(', ')}. Params live in functions/.env.${projectId}; ` +
        'the client secret comes from the SHOPIFY_CLIENT_SECRET environment variable ' +
        'or, for the doctor, from Secret Manager.',
    );
  }
  const token = await mintAdminToken({ domain, clientId, clientSecret });
  return { domain, version, token, clientId };
}

// ---------------------------------------------------------------- firebase

/** The public Web API key from lib/firebase_options.dart (public by design). */
export function firebaseApiKey() {
  const file = join(REPO_DIR, 'lib', 'firebase_options.dart');
  if (!existsSync(file)) return null;
  const match = readFileSync(file, 'utf8').match(/apiKey:\s*'([^']+)'/);
  return match ? match[1] : null;
}

const IDENTITY = 'https://identitytoolkit.googleapis.com/v1';

/** Signs up a throwaway account. Returns { idToken, localId } or { error }. */
export async function identitySignUp(apiKey, body) {
  const response = await fetch(`${IDENTITY}/accounts:signUp?key=${apiKey}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ returnSecureToken: true, ...body }),
  });
  const json = await response.json();
  if (!response.ok) return { error: json.error?.message ?? `HTTP ${response.status}` };
  return { idToken: json.idToken, localId: json.localId };
}

export async function identityDelete(apiKey, idToken) {
  await fetch(`${IDENTITY}/accounts:delete?key=${apiKey}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ idToken }),
  }).catch(() => {});
}

/** Counts documents in a top-level collection through the Firestore REST API. */
export async function countCollection(projectId, idToken, collection) {
  const url =
    `https://firestore.googleapis.com/v1/projects/${projectId}` +
    '/databases/(default)/documents:runAggregationQuery';
  const response = await fetch(url, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${idToken}`,
    },
    body: JSON.stringify({
      structuredAggregationQuery: {
        structuredQuery: { from: [{ collectionId: collection }] },
        aggregations: [{ alias: 'n', count: {} }],
      },
    }),
  });
  if (!response.ok) {
    const text = await response.text();
    throw new Error(
      `Firestore count of ${collection} failed: HTTP ${response.status} ${text.slice(0, 160)}`,
    );
  }
  const rows = await response.json();
  const value = rows?.[0]?.result?.aggregateFields?.n?.integerValue;
  return Number(value ?? 0);
}

/** Calls a deployed `onCall` function over HTTPS with a Firebase ID token. */
export async function callFunction(projectId, name, idToken, data = {}) {
  const response = await fetch(functionUrl(projectId, name), {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${idToken}`,
    },
    body: JSON.stringify({ data }),
  });
  const json = await response.json().catch(() => ({}));
  if (!response.ok) {
    const err = json.error ?? {};
    throw new Error(`${name}: ${err.status ?? response.status} ${err.message ?? ''}`.trim());
  }
  return json.result;
}
