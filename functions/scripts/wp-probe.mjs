#!/usr/bin/env node
//
// What littlebluecart.com (its staging copy, on the dev project) knows about
// one email address, as the app's own lookups would see it:
//
//   npm run wp:probe -- --email grace-s+dir1@the-culture-connection.com
//
// Prints ids, counts, statuses and field names. Never a secret, never anyone
// else's email. This is the block Grace pastes when the Directory screen
// disagrees with the website.

import { arg, loadParams, resolveProject, secretValue } from './lib/shopify-admin.mjs';

const projectId = resolveProject(arg('project', 'dev'));
const email = String(arg('email', '')).trim().toLowerCase();
if (!email) {
  console.error('usage: npm run wp:probe -- --email <address>');
  process.exit(2);
}
const params = loadParams(projectId);
const base = String(params.WP_BASE_URL ?? '').trim().replace(/\/+$/, '');
if (!base) {
  console.error('WP_BASE_URL is empty in functions/.env.' + projectId + ' (CP-D0)');
  process.exit(1);
}
const appUser = String(params.WP_APP_USER ?? '').trim();
const appPassword = process.env.WP_APP_PASSWORD || secretValue('WP_APP_PASSWORD', projectId);
const wcKey = process.env.WC_CONSUMER_KEY || secretValue('WC_CONSUMER_KEY', projectId);
const wcSecret = process.env.WC_CONSUMER_SECRET || secretValue('WC_CONSUMER_SECRET', projectId);

const basic = (u, p) => `Basic ${Buffer.from(`${u}:${p}`, 'utf8').toString('base64')}`;

async function get(path, query, authorization) {
  const url = new URL(`${base}/wp-json/${path}`);
  for (const [k, v] of Object.entries(query ?? {})) if (v !== undefined) url.searchParams.set(k, String(v));
  const headers = { accept: 'application/json' };
  if (authorization) headers.authorization = authorization;
  const res = await fetch(url, { headers, redirect: 'follow' });
  const text = await res.text();
  if (!res.ok) {
    let hint = text.slice(0, 120);
    try {
      const j = JSON.parse(text);
      if (j && (j.code || j.message)) hint = `${j.code ?? ''} ${j.message ?? ''}`.trim();
    } catch { /* not JSON */ }
    throw new Error(`WP ${res.status} ${path}: ${hint}`);
  }
  return { json: JSON.parse(text), total: res.headers.get('x-wp-total') };
}

function line(label, value) {
  console.log(`${label.padEnd(22)} ${value}`);
}

async function main() {
  console.log(`LBM wp-probe · ${new URL(base).host} · ${email}\n`);
  const site = await get('', {});
  line('site', `${site.json.name ?? '?'} · wp/v2 ${site.json.namespaces?.includes('wp/v2') ? 'yes' : 'NO'} · wc/v3 ${site.json.namespaces?.includes('wc/v3') ? 'yes' : 'NO'}`);

  // WordPress member ---------------------------------------------------------
  let user = null;
  if (!appUser || !appPassword) {
    line('wordpress user', 'skipped: WP_APP_USER or WP_APP_PASSWORD not set (CP-D1)');
  } else {
    const auth = basic(appUser, appPassword);
    const { json } = await get('wp/v2/users', { search: email, context: 'edit', per_page: 100 }, auth);
    const exact = (Array.isArray(json) ? json : []).filter((u) => String(u.email ?? '').toLowerCase() === email);
    if (exact.length === 1) {
      user = exact[0];
      line('wordpress user', `found · id ${user.id} · login ${user.slug} · roles [${(user.roles ?? []).join(', ')}] · registered ${user.registered_date ?? '?'}`);
    } else if (exact.length > 1) {
      line('wordpress user', `${exact.length} users share this email: the app links neither (fix on the site, then retry)`);
    } else {
      line('wordpress user', `none with exactly this email (${Array.isArray(json) ? json.length : 0} loose search hits ignored)`);
    }
    if (user) {
      const { json: listings } = await get('wp/v2/vendors_dir_ltg', { author: user.id, status: 'publish,pending,draft,private,future', context: 'view', per_page: 50 }, auth);
      const arr = Array.isArray(listings) ? listings : [];
      line('directory listings', `${arr.length} for author ${user.id}`);
      for (const l of arr) {
        const plan = l.drts_fields?.payment_plan;
        const planName = Array.isArray(plan) ? plan[0]?.plan_name : plan?.plan_name;
        line(`  #${l.id}`, `${l.status} · "${l.title?.rendered ?? ''}" · plan ${planName ?? '?'} · fields [${Object.keys(l.drts_fields ?? {}).join(', ')}]`);
      }
      if (!arr.length) {
        const { json: pub } = await get('wp/v2/vendors_dir_ltg', { author: user.id, per_page: 5 });
        line('  public check', `${Array.isArray(pub) ? pub.length : 0} published listings visible without a password`);
      }
    }
  }

  // WooCommerce -------------------------------------------------------------
  if (!wcKey || !wcSecret) {
    line('woocommerce', 'skipped: WC_CONSUMER_KEY / WC_CONSUMER_SECRET not set (CP-D1)');
  } else {
    const auth = basic(wcKey, wcSecret);
    const { json: customers } = await get('wc/v3/customers', { email, per_page: 10 }, auth);
    const c = Array.isArray(customers) ? customers.find((x) => String(x.email ?? '').toLowerCase() === email) : null;
    if (c) {
      line('woocommerce customer', `id ${c.id} · orders_count ${c.orders_count ?? '?'} · total_spent ${c.total_spent ?? '?'}`);
      const { json: orders, total } = await get('wc/v3/orders', { customer: c.id, per_page: 100 }, auth);
      const arr = Array.isArray(orders) ? orders : [];
      line('orders by customer', `${total ?? arr.length}: ${arr.map((o) => `#${o.number} ${o.status} ${o.total}`).join(' · ') || '(none)'}`);
    } else {
      line('woocommerce customer', 'none with this email (guest checkouts have no customer record)');
    }
    const { json: byEmail } = await get('wc/v3/orders', { search: email, per_page: 100 }, auth);
    const guest = (Array.isArray(byEmail) ? byEmail : []).filter((o) => String(o.billing?.email ?? '').toLowerCase() === email);
    line('orders by billing email', `${guest.length}: ${guest.map((o) => `#${o.number} ${o.status} ${o.total}${o.customer_id ? '' : ' (guest)'}`).join(' · ') || '(none)'}`);
  }
  console.log('\nPaste this whole block to Claude with the checkpoint step.');
}

main().catch((error) => {
  console.error(`\nwp-probe failed: ${error.message}`);
  console.error('Paste this to Claude.');
  process.exit(1);
});
