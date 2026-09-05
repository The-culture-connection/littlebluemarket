import { logger } from 'firebase-functions';

import { SHOPIFY_LOCATION_ID } from './config.ts';
import type { GraphQL } from './listings.ts';

/**
 * Where a seller's stock goes.
 *
 * Shopify counts a variant as sellable online only at locations that fulfil
 * online orders. The dev store has three locations, and the API lists a
 * secondary one first; opening stock written there made every app product
 * read "sold out" at checkout while showing plenty in the admin.
 *
 * Three ways to know the right location, in order:
 *  1. `SHOPIFY_LOCATION_ID` in the env, set once by a person who looked.
 *  2. The store's own answer (`fulfillsOnlineOrders`), which needs the
 *     `read_locations` scope.
 *  3. The location most of the store's existing stock already sits at,
 *     which needs no scope and is the merchant's real warehouse in every
 *     store that has one.
 */

export interface LocationCandidate {
  id: string;
  fulfillsOnlineOrders?: boolean | null;
  /** How many existing variants keep stock here. */
  weight?: number;
}

/** Pure: the best location among what we could learn. */
export function pickStockLocation(candidates: LocationCandidate[]): string | null {
  if (candidates.length === 0) return null;
  const online = candidates.filter((c) => c.fulfillsOnlineOrders === true);
  const pool = online.length ? online : candidates;
  return [...pool].sort((a, b) => (b.weight ?? 0) - (a.weight ?? 0))[0]?.id ?? null;
}

const gid = (id: string) =>
  id.startsWith('gid://') ? id : `gid://shopify/Location/${id}`;

let cached: string | null | undefined;

export async function stockLocationId(graphql: GraphQL): Promise<string | null> {
  const configured = SHOPIFY_LOCATION_ID.value().trim();
  if (configured) return gid(configured);
  if (cached !== undefined) return cached;

  // 2. Ask the store which locations fulfil online orders.
  try {
    const data = await graphql<{
      locations: { nodes: Array<{ id: string; fulfillsOnlineOrders: boolean }> };
    }>(`{ locations(first: 20, query: "active:true") { nodes { id fulfillsOnlineOrders } } }`);
    const picked = pickStockLocation(data.locations.nodes);
    if (picked) {
      cached = picked;
      return picked;
    }
  } catch (error) {
    logger.info('Locations are not readable (read_locations not granted); inferring from stock', {
      error: String(error).slice(0, 120),
    });
  }

  // 3. Follow the store's existing stock.
  try {
    const data = await graphql<{
      products: {
        nodes: Array<{
          variants: {
            nodes: Array<{
              inventoryItem: { inventoryLevels: { nodes: Array<{ location: { id: string } }> } };
            }>;
          };
        }>;
      };
    }>(
      `{ products(first: 50, query: "status:active") {
        nodes { variants(first: 1) { nodes { inventoryItem { inventoryLevels(first: 5) { nodes { location { id } } } } } } }
      } }`,
    );
    const weights = new Map<string, number>();
    for (const p of data.products.nodes) {
      for (const v of p.variants.nodes) {
        for (const level of v.inventoryItem.inventoryLevels.nodes) {
          weights.set(level.location.id, (weights.get(level.location.id) ?? 0) + 1);
        }
      }
    }
    const picked = pickStockLocation([...weights].map(([id, weight]) => ({ id, weight })));
    cached = picked;
    if (picked) logger.info('Stock location inferred from existing stock', { locationId: picked });
    return picked;
  } catch (error) {
    logger.warn('Could not determine a stock location', { error: String(error).slice(0, 160) });
    cached = null;
    return null;
  }
}
