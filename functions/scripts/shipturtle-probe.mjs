#!/usr/bin/env node
//
// Finds out, loudly, what the stored Shipturtle token can reach.
//
//   npm run probe:shipturtle            # token read from Secret Manager via the CLI
//   SHIPTURTLE_API_KEY=... node scripts/shipturtle-probe.mjs
//   SHIPTURTLE_API_KEY_ORDER=... SHIPTURTLE_API_KEY_PRODUCT=... node scripts/shipturtle-probe.mjs
//
// Prints: what the token claims to be (a JWT's scopes and expiry, never the
// token), one row per (host, path, auth style) tried, and a verdict naming
// the endpoint that lists vendors — or the question to ask Shipturtle.
// Contains no secret, so the whole output can be pasted to Claude.

import { arg, loadParams, resolveProject, secretValue } from './lib/shopify-admin.mjs';

const projectId = resolveProject(arg('project', 'dev'));
const params = loadParams(projectId);

const tokens = [];
for (const name of ['SHIPTURTLE_API_KEY', 'SHIPTURTLE_API_KEY_ORDER', 'SHIPTURTLE_API_KEY_PRODUCT']) {
  if (process.env[name]) tokens.push({ name, value: process.env[name] });
}
if (tokens.length === 0) {
  const fromSecret = secretValue('SHIPTURTLE_API_KEY', projectId);
  if (fromSecret) tokens.push({ name: 'SHIPTURTLE_API_KEY (Secret Manager)', value: fromSecret });
}
if (tokens.length === 0) {
  console.error('No Shipturtle token found in the environment or Secret Manager.');
  process.exit(1);
}

const BASES = [...new Set([
  params.SHIPTURTLE_BASE_URL,
  'https://api-v2.shipturtle.com',
  'https://api.shipturtle.com',
].filter(Boolean).map((b) => b.replace(/\/$/, '')))];

const PATHS = [
  ['GET', '/api/v1/me'],
  ['GET', '/api/v1/vendors'],
  ['GET', '/api/v1/vendor'],
  ['GET', '/api/v1/vendor-list'],
  ['GET', '/api/v1/users'],
  ['GET', '/api/v1/company'],
  ['GET', '/api/v3/vendors'],
  ['GET', '/api/v1/orders?limit=1'],
  ['GET', '/api/v1/products?limit=1'],
  ['POST', '/api/v3/fetch-product-data/parent'],
  ['GET', '/v1/vendors'],
  ['GET', '/v1/orders?limit=1'],
];

const STYLES = ['Authorization', 'x-api-key', 'access-token'];

function decodeJwt(token) {
  const parts = token.split('.');
  if (parts.length !== 3) return null;
  try {
    return JSON.parse(Buffer.from(parts[1].replace(/-/g, '+').replace(/_/g, '/'), 'base64').toString('utf8'));
  } catch {
    return null;
  }
}

function headers(token, style) {
  const h = { Accept: 'application/json' };
  if (style === 'x-api-key') h['x-api-key'] = token;
  else if (style === 'access-token') h['access-token'] = token;
  else h.Authorization = `Bearer ${token}`;
  return h;
}

function summarize(body) {
  try {
    const json = JSON.parse(body);
    const keys = Array.isArray(json) ? `array[${json.length}]` : Object.keys(json).slice(0, 8).join(',');
    const arr = Array.isArray(json) ? json : json.data ?? json.vendors ?? json.items ?? null;
    const len = Array.isArray(arr) ? arr.length : null;
    const first = Array.isArray(arr) && arr[0] && typeof arr[0] === 'object' ? Object.keys(arr[0]).slice(0, 10).join(',') : '';
    return { json: true, keys, len, first };
  } catch {
    return { json: false, keys: '', len: null, first: '', text: body.slice(0, 120).replace(/\s+/g, ' ') };
  }
}

for (const token of tokens) {
  console.log(`\n=== ${token.name} ===`);
  const claims = decodeJwt(token.value);
  if (claims) {
    const exp = typeof claims.exp === 'number' ? new Date(claims.exp * 1000) : null;
    console.log(`JWT · sub ${claims.sub ?? '?'} · aud ${claims.aud ?? '?'} · scopes ${JSON.stringify(claims.scopes ?? [])} · expires ${exp?.toISOString() ?? '?'}${exp && exp < new Date() ? '  (EXPIRED)' : ''}`);
  } else {
    console.log(`opaque token (${token.value.length} chars, not a JWT)`);
  }

  const found = [];
  for (const base of BASES) {
    for (const [method, path] of PATHS) {
      for (const style of STYLES) {
        const url = `${base}${path}`;
        let line;
        try {
          const controller = new AbortController();
          const timer = setTimeout(() => controller.abort(), 10000);
          const res = await fetch(url, {
            method,
            headers: { ...headers(token.value, style), ...(method === 'POST' ? { 'Content-Type': 'application/json' } : {}) },
            body: method === 'POST' ? '{}' : undefined,
            signal: controller.signal,
          });
          clearTimeout(timer);
          const body = await res.text();
          const s = summarize(body);
          line = `${String(res.status).padEnd(4)} ${method.padEnd(4)} ${url.padEnd(58)} ${style.padEnd(13)} ${s.json ? `keys[${s.keys}]${s.len !== null ? ` n=${s.len}` : ''}${s.first ? ` first[${s.first}]` : ''}` : `non-json: ${s.text}`}`;
          if (res.ok && s.json && s.len !== null && /vendor|company|user/i.test(path + s.first)) {
            // A roster has emails; a product list does not. Rank by that first.
            const score = (/email/i.test(s.first) ? 1000 : 0) + (/company_id/.test(s.first) ? 100 : 0) + s.len;
            found.push({ base, path, style, count: s.len, first: s.first, score });
          }
          // A 401/403 on one style means the others are worth trying; a 404
          // on one style means the path is wrong for every style.
          if (res.status === 404) { console.log(line); break; }
        } catch (error) {
          line = `ERR  ${method.padEnd(4)} ${url.padEnd(58)} ${style.padEnd(13)} ${error.name === 'AbortError' ? 'timeout' : error.message}`;
        }
        console.log(line);
      }
    }
  }

  console.log('');
  if (found.length) {
    const best = found.sort((a, b) => b.score - a.score)[0];
    console.log(`ROSTER REACHABLE at ${best.base}${best.path} using ${best.style} · ${best.count} row(s) · fields [${best.first}]`);
    console.log(`Set in functions/.env.${projectId}:\n  SHIPTURTLE_BASE_URL=${best.base}\n  SHIPTURTLE_VENDORS_PATH=${best.path}\n  SHIPTURTLE_AUTH_HEADER=${best.style}\nthen redeploy.`);
  } else {
    console.log('NO ROSTER ENDPOINT FOUND with this token. Ask team@shipturtle.com:');
    console.log('  "Which Open API endpoint lists the merchant\'s vendors and their user emails, and which header carries the token?"');
    console.log('Vendor linking keeps working through claim codes in the meantime.');
  }
}
