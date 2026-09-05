import {
  SHOPIFY_API_VERSION,
  SHOPIFY_STORE_DOMAIN,
  SHOPIFY_STOREFRONT_PRIVATE_TOKEN,
} from '../config.ts';

/**
 * The Storefront API — carts and checkout.
 *
 * Uses the *private* token even though a public one exists, because these calls
 * run server-side where the private token's higher rate limits and lack of
 * per-buyer throttling are what we want. Neither token ever reaches the app.
 *
 * Unlike the Admin token, this one does not expire on a 24-hour clock, so
 * there is no broker here — just a header.
 */
export async function storefrontGraphQL<T>(
  query: string,
  variables: Record<string, unknown> = {},
): Promise<T> {
  const domain = SHOPIFY_STORE_DOMAIN.value();
  const version = SHOPIFY_API_VERSION.value();

  const response = await fetch(
    `https://${domain}/api/${version}/graphql.json`,
    {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Shopify-Storefront-Private-Token':
          SHOPIFY_STOREFRONT_PRIVATE_TOKEN.value(),
      },
      body: JSON.stringify({ query, variables }),
    },
  );

  if (!response.ok) {
    throw new Error(
      `Storefront API returned HTTP ${response.status} for ${domain} (API ${version}). ` +
        'A 401 means SHOPIFY_STOREFRONT_PRIVATE_TOKEN is wrong: ' +
        'firebase functions:secrets:set SHOPIFY_STOREFRONT_PRIVATE_TOKEN --project dev. ' +
        'A 404 means SHOPIFY_STORE_DOMAIN is wrong in functions/.env.<project-id>.',
    );
  }

  const body = (await response.json()) as {
    data?: T;
    errors?: Array<{ message: string }>;
  };

  // GraphQL reports failures with a 200, so this is the real error check.
  if (body.errors?.length) {
    throw new Error(body.errors.map((e) => e.message).join('; '));
  }
  if (!body.data) throw new Error('Storefront API returned no data');
  return body.data;
}
