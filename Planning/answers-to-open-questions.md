# Answers to the open questions — in plain language

**The decision that shapes every answer below:** we build and test against a **separate test shop**,
and switch the app over to the real littlebluemarket.com shop later, once it works. Nothing about the
real shop is touched until then.

One thing to know about that up front, so "migrate" doesn't mean something scarier than it is:
**nothing moves *into* Shopify.** The real shop already has all 2,500 products, the vendors and the
customers. What "migrates" is *where the app points* — a handful of settings in the backend, the
app being installed on the real shop, and Shopify being told to send its notifications to us. The
test shop is thrown away afterwards; Shopify doesn't allow test stores to become real ones anyway.

I'm the admin for all of this. I don't know Shopify, so Part 0 is a click-by-click list of everything I
have to get, in the order to get it.

---

## Part 0 — Things I need to get

Work top to bottom. Each item says where to click, what you're looking for, and who it goes to.
Anything marked 🔒 is a secret: hand it to the engineer privately (a password manager share or a
direct message that you delete), never in a document, a ticket or a group chat.

### Shopify — the Dev Dashboard (where apps and test shops live)

Log in at **dev.shopify.com/dashboard**. This is a different site from your shop's admin. It's where
the app already exists.

- [ ] **0.1 Create the test shop.** Left sidebar → **Stores** → **Create store** → type **Dev** → name it
  something obvious like `lbm-test` → plan **Basic** → **Create store**. Write down the address it
  gives you; it ends in `.myshopify.com`. *Hand to the engineer:* that address. It becomes
  `SHOPIFY_STORE_DOMAIN` for testing.

- [ ] **0.2 Install the app on the test shop.** Left sidebar → **Apps** → open the Little Blue Market app
  → there's an install / "Test on development store" option → pick the store from 0.1. (You did this
  once already for the real shop; this is the same thing for the test one.)

- [ ] **0.3 Check the app's permissions.** Same app → **Configuration** → find **Access scopes**
  (it may be called "API access scopes"). Look for these three, ticked:
  `write_products`, `write_inventory`, `write_publications`. If any is missing, tick it and save —
  and reinstall on the test shop (0.2) afterwards, because permissions only take effect on install.
  *Hand to the engineer:* "all three are on" or which one was missing.

- [ ] **0.4 The app's two identifiers.** Same app → **Configuration** or **Settings** → you'll see a
  **Client ID** and a **Client secret**. The client ID is like a username — fine to send in the open.
  The client secret 🔒 is a password. Both are already in your `.env.littlebluemarket` file, so you
  probably don't need to copy them again — just confirm they match what's on screen.

- [ ] **0.5 Customer accounts on the test shop.** So buyers log in the same way they do on the real
  shop: open the **test shop's admin** (from the Dev Dashboard, click the store) → **Settings** →
  **Customer accounts** → choose **Customer accounts** (the newer, passwordless kind — *not*
  "Legacy"). Save.

### Shopify — the test shop's admin (day-to-day settings)

Open the test shop from the Dev Dashboard, or go to `https://<your-test-shop>.myshopify.com/admin`.

- [ ] **0.6 Put real-looking products in it.** Go to the **real shop's** admin → **Products** →
  **Export** → "All products", CSV → download. Then in the **test shop** → **Products** → **Import** →
  upload that file. This carries the vendor names (the column called *Vendor*), tags, prices, images
  and even a *Collections* column — which is exactly the data the app needs to look real. **Do not
  export or import Customers** — those are real people's details and a test shop doesn't need them.
  *Hand to the engineer:* "test shop has the product catalogue imported".

- [ ] **0.7 Locations.** Test shop → **Settings** → **Locations**. Count them and note the names. Then
  do the same on the **real** shop and note whether there are one or two, or dozens named after
  vendors. *Hand to the engineer:* the count and a few of the names, for each shop.

- [ ] **0.8 Webhooks — just look, don't add.** Test shop → **Settings** → **Notifications** → scroll to
  the bottom → **Webhooks**. Note what's listed (probably nothing yet on a new test shop — that's
  fine; the engineer registers them). Do the same on the real shop and screenshot the list.
  *Hand to the engineer:* the screenshot.

- [ ] **0.9 A test vendor account in Shipturtle, on the test shop.** Test shop → **Apps** → **Shopify
  App Store** → search **Shipturtle Multi Vendor** → install on the test shop. Then, inside
  Shipturtle, **Vendors → Manage Vendors → Add vendor** and create one made-up vendor whose name
  exactly matches one of the imported product vendors (e.g. `Gwynstone`), with an email you control.
  If Shipturtle won't install on a test shop, skip this — the engineer can fake a vendor by hand; the
  plan allows for it.

### Firebase (the app's own backend)

Log in at **console.firebase.google.com**.

- [ ] **0.10 Make a test project.** **Add project** → name it `little-blue-test` → you can turn
  Analytics off → create. The real one, `little-blue-610e5`, stays for later. Testing in a separate
  project means fake orders never mix with real sales counters.

- [ ] **0.11 Give the engineer access.** Open the project → the ⚙ gear next to *Project Overview* →
  **Project settings** → **Users and permissions** → **Add member** → their email → role **Editor**.
  Do it for `little-blue-test` now and `little-blue-610e5` when we cut over.
  ⚠️ If anyone asks you to download a "service account key" or a JSON file, say no — the plan
  deliberately doesn't use one.

- [ ] **0.12 Turn on the pieces.** In the test project's left sidebar, click each of **Authentication**
  (→ Get started → enable **Email/Password**, and tick **Email link (passwordless sign-in)** →
  also enable **Anonymous**), **Firestore Database** (→ Create database → production mode → a US
  region), **Storage** (→ Get started), and **Functions** (→ this one needs the project on the
  **Blaze** pay-as-you-go plan; it prompts you. It stays free within generous limits).

### Shipturtle — the owner's merchant account (not your vendor login)

Two things only the store owner can do. Send them this section.

- [ ] **0.13 Export the vendor list.** Owner's Shipturtle dashboard → **Vendors → Manage Vendors** →
  **Export**. We need three columns per vendor: login email, shop name, and the vendor number
  (`company_id`). *Hand to the engineer:* the file.

- [ ] **0.14 The API add-on** (optional for now). **Settings → Subscription and Billing → API
  Integration** → buy it → then **Dashboard → API integration → generate a token** with both "Order
  API Access" and "Product API Access" ticked. 🔒 That token goes to the engineer privately.
  Nothing else waits on this; it only unlocks the automatic conveniences.

### What to hand the engineer, in one message

Test shop address · "app installed, three scopes on" · "catalogue imported" · locations (both shops) ·
webhook screenshots (both shops) · Firebase project `little-blue-test` with them as Editor · the
vendor export from the owner · and, privately 🔒: nothing new — the secrets already in your `.env`
are the ones they need, set through the private secrets command.

---

## Part 1 — The answers

### A. Hard blockers

**A1 — Claim codes.** The engineer needs a list of real vendors (email, shop name, vendor number) to
make the one-time codes that prove a seller is who she says she is. That list comes from the
owner's Shipturtle export (0.13). **Decision:** codes for the top five vendors first — Gwynstone,
AbstractbyRabrams, Romantique Books, Renewthehalls, Peaches and Seam cover about 1,500 of the 2,500
products — then on request. On the test shop, one made-up vendor (0.9) is enough to build against.

**A2 — Shipturtle's API add-on.** Has to be bought from the owner's merchant account (0.14). Not
blocking anything else; proceed without it.

**A3 — Which shop to write to.** **A separate test shop, created in the Dev Dashboard (0.1), with the
real catalogue imported by CSV (0.6).** The real shop is not touched until cutover. Worth knowing:
`little-blue-cart-dev.myshopify.com` *is* littlebluemarket.com — Shopify's own login page identifies it
that way and the vendor dashboard links to it as "the store". The "dev" in the name is just its old
nickname. So: never test product creation there.

**A4 — Webhooks.** On the test shop, the engineer registers them (the app can do this itself once
installed). On the real shop, I'll send a screenshot of what's under Settings → Notifications →
Webhooks (0.8) so they know what exists before cutover.

**A5 — A test seller.** On the test shop: the made-up vendor from 0.9, whose name matches imported
products, so "her products are already there" is testable from day one. My own real vendor account
(`grace-s@the-culture-connection.com`, Shipturtle user 871756, vendor 1092484) stays for the real
shop; it has no products, so it's only useful for the sign-in half.

### B. Decisions — agree with all defaults

B1 built-in browser checkout · B2 single variant first · B3 default location *(I'll send the counts
from 0.7)* · B4 admin flag · B5 no automatic photo screening, owner approval is the gate ·
B6 app has its own sign-in, matched to Shopify by email · B7 status chip, no push yet · B8 no digital
products yet · **B9 tutorial wording: ship as written** *(or edits here: …)*.

### C. Access — before anything deploys

- Firebase: engineer is Editor on `little-blue-test` now (0.11); on `little-blue-610e5` at cutover.
  No service-account key.
- `SHOPIFY_STORE_DOMAIN` = the test shop's address from 0.1 for now; `little-blue-cart-dev.myshopify.com`
  at cutover.
- `SHOPIFY_CLIENT_ID` = the value on that line of `.env.littlebluemarket`.
- Bump the API version default in `config.ts` to `2026-07`.
- I'll read back Locations, Webhooks and Access scopes from the screens above.

---

## Part 2 — What "cutover" will actually involve, so it's not a surprise

When the app works on the test shop, switching to the real one is a checklist, not a rebuild:

1. Install the app on the real shop (already done) and confirm the three scopes there too.
2. Change `SHOPIFY_STORE_DOMAIN` to `little-blue-cart-dev.myshopify.com` and deploy to the real
   Firebase project `little-blue-610e5`.
3. Register the webhooks on the real shop.
4. Run the one-time catalogue import (`backfillCatalog`) against the real shop — this fills the app's
   copy of the catalogue from the real 2,500 products.
5. Issue the claim codes to the top five vendors.
6. Nothing from the test Firebase project comes across. Fake orders, fake sellers and fake listings
   stay in `little-blue-test`, which you can delete.

---

## Your reply — copy, fill the blanks, send

> **Environment:** I'm creating a separate Shopify test shop in the Dev Dashboard and importing the real
> product catalogue into it by CSV. We build and test there. The real shop
> (`little-blue-cart-dev.myshopify.com` — which *is* littlebluemarket.com) is untouched until cutover,
> when we repoint the backend, register webhooks and run the catalogue import against it. I'll send the
> test shop address as soon as it exists.
>
> **A1** — Vendor export is coming from the owner's Shipturtle account. Top five vendors get codes
> first, then on request. On the test shop, use one made-up vendor.
> **A2** — Add-on has to come from the owner's merchant account; proceed without it.
> **A3** — Test shop, as above. Do not test product creation against little-blue-cart-dev.
> **A4** — You register webhooks on the test shop; I'll send a screenshot of the real shop's list.
> **A5** — Made-up vendor on the test shop, name matching imported products. My real vendor account is
> `grace-s@the-culture-connection.com` / Shipturtle user 871756 / vendor 1092484, for the sign-in half.
>
> **B1–B8** — Agree with all defaults. B3: locations counts coming.
> **B9** — [Ship it as written / edits: …]
>
> **C** — You're Editor on Firebase project `little-blue-test` [now / by <date>]; `little-blue-610e5` at
> cutover. No service-account key. `SHOPIFY_STORE_DOMAIN` = [test shop address]; `SHOPIFY_CLIENT_ID`
> = [from my .env]. Bump the API version default to 2026-07. Locations, webhooks and access scopes
> coming from the admin screens.
