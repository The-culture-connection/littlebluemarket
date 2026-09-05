#!/usr/bin/env node
//
// Re-saves products on the dev store with a no-op edit, so Shopify fires
// `products/update` for each and the catalog mirror fills through the real
// webhook path. Doubles as an end-to-end webhook test.
//
//   npm run touch-products                       # every product
//   npm run touch-products -- --vendor "Name"    # one vendor's products
//   npm run touch-products -- --limit 25
//
// Refuses to run against the production store.

import {
  adminGraphQL,
  arg,
  resolveProject,
  shopifyContext,
} from './lib/shopify-admin.mjs';

const PRODUCTION_DOMAIN = 'little-blue-cart-dev.myshopify.com';

const LIST = `
  query Products($q: String, $after: String, $first: Int!) {
    products(first: $first, query: $q, after: $after) {
      pageInfo { hasNextPage endCursor }
      nodes { id title vendor tags }
    }
  }
`;

const UPDATE = `
  mutation Touch($product: ProductUpdateInput!) {
    productUpdate(product: $product) {
      product { id }
      userErrors { field message }
    }
  }
`;

const UPDATE_LEGACY = `
  mutation TouchLegacy($input: ProductInput!) {
    productUpdate(input: $input) {
      product { id }
      userErrors { field message }
    }
  }
`;

async function main() {
  const projectId = resolveProject(arg('project', 'dev'));
  const vendor = arg('vendor');
  const limit = Number(arg('limit', '0')) || Infinity;

  const ctx = await shopifyContext(projectId, { allowSecretAccess: true });
  if (ctx.domain === PRODUCTION_DOMAIN) {
    throw new Error(`Refusing to touch every product on the PRODUCTION store (${ctx.domain}).`);
  }

  const q = vendor ? `vendor:'${vendor.replace(/'/g, "\'")}'` : null;
  const products = [];
  let after = null;
  while (products.length < limit) {
    const page = await adminGraphQL(ctx, LIST, {
      q,
      after,
      first: Math.min(50, limit === Infinity ? 50 : limit - products.length),
    });
    products.push(...page.products.nodes);
    if (!page.products.pageInfo.hasNextPage) break;
    after = page.products.pageInfo.endCursor;
  }

  console.log(`Store ${ctx.domain}: ${products.length} product(s)${vendor ? ` for vendor "${vendor}"` : ''}.`);
  let useLegacy = false;
  let touched = 0;
  for (const product of products) {
    const attempt = async () => {
      if (!useLegacy) {
        try {
          return await adminGraphQL(ctx, UPDATE, { product: { id: product.id, tags: product.tags } });
        } catch (error) {
          if (!/ProductUpdateInput|Unknown argument/.test(String(error.message))) throw error;
          useLegacy = true;
        }
      }
      return adminGraphQL(ctx, UPDATE_LEGACY, { input: { id: product.id, tags: product.tags } });
    };
    const data = await attempt();
    const errors = data.productUpdate.userErrors;
    if (errors.length) {
      console.log(`  FAILED  ${product.title} — ${errors.map((e) => e.message).join('; ')}`);
    } else {
      touched += 1;
      console.log(`  touched ${product.title}  (${product.vendor})`);
    }
  }
  console.log(
    `\nTouched ${touched} of ${products.length}. Shopify now sends products/update for each; ` +
      'give it ~30 s, then `npm run doctor` shows the catalog count (Firebase console → Firestore → catalog).',
  );
}

main().catch((error) => {
  console.error(`\ntouch-products failed: ${error.message ?? error}`);
  console.error('Paste this whole output to Claude.');
  process.exit(1);
});
