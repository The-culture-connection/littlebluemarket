#!/usr/bin/env node
//
// Replays a Shopify order into the deployed `shopifyWebhook`, signed exactly
// as Shopify would sign it. Two uses:
//
//   1. The idempotency test (M2): replay the same order twice and confirm the
//      second says `duplicate` and no counter moved.
//   2. Recovery: an order whose webhook never arrived can be pushed by hand.
//
//   npm run replay-order -- --order 1001          # the order number, or its id
//   npm run replay-order -- --order 1001 --topic orders/paid
//
// The client secret is read into memory through the Firebase CLI and used
// only to compute the HMAC. Nothing secret is printed.

import * as crypto from 'node:crypto';

import {
  adminGraphQL,
  arg,
  defaultWebhookUrl,
  resolveProject,
  secretValue,
  shopifyContext,
} from './lib/shopify-admin.mjs';

const projectId = resolveProject(arg('project', 'dev'));
const wanted = arg('order');
const topic = arg('topic', 'orders/paid');
if (!wanted) {
  console.error('Usage: npm run replay-order -- --order <number or id>');
  process.exit(1);
}

const ctx = await shopifyContext(projectId, { allowSecretAccess: true });

// Find the order by number ("#1001", "1001") or by id.
const q = /^\d{5,}$/.test(wanted) ? `id:${wanted}` : `name:#${wanted.replace(/^#/, '')}`;
const data = await adminGraphQL(ctx, `
  query Order($q: String!) {
    orders(first: 1, query: $q) {
      nodes {
        id name createdAt displayFinancialStatus
        email
        totalPriceSet { shopMoney { amount } }
        customAttributes { key value }
        lineItems(first: 50) {
          nodes {
            id title quantity vendor
            variant { id title price }
            product { id }
            customAttributes { key value }
          }
        }
      }
    }
  }`, { q });

const order = data.orders.nodes[0];
if (!order) {
  console.error(`No order matched "${wanted}" on ${ctx.domain}.`);
  process.exit(1);
}

const tail = (gid) => gid.split('/').pop();

// The REST-shaped payload `normalizeOrder` reads (id, name, created_at,
// financial_status, total_price, email, note_attributes, line_items[]).
const payload = {
  id: Number(tail(order.id)),
  name: order.name,
  created_at: order.createdAt,
  financial_status: String(order.displayFinancialStatus ?? 'paid').toLowerCase(),
  total_price: order.totalPriceSet?.shopMoney?.amount ?? '0',
  email: order.email ?? null,
  note_attributes: (order.customAttributes ?? []).map((a) => ({ name: a.key, value: a.value })),
  line_items: order.lineItems.nodes.map((line) => ({
    id: Number(tail(line.id)),
    product_id: line.product ? Number(tail(line.product.id)) : null,
    variant_id: line.variant ? Number(tail(line.variant.id)) : null,
    title: line.title,
    variant_title: line.variant?.title ?? '',
    price: line.variant?.price ?? '0',
    quantity: line.quantity,
    vendor: line.vendor ?? '',
    properties: (line.customAttributes ?? []).map((a) => ({ name: a.key, value: a.value })),
  })),
};

const body = JSON.stringify(payload);
const secret = process.env.SHOPIFY_CLIENT_SECRET || secretValue('SHOPIFY_CLIENT_SECRET', projectId);
const hmac = crypto.createHmac('sha256', secret).update(body, 'utf8').digest('base64');
const url = arg('url', defaultWebhookUrl(projectId));

console.log(`Replaying ${order.name} (${payload.line_items.length} line(s), ${payload.financial_status}, app_uid ${payload.note_attributes.find((a) => a.name === 'app_uid')?.value ?? 'none'}) as ${topic}\n  -> ${url}`);
const response = await fetch(url, {
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
    'X-Shopify-Topic': topic,
    'X-Shopify-Hmac-Sha256': hmac,
    'X-Shopify-Shop-Domain': ctx.domain,
  },
  body,
});
const text = await response.text();
console.log(`HTTP ${response.status} ${text}`);
console.log(
  response.ok
    ? 'The function answered. Its log line says "recorded" the first time and "duplicate" on a replay:\n  firebase functions:log --only shopifyWebhook --project dev | tail -5'
    : 'The function refused. A 401 means the secret used to sign does not match the deployed SHOPIFY_CLIENT_SECRET.',
);
