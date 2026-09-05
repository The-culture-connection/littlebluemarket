#!/usr/bin/env node
// What Shipturtle knows: its vendor users, and which Shopify vendor string
// each vendor's products carry. Read-only; prints no secret.
//
//   node scripts/shipturtle-vendors.mjs [--project dev] [--title "Fall Crewneck"]
import { arg, loadParams, resolveProject, secretValue } from './lib/shopify-admin.mjs';

const projectId = resolveProject(arg('project', 'dev'));
const params = loadParams(projectId);
const base = (params.SHIPTURTLE_BASE_URL ?? 'https://api-v2.shipturtle.com').replace(/\/$/, '');
const token = process.env.SHIPTURTLE_API_KEY || secretValue('SHIPTURTLE_API_KEY', projectId);
if (!token) {
  console.error('No SHIPTURTLE_API_KEY (env or Secret Manager).');
  process.exit(2);
}
const headers = { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' };

async function call(method, path, body) {
  const res = await fetch(`${base}${path}`, { method, headers, body: body ? JSON.stringify(body) : undefined });
  const text = await res.text();
  let json;
  try { json = JSON.parse(text); } catch { json = null; }
  return { status: res.status, json, text };
}

const users = await call('GET', '/api/v1/users');
console.log(`users: HTTP ${users.status}`);
const rows = Array.isArray(users.json?.data) ? users.json.data : [];
for (const u of rows) {
  console.log(`  company ${String(u.company_id).padEnd(6)} ${String(u.type ?? '').padEnd(8)} ${String(u.name ?? '').padEnd(28)} ${u.email ?? ''}${u.is_master ? '  (master)' : ''}`);
}

const products = await call('POST', '/api/v3/fetch-product-data/parent', { start: 0, length: 500 });
console.log(`\nproducts: HTTP ${products.status} · ${products.json?.recordsTotal ?? '?'} total`);
const list = Array.isArray(products.json?.data) ? products.json.data : [];
const byCompany = new Map();
for (const p of list) {
  const key = `${p.company_id}`;
  const row = byCompany.get(key) ?? { vendors: new Set(), count: 0, statuses: new Set() };
  row.vendors.add(p.vendor);
  row.statuses.add(p.status);
  row.count += 1;
  byCompany.set(key, row);
}
for (const [company, row] of [...byCompany].sort()) {
  console.log(`  company ${company.padEnd(6)} ${row.count} products · vendor strings ${JSON.stringify([...row.vendors])} · statuses ${JSON.stringify([...row.statuses])}`);
}

const title = arg('title');
if (title) {
  const hits = list.filter((p) => String(p.title ?? '').toLowerCase() === title.toLowerCase());
  console.log(`\n"${title}": ${hits.length ? JSON.stringify(hits.map((p) => ({ id: p.id, company_id: p.company_id, vendor: p.vendor, status: p.status, handle: p.handle })), null, 2) : 'not in Shipturtle'}`);
}
