# Identity, catalog import, and attribution — verified against the live systems

Everything below was read off the running sites on 2026-09-04, not inferred from docs.

---

## 1. How buyers are authenticated (littlebluemarket.com)

**Shopify's new customer accounts. OAuth 2.0 / OIDC, passwordless. There is no password to verify
and no classic `/account/login` form behind it.**

`https://littlebluemarket.com/account/login` 302s straight to:

```
https://shopify.com/authentication/75519754395/login
  ?client_id=70322625-b2ee-4b3e-9b97-67a85062312d
  &redirect_uri=/authentication/75519754395/oauth/authorize
      ?response_type=code
      &scope=openid+email+customer-account-api:full
      &nonce=…&state=…
      &redirect_uri=https://shopify.com/75519754395/account/callback
```

Facts that matter:

| Thing | Value |
|---|---|
| Shop ID (the number in every Customer Account API URL) | `75519754395` |
| Store domain | `little-blue-cart-dev.myshopify.com` |
| Web storefront's OAuth client | `70322625-b2ee-4b3e-9b97-67a85062312d` |
| **Our app's Customer Account API client** | `3ccf2df0-6148-41a5-9ad3-3b15deda8d04` (already in `.env.littlebluemarket`) |
| Scopes | `openid email customer-account-api:full` |
| Grant | authorization code + PKCE |

The two client IDs being different is correct and expected — the online store authenticates with its
own client, the mobile app must use ours. Do not copy the storefront's client ID into the app.

The login screen offers an emailed code plus "More sign-in options" (Shop / passkey). The user never
types a password, so **there is no credential the app could collect and verify itself.** Any screen
in the app that asks for a Shopify password is unbuildable.

### Endpoints the app needs

```
authorize  https://shopify.com/authentication/75519754395/oauth/authorize
token      https://shopify.com/authentication/75519754395/oauth/token
logout     https://shopify.com/authentication/75519754395/logout
jwks       https://shopify.com/75519754395/.well-known/openid-configuration  (discovery)
graphql    https://shopify.com/75519754395/account/customer/api/2026-07/graphql
```

The redirect URI must be a **custom scheme** (e.g. `littlebluemarket://auth/callback`) registered in
the Shopify Dev Dashboard under the Customer Account API's "Application setup" → mobile/custom URI.
A Firebase Hosting `/api/auth/callback` URL works too but forces a browser round-trip on mobile;
the custom scheme is the one to register.

---

## 2. How sellers are authenticated (vendors.littlebluemarket.com)

**They are not Shopify accounts at all.** `vendors.littlebluemarket.com` is Shipturtle's white-labelled
vendor panel (a Vue/Vuetify SPA), and it authenticates against Shipturtle's own backend:

- API base: `https://api-v2.shipturtle.com/api/v1/` and `/api/v3/`
- Auth: `Authorization: Bearer <JWT>`, Laravel Passport-shaped (`aud`, `jti`, `iat`, `nbf`, `exp`,
  `sub`, `scopes`)
- Tokens are held in **cookies** on the vendor domain: `accessToken`, `refreshToken`, `tokenType`,
  `expiresIn`. `expiresIn` is `1296000` — **15 days**.
- `sub` is the Shipturtle **user** id. `GET /api/v1/me` returns that user:

```json
{"data":{"id":871756,"name":"Grace Shorter","email":"grace-s@the-culture-connection.com",
         "company_id":1092484,"type":"user","type_role":"user","is_master":null, …}}
```

- `company_id` **is the vendor id.** `GET /api/v1/active-subscription` confirms it:
  `subscriptions[0].vendor_id = 1092484`, under `merchant_id = 1066319` (Little Blue Market),
  on plan 397 "Existing Little Blue Market Vendors", commission 9.50%.

So the shape is: **merchant 1066319 → vendor (company) 1092484 → one or more users, each with an email.**
`settings/user-management` in the panel means a vendor can have several user logins.

### The consequence for the app

There is no vendor SSO to federate against, and it would be wrong to ask a seller for their
Shipturtle password in our app. **A seller's app identity is the same Firebase account as a buyer's;
"seller" is a role granted by matching their verified email to a Shipturtle vendor user.**
That is exactly the seam `functions/src/linking.ts` already has — `findVendor()` is the part still
stubbed to a hand-written `vendorMappings` document.

To fill it automatically you need Shipturtle's Open API, and that is a **paid add-on**: Settings →
Subscription and Billing → "API Integration", then Dashboard → API integration → generate an access
token with *Order API Access* and/or *Product API Access*. That token is a **merchant-level** token —
Grace's vendor session token above is not it and will not list other vendors.

**The mapping rule, now decidable:** a Shipturtle vendor user's `email` ↔ a Firebase account's
verified email → `users/{uid}.shipturtleVendorId = company_id`, `isSeller = true`. That is strategy 4
in `vendors.ts`, and it is the right one. Strategies 1–3 stay as they are: the line attribute for
app-originated orders, the manual override, and the vendor-name match.

---

## 3. How to import a seller's products and their metadata

**Import from Shopify, not from Shipturtle.** Shipturtle already pushes every vendor's products into
the Shopify store and stamps the vendor's shop name into Shopify's `product.vendor` field. Shopify is
therefore the merged, deduplicated, already-approved catalog; Shipturtle's product API is a
per-vendor DataTables endpoint (`POST /api/v3/fetch-product-data/parent`) scoped to whoever's bearer
token you hold — useless for a whole-catalog import.

Live numbers from `littlebluemarket.com/products.json` right now: **2,500+ published products across
79+ distinct `vendor` values.** Largest: Gwynstone (551), AbstractbyRabrams (465), Romantique Books
(202), Renewthehalls (178), Peaches and Seam (107).

### One seller's products

Admin GraphQL, which the app already brokers a token for in `functions/src/shopify/token.ts`:

```graphql
query VendorProducts($q: String!, $after: String) {
  products(first: 250, query: $q, after: $after) {
    pageInfo { hasNextPage endCursor }
    nodes {
      id title handle descriptionHtml productType tags status vendor
      createdAt updatedAt publishedAt
      featuredImage { url altText }
      images(first: 20) { nodes { url altText width height } }
      options { name position values }
      variants(first: 100) {
        nodes { id title sku price compareAtPrice availableForSale
                inventoryQuantity selectedOptions { name value } image { url } }
      }
      metafields(first: 25) { nodes { namespace key type value } }
    }
  }
}
```
with `q: "vendor:'Paisley Moon Creative'"`. Quote the vendor name — most of them contain spaces,
commas or `&` (`Jilly Bean Publishing, LLC`, `Chill, Babe Candle Co`, `Femme & Fawn`).

### The whole catalog at once

2,500+ products × variants is too much for cursor paging inside a Cloud Function timeout. Use a
**bulk operation**: `bulkOperationRunQuery` with the same selection minus pagination, poll
`currentBulkOperation`, then stream the JSONL result. One call, no rate limiting, runs to completion.

### Keeping it current

Already wired: `products/create`, `products/update`, `products/delete` webhooks →
`mirrorProduct` / `removeMirroredProduct` in `functions/src/catalog.ts`. Nothing to add. The backfill
just has to write documents in the same shape those webhooks produce — note `mirrorProduct` reads
**REST-shaped** payloads (`body_html`, `images[].src`, `variants[].price`, `tags` as a
comma-separated *string*), so a GraphQL backfill needs its own mapper or a shape adapter. Do not let
the two drift; that is how half the catalog ends up with a different field set.

### What the metadata actually looks like

`products.json` field set: `id, title, handle, body_html, published_at, created_at, updated_at,
vendor, product_type, tags, variants[], images[], options[]`.
Variants: `id, title, option1..3, sku, requires_shipping, taxable, featured_image, available, price,
grams, compare_at_price, position, product_id`.

Two things the mirror gets wrong against real data:

1. **`product_type` is not a category.** Real values are things like `"physical"`. The store's actual
   taxonomy lives in **collections** — there are 92 of them (`Adult Apparel`, `Bath, Beauty &
   Wellness`, `Books & Bookish Gifts`, `Baked Goods`, …). `catalog.typeSlug` built from
   `product_type` will bucket the entire catalog into one or two meaningless slugs.
2. **The hashtag filter matches nothing.** `mirrorProduct` keeps only tags starting with `#`. Real
   tags do not: `"feminist gift"`, `"political tote bag"`, `"New"`, `"shoulder tote"`. Every mirrored
   product will get `tags: []`, and the hashtag counters in `onPostWritten` will only ever see tags
   typed by app users.

**The initiatives are collections, not tags.** `Ally Owned` and `BIPOC Owned` are already collections
on the store, sitting alongside the category ones. Mirror `collections` (id, title, handle, image)
and each product's `collections` edge, and the initiative model has real data behind it on day one.
Keep the `#`-prefixed tag path for user-created posts, where hashtags genuinely are hashtags.

---

## 4. Tying each person to their products and their purchases

Four joins, all keyed off the **verified** email or off an id we stamp ourselves.

### Buyer → past purchases (existing website customers)
`linkAccounts` (callable) reads `request.auth.token.email` + `email_verified`, finds the Shopify
customer by `email:`, stores `shopifyCustomerId`, and backfills the last 50 orders into
`users/{uid}/purchases`. Already built and correct. The email comes from the token claim, never the
request body — keep it that way; a client-supplied email lets anyone inherit a stranger's history.

### Buyer → new purchases
`orders/paid` webhook → `normalizeOrder` → `recordPaidOrder`, matched to a uid by `emailLower`.
This is the only source of truth that a purchase happened; the app cannot observe checkout completing.

### Seller → products
`catalog/{id}.sellerId`, set inside `mirrorProduct` from `resolveSellerUid({vendor, productId})`,
i.e. Shopify's `product.vendor` string → a uid.

### Seller → sales and revenue
Order line → product → `vendor` → uid, via the same `resolveSellerUid`. App-originated orders skip
the lookup entirely because they stamp `app_seller_uid` on the line.

### Four gaps in the current implementation, all real

1. **`shopifyVendorName` is never written.** `linkStoreAccounts` sets `shipturtleVendorId` and
   `isSeller`, but strategy 3 in `resolveSellerUid` queries `users.shopifyVendorName`, which nothing
   populates. Write it during linking, from the Shipturtle vendor's store name.
2. **Products mirrored before their seller signs up keep `sellerId: ''` forever.** Nothing re-resolves
   them. Since the catalog will be backfilled long before 79 sellers create app accounts, that is the
   default state, not an edge case. `linkStoreAccounts` must, after setting `isSeller`, run a
   `catalog.where('vendorName','==',name)` backfill — which means **`mirrorProduct` has to persist the
   raw `payload.vendor` string on the document**; today it stores only the resolved (often empty) uid,
   so there is nothing left to re-match on. That field is the fix, and it is one line.
3. **The negative cache is sticky.** `resolveSellerUid` caches `''` in a module-level `Map` for the
   life of the function instance. After a vendor mapping is written, a warm instance keeps returning
   `''`. `forgetVendorCache()` exists — call it from the linking path, or don't cache misses.
4. **Backfilled purchases carry `sellerId: ''`.** `backfillOrders` hardcodes it, though the order
   query already selects `lineItems.nodes.vendor`. Pass that through `resolveSellerUid` and a buyer's
   history links to seller profiles instead of dead ends.

---

## 5. The one thing still genuinely blocked

The Shipturtle **API Integration add-on** and a merchant-level access token. Without it `findVendor()`
cannot be automated and every seller has to be linked by hand via a `vendorMappings` document. The
rule itself is no longer unknown — it is email → `company_id` — so the code does not change shape
when the token arrives; only `findVendor()` gets a real implementation.
