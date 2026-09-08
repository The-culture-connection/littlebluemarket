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
  if (!text.trim()) throw new Error(`WP ${res.status} ${path}: empty answer (a security plugin hides this endpoint)`);
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
  // WooCommerce's customers endpoint with role=all lists every WordPress
  // user and is what littlebluecart.com answers; core's wp/v2/users comes
  // back blank there (a security plugin). Same order as the app.
  let user = null;
  if (wcKey && wcSecret) {
    try {
      const { json } = await get('wc/v3/customers', { email, role: 'all', per_page: 20 }, basic(wcKey, wcSecret));
      const exact = (Array.isArray(json) ? json : []).filter((u) => String(u.email ?? '').toLowerCase() === email);
      if (exact.length === 1) {
        user = { id: exact[0].id, slug: exact[0].username, roles: [exact[0].role], registered_date: exact[0].date_created };
        line('wordpress user', `found via WooCommerce · id ${user.id} · login ${user.slug} · role ${user.roles[0] ?? '?'} · registered ${user.registered_date ?? '?'}`);
      } else if (exact.length > 1) {
        line('wordpress user', `${exact.length} users share this email: the app links neither (fix on the site, then retry)`);
      } else {
        line('wordpress user', 'none with exactly this email (WooCommerce customers, every role)');
      }
    } catch (error) {
      line('wordpress user', `WooCommerce lookup failed: ${error.message}`);
    }
  } else {
    line('wordpress user', 'skipped: WC_CONSUMER_KEY / WC_CONSUMER_SECRET not set (CP-D1)');
  }
  if (!user && appUser && appPassword) {
    try {
      const auth = basic(appUser, appPassword);
      const { json } = await get('wp/v2/users', { search: email, context: 'edit', per_page: 100 }, auth);
      const exact = (Array.isArray(json) ? json : []).filter((u) => String(u.email ?? '').toLowerCase() === email);
      if (exact.length === 1) {
        user = exact[0];
        line('wordpress user (core)', `found · id ${user.id} · login ${user.slug} · roles [${(user.roles ?? []).join(', ')}]`);
      } else {
        line('wordpress user (core)', `none (${Array.isArray(json) ? json.length : 0} loose hits)`);
      }
    } catch (error) {
      line('wordpress user (core)', `unavailable: ${error.message.slice(0, 120)} (expected on littlebluecart.com: the site hides this endpoint)`);
    }
  }
  if (user && appUser && appPassword) {
    // The site blanks ?author= queries, so walk the owner pages the way the
    // app does and pick this member's ids, then fetch those by id.
    const auth = basic(appUser, appPassword);
    const mine = [];
    let pages = 0;
    for (let page = 1; page <= 100; page++) {
      let res;
      try {
        res = await get('wp/v2/vendors_dir_ltg', { _fields: 'id,author,status', per_page: 100, page, status: 'publish,pending,draft,private,future' }, auth);
      } catch (error) {
        if (/WP 400 /.test(error.message) && page > 1) break;
        throw error;
      }
      pages++;
      for (const row of Array.isArray(res.json) ? res.json : []) if (Number(row.author) === Number(user.id)) mine.push(row.id);
      if (!Array.isArray(res.json) || res.json.length < 100) break;
    }
    line('directory listings', `${mine.length} for author ${user.id} (walked ${pages} page(s) of the owner index)`);
    if (mine.length) {
      const { json: listings } = await get('wp/v2/vendors_dir_ltg', { include: mine.slice(0, 100).join(','), status: 'publish,pending,draft,private,future', context: 'view', per_page: 100 }, auth);
      for (const l of Array.isArray(listings) ? listings : []) {
        const plan = l.drts_fields?.payment_plan;
        const planName = Array.isArray(plan) ? plan[0]?.plan_name : plan?.plan_name;
        const desc = l.yoast_head_json?.og_description ? 'yes' : 'no';
        line(`  #${l.id}`, `${l.status} · "${l.title?.rendered ?? ''}" · plan ${planName ?? '?'} · description ${desc} · image ${l.featured_media ? 'featured' : 'none'} · fields [${Object.keys(l.drts_fields ?? {}).join(', ') || 'none'}] · cat ${JSON.stringify(l.vendors_dir_cat)} tag ${JSON.stringify(l.vendors_dir_tag)} loc ${JSON.stringify(l.vendors_loc_loc)}`);
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
