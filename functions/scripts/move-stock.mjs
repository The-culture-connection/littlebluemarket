#!/usr/bin/env node
// Moves a vendor's stock to one location.
//
//   node scripts/move-stock.mjs --vendor cc --to 121092407456 [--project dev] [--dry]
//
// For every variant of the vendor's products whose stock sits at another
// location: activate the item at the target with the same available count,
// then deactivate the old level. Prints what it did; changes nothing with
// --dry. Needs write_inventory (granted).
import { randomUUID } from 'node:crypto';

import { adminGraphQL, arg, hasFlag, resolveProject, shopifyContext } from './lib/shopify-admin.mjs';

// Every inventory mutation on 2026-07 must carry an @idempotent key on the field.
const idem = () => '@idempotent(key: "' + randomUUID() + '")';

const projectId = resolveProject(arg('project', 'dev'));
const vendor = arg('vendor');
const to = arg('to');
const dry = hasFlag('dry');
if (!vendor || !to) {
  console.error('Usage: node scripts/move-stock.mjs --vendor <vendor string> --to <location id> [--dry]');
  process.exit(2);
}
const target = to.startsWith('gid://') ? to : `gid://shopify/Location/${to}`;
const ctx = await shopifyContext(projectId, { allowSecretAccess: true });

const data = await adminGraphQL(ctx, `query($q: String!) {
  products(first: 50, query: $q) {
    nodes {
      title
      variants(first: 50) {
        nodes {
          id title
          inventoryItem { id inventoryLevels(first: 10) { nodes { id location { id } quantities(names: ["available"]) { quantity } } } }
        }
      }
    }
  }
}`, { q: `vendor:'${vendor.replace(/'/g, "\\'")}'` });

let moved = 0;
for (const product of data.products.nodes) {
  for (const variant of product.variants.nodes) {
    const levels = variant.inventoryItem.inventoryLevels.nodes;
    const atTarget = levels.find((l) => l.location.id === target);
    const elsewhere = levels.filter((l) => l.location.id !== target);
    if (elsewhere.length === 0) {
      console.log(`  ok      ${product.title} / ${variant.title}: already at the target only`);
      continue;
    }
    const available = elsewhere.reduce((sum, l) => sum + (l.quantities[0]?.quantity ?? 0), 0)
      + (atTarget?.quantities[0]?.quantity ?? 0);
    console.log(`  ${dry ? 'would move' : 'moving'} ${product.title} / ${variant.title}: ${available} available -> ${to}${atTarget ? ' (already stocked there)' : ''}`);
    if (dry) continue;

    if (atTarget) {
      const r = await adminGraphQL(ctx, `mutation($input: InventorySetQuantitiesInput!) {
        inventorySetQuantities(input: $input) ${idem()} { userErrors { message } }
      }`, { input: { name: 'available', reason: 'correction', quantities: [{ inventoryItemId: variant.inventoryItem.id, locationId: target, quantity: available, changeFromQuantity: atTarget.quantities[0]?.quantity ?? 0 }] } });
      if (r.inventorySetQuantities.userErrors.length) throw new Error(JSON.stringify(r.inventorySetQuantities.userErrors));
    } else {
      const r = await adminGraphQL(ctx, `mutation($item: ID!, $loc: ID!, $available: Int) {
        inventoryActivate(inventoryItemId: $item, locationId: $loc, available: $available) ${idem()} { userErrors { message } }
      }`, { item: variant.inventoryItem.id, loc: target, available });
      if (r.inventoryActivate.userErrors.length) throw new Error(JSON.stringify(r.inventoryActivate.userErrors));
    }
    for (const level of elsewhere) {
      const r = await adminGraphQL(ctx, `mutation($id: ID!) { inventoryDeactivate(inventoryLevelId: $id) ${idem()} { userErrors { message } } }`, { id: level.id });
      if (r.inventoryDeactivate.userErrors.length) console.log(`    (could not deactivate old level: ${r.inventoryDeactivate.userErrors.map((e) => e.message).join('; ')})`);
    }
    moved += 1;
  }
}
console.log(`\n${dry ? 'Would move' : 'Moved'} ${moved} variant(s) to location ${to}.`);
