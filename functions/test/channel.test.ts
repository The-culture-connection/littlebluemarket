import { strict as assert } from 'node:assert';
import { test } from 'node:test';

import { explainCheckoutError } from '../src/cart.ts';
import { variantAvailable } from '../src/catalog.ts';
import { pickAppPublication } from '../src/collections.ts';

/**
 * The two things that made "the merchandise does not exist" at checkout:
 * a product not on the app's channel, and a sold-out one the mirror thought
 * was buyable.
 */

test('the app sells through its headless channel, whatever it is called', () => {
  const pubs = [
    { id: 'gid://shopify/Publication/1', name: 'Online Store' },
    { id: 'gid://shopify/Publication/2', name: 'Point of Sale' },
    { id: 'gid://shopify/Publication/3', name: 'Little Blue Market Devtestingshop Headless' },
  ];
  assert.equal(pickAppPublication(pubs), 'gid://shopify/Publication/3');
  assert.equal(pickAppPublication(pubs.slice(0, 2)), null);
});

test('availability follows stock and policy when the payload has no flag', () => {
  assert.equal(variantAvailable({ available: false, inventory_quantity: 9 }), false);
  assert.equal(variantAvailable({ inventory_quantity: 0, inventory_policy: 'deny', inventory_management: 'shopify' }), false);
  assert.equal(variantAvailable({ inventory_quantity: 0, inventory_policy: 'continue', inventory_management: 'shopify' }), true);
  assert.equal(variantAvailable({ inventory_quantity: 0, inventory_management: null }), true);
  assert.equal(variantAvailable({ inventory_quantity: 3, inventory_policy: 'deny' }), true);
  assert.equal(variantAvailable({}), true);
});

test('a checkout refusal names the line, not the id', () => {
  const lines = [
    { id: 'a', productId: 'p', variantId: '58810940555424', title: 'test board', variantTitle: 'Default', unitPriceCents: 100, quantity: 1, sellerUid: 'kali' },
  ];
  assert.equal(
    explainCheckoutError('The merchandise with id gid://shopify/ProductVariant/58810940555424 does not exist.', lines),
    '"test board" is not available in the app\'s shop right now. Remove it from your cart and try again.',
  );
  assert.equal(explainCheckoutError('Something else went wrong', lines), 'Something else went wrong');
  assert.equal(explainCheckoutError(undefined, lines), 'Checkout failed.');
});
