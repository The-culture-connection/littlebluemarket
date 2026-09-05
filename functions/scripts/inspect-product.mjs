#!/usr/bin/env node
// Prints what the store holds for one product: vendor, status, tags,
// collections, variants and stock. Read-only. Prints no secret.
//
//   node scripts/inspect-product.mjs --id 15858572001440 [--project dev]
//   node scripts/inspect-product.mjs --tag lbm:5n1AiRWzNwRNmX4sLkpH
//   node scripts/inspect-product.mjs --vendors      # every distinct vendor string
import { adminGraphQL, arg, resolveProject, shopifyContext, hasFlag } from './lib/shopify-admin.mjs';

const projectId = resolveProject(arg('project', 'dev'));
const ctx = await shopifyContext(projectId, { allowSecretAccess: true });

const FIELDS = `
  id title vendor status productType tags handle createdAt
  collections(first: 20) { nodes { handle title } }
  variants(first: 5) { nodes { id title price sku inventoryQuantity inventoryItem { tracked } } }
  media(first: 5) { nodes { ... on MediaImage { image { url } status } } }
  metafield(namespace: "lbm", key: "draft_id") { value }
`;

if (hasFlag('vendors')) {
  const seen = new Map();
  let after = null;
  for (;;) {
    const data = await adminGraphQL(ctx, `query($after: String) { products(first: 250, after: $after) { pageInfo { hasNextPage endCursor } nodes { vendor status } } }`, { after });
    for (const p of data.products.nodes) {
      const row = seen.get(p.vendor) ?? { active: 0, draft: 0, other: 0 };
      row[p.status === 'ACTIVE' ? 'active' : p.status === 'DRAFT' ? 'draft' : 'other'] += 1;
      seen.set(p.vendor, row);
    }
    if (!data.products.pageInfo.hasNextPage) break;
    after = data.products.pageInfo.endCursor;
  }
  for (const [vendor, row] of [...seen].sort()) console.log(`${JSON.stringify(vendor).padEnd(40)} active ${row.active}  draft ${row.draft}  other ${row.other}`);
  process.exit(0);
}

const id = arg('id');
const tag = arg('tag');
let product;
if (id) {
  const data = await adminGraphQL(ctx, `query($id: ID!) { product(id: $id) { ${FIELDS} } }`, { id: `gid://shopify/Product/${id}` });
  product = data.product;
} else if (tag) {
  const data = await adminGraphQL(ctx, `query($q: String!) { products(first: 5, query: $q) { nodes { ${FIELDS} } } }`, { q: `tag:'${tag}'` });
  product = data.products.nodes[0];
  if (data.products.nodes.length > 1) console.log(`NOTE: ${data.products.nodes.length} products carry that tag`);
} else {
  console.error('pass --id <productId>, --tag <tag>, or --vendors');
  process.exit(2);
}
if (!product) { console.log('not found'); process.exit(1); }
console.log(JSON.stringify(product, null, 2));
