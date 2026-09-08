# Plan: littlebluecart.com directory + onboarding doors + push notifications (Stages 10–12)

`REPO` = `little_blue_market\`, `PARENT` = the folder above it (where `.env.dev` lives). Same shorthand as `Planning/checkpoints.md`.

> **Status, 2026-09-08:** every checkpoint below except the optional CP-D5 is built, tested and pushed to `main`: CP-D0–D4, CP-O1–O2, CP-N0–N3, and CP-N4's iPhone files. None is ticked yet: each waits for your tap-through, and the whole directory stage waits for the Cloudways staging site and the three secrets (§2). The boxes, pass lines and journeys live in `Planning/checkpoints.md` (Stages 10–12) and `Planning/manual-test.md` (J12–J15). One thing to know before anything else: **the next `deploy-dev` asks for the three WordPress secrets and will not finish until they exist**, so do §2's "First" and "Secrets" steps before deploying anything, including a Stage 8/9 fix.

## 1. Context

The app already joins Firebase (identity, social) with Shopify + Shipturtle (Little Blue **Market** money and shipping). Stages 0–9 are built; 8–9 await your tap-through.

You now want to bring in Little Blue **Cart** (littlebluecart.com), the WordPress site with the business directory and a WooCommerce shop, so that:

- someone who bought on littlebluecart.com sees those orders in the app;
- a business listed in the directory sees its listing, contact info and website in the app, its listing is visible to everyone in the app like a seller profile, and it can add a listing (through the website form);
- applying to sell on the Market stays exactly as it is;
- new people are steered to the right door when they create a profile;
- the app sends push notifications (announcements from you, new product from a shop you bought from, forum activity, shoutouts that tag you, reviews on your product) on Android and iPhone.

What I verified live today about littlebluecart.com (no code exists for any of it yet):

- Directory listings are a WordPress post type `vendors_dir_ltg` ("LBC Directory - Listings", Directories Pro plugin). They are readable without a password at `/wp-json/wp/v2/vendors_dir_ltg`, with title, owner (WP user id), categories, ownership tags (Woman-Owned…), state, and `drts_fields` (website, email, phone, address, plan, photos). About 1,700 listings.
- WooCommerce REST (`wc/v3`) is on. The shop sells LBC merch and paid listing upgrades.
- Add Your Business is `https://littlebluecart.com/add-directory-listing/` (login required; Free / $25 Spotlight / $50 Express Lane; Free reviewed within 2 weeks).
- The site is hosted on **Cloudways** (the server answers as `cloudwaysapps.com`). Cloudways has one-click staging, which is how the development copy gets made.
- Matching an app account to a WP account has to be by email, and reading WP user emails needs an admin Application Password. The phone never talks to WordPress; Cloud Functions do, same as Shopify.

Decisions you made today (I will not re-ask):

| Question | Your answer |
|---|---|
| Posting a listing from the app | Website form only. The app opens Add Your Business. |
| Who can see directory listings in the app | Everyone. A linked directory owner's listing (business, category, state, ownership tags, contact) shows like a seller profile and in the feed. Only owners who have linked in the app are mirrored; the full 1,700 browse is an optional later checkpoint. |
| Push phones | Android and iPhone. All sending logic in TypeScript Cloud Functions. |
| Forum pushes | New threads in forums you joined, plus replies to threads you started or commented on. |
| The welcome screen | Keep the artwork. "Sign in" = Returning to the app. "Create a Profile" opens the new "Are you a…" screen. |
| Development WordPress | Build and test against a **staging copy** of littlebluecart.com, never the live site, the same rule as the dev Shopify shop. |

## 2. What I need from you

Nothing gets pasted into chat. Each secret is typed once into a prompt on your computer.

### First: the development WordPress (CP-D0, your clicks)

Everything below is created on the **staging** site, not on littlebluecart.com. The dev Firebase project `little-blue-610e5` points at staging. Live keys are made only at cutover, for the production Firebase project.

**Route C, the one in use (Grace's decision, 2026-09-08): dev reads the LIVE site.** The host blocks plugin installs and there is no Cloudways login, so no copy can be made today. The app never writes to WordPress and the WooCommerce key is Read, so `WP_BASE_URL=https://littlebluecart.com` with `WP_LIVE_OK=yes` in the dev env is allowed; the doctor stays yellow about it. Test with existing accounts where possible and delete any test user, order or listing added to the live site once a checkpoint passes. The Application Password and WooCommerce key are made on the live wp-admin, and they are also the production credentials at cutover.

**Route B, from wp-admin only (kept for when a copy becomes possible):**

1. littlebluecart.com `/wp-admin` → Plugins → Add New → **WP Staging** → Install → Activate.
2. **WP Staging** → **Create Staging Site** → name `dev` → **Start Cloning**. 10–30 minutes; keep the tab open.
3. The copy is `https://littlebluecart.com/dev/`, its wp-admin `https://littlebluecart.com/dev/wp-admin/`, same login as live. Visitors see a login box; the app gets through with the Application Password (CP-D1).
4. In the **copy's** wp-admin: WooCommerce's staging question → **This is a temporary / staging site**; WooCommerce → Settings → Payments → every live method off; Settings → Reading → **Discourage search engines**; Plugins → **Disable Emails** installed and active.
5. `WP_BASE_URL=https://littlebluecart.com/dev` and `DIRECTORY_ADD_LISTING_URL=https://littlebluecart.com/dev/add-directory-listing/` in the dev env file. The doctor allows a copy in a folder under the live domain and refuses only the live root.

*Route A, if a Cloudways login turns up:* Cloudways → the app → **Staging Management** → **Add Staging Application**; the copy gets its own `https://wordpress-…cloudwaysapps.com` address; switch **Password Protection** off; steps 4–5 are the same.

### Secrets (typed into `npm run secrets:dev -- NAME` inside `REPO\functions\`, made on the staging site)

| Name | What it is | Where you get it |
|---|---|---|
| `WP_APP_PASSWORD` | A WordPress Application Password for your admin user | staging `/wp-admin` → Users → your admin user → Profile → **Application Passwords** → name it `Little Blue Market app` → Add New → copy once. If that section is missing, a security plugin (Wordfence, Solid Security) has turned it off; switch it on there. |
| `WC_CONSUMER_KEY` | WooCommerce REST key | staging WooCommerce → Settings → Advanced → REST API → **Add key** → Description `Little Blue Market app`, User: your admin, Permissions **Read** → Generate. |
| `WC_CONSUMER_SECRET` | The matching secret | Same screen, shown once next to the key. |

### Plain settings (not secret; I add them to `REPO\functions\.env.little-blue-610e5`, you tell me the value)

| Name | Dev value |
|---|---|
| `WP_APP_USER` | Your WordPress admin **login name** (the one the Application Password was made under) |
| `WP_BASE_URL` | The staging URL from step 2 (live: `https://littlebluecart.com`, later) |
| `DIRECTORY_ADD_LISTING_URL` | `<staging URL>/add-directory-listing/` (live: `https://littlebluecart.com/add-directory-listing/`, later) |

### Things only you can do (no secret involved)

- **Test accounts on staging:** a WP user `grace-s+dir1@the-culture-connection.com` (Subscriber) with one Free directory listing, and one completed WooCommerce order placed for that user (WooCommerce → Orders → Add order). Staging already holds a copy of every real listing and order, so real accounts can be used to check matching too.
- **Android emulator with Google Play services.** Push needs a "Google APIs" or "Google Play" system image, Android 13 or newer. The doctor will tell you if the running emulator lacks it.
- **iPhone push (CP-N4):** an APNs key from Apple Developer (Keys → + → tick Apple Push Notifications service → download the `.p8` once, keep it in `PARENT\`, note Key ID and Team ID), uploaded in Firebase console → Project settings → Cloud Messaging → Apple app → APNs Authentication Key. Push Notifications capability ticked on the `com.littleblue.market` identifier. **Building and testing the iPhone app needs a Mac with Xcode and a real iPhone**; there is no way around that on Windows. I pre-wire every iOS file so the Mac session is clicks only. The server side works for both platforms from day one.

No new secret for push itself. Firebase Cloud Messaging uses the project's own credentials.

## 3. Rules that carry over

- Role truth stays server-side. No role field on `users/{uid}`. The directory link lives in a new server-only `directory/{uid}` doc, mirroring `sellers/{uid}`.
- **Dev never touches live.** `WP_BASE_URL` on the dev project must be the staging site; the doctor fails when it is `littlebluecart.com`, the same guard it has for the production Shopify domain.
- Every callable is wrapped in `withLoudErrors` (`functions/src/errors.ts`); the phone shows Copy for Claude.
- One commit and push per checkpoint. Tests green first. Add every new route to `test/screens_smoke_test.dart` and `test/text_scaling_test.dart`.
- New checkpoints get added to `Planning/checkpoints.md` (progress table, stage sections, §5 Things only you can do, §6 Critical files, § Sequencing) and journeys to `Planning/manual-test.md`. Stage letters: **D** directory, **O** onboarding, **N** push.

## 4. Stage 10 — littlebluecart.com directory (CP-D)

**Goal:** a directory customer sees website orders; a directory owner sees, shares and adds listings; everyone can see a linked owner's business. All of it built and tested against the staging WordPress.

### CP-D0 A development WordPress + WooCommerce (S for Claude, ~1 hour of your clicks)

**Why:** the live site holds 1,700 real businesses and real customer orders. Building against it means test users, test orders and test listings land in the real directory, and a bug in the sync could touch real data. Cloudways staging clones the whole site (theme, WooCommerce, Directories Pro and its field setup, all data) to a separate URL, which is exactly what is needed because the Directories Pro configuration cannot be rebuilt by hand.

**Claude builds**
- `functions/scripts/doctor.mjs`: an `env params` rule that FAILs when the dev project's `WP_BASE_URL` is `littlebluecart.com` (fix text: "point WP_BASE_URL at the staging site"), and a `wordpress` reachability line that only needs the URL: `GET <WP_BASE_URL>/wp-json/` must answer with the site name and the `wc/v3` and `wp/v2` namespaces, then `GET /wp-json/wp/v2/vendors_dir_ltg?per_page=1` must return one listing. PASS text `staging reachable · <site name> · listings public`. A `401` here means Cloudways Password Protection is on.
- `PARENT\.env.dev` reference copy gains the WP lines (names only for the secrets, values for the plain settings), matching how the Shopify ones are kept.
- A short section in `Planning/identity-and-catalog.md` describing staging vs live for WordPress, next to the dev-vs-production Shopify shop section.

**Grace does:** steps 1–4 in §2 "First: the development WordPress", then `scripts\doctor.ps1`.
**Pass:** the staging URL opens in a browser over https and looks like littlebluecart.com; `<staging URL>/wp-json/wp/v2/vendors_dir_ltg?per_page=1` shows a listing in the browser; the doctor line reads `PASS wordpress staging reachable …`.
**If it fails:** `401` or a browser password box → Cloudways → staging app → Access Details → Password Protection off. `FAIL env params WP_BASE_URL is the live site` → put the staging URL in `functions\.env.little-blue-610e5`. Staging URL is `http` only → Cloudways → staging app → SSL Certificate → install Let's Encrypt (or use the `cloudwaysapps.com` address, which already has https). WooCommerce says "live payments" → step 3 not done.

### CP-D1 Credentials, WordPress client, doctor (S)

**Claude builds**
- `functions/src/config.ts`: `WP_APP_PASSWORD`, `WC_CONSUMER_KEY`, `WC_CONSUMER_SECRET` (defineSecret, declared above `ALL_SECRETS` and added to it). The three plain params landed in CP-D0. The secrets are declared here and not in D0 on purpose: Firebase refuses to deploy a function that names a secret which does not exist yet, so Grace creates the three secrets first and deploys second.
- New `functions/src/wordpress.ts`: `wpFetch` (Basic auth for WP or WC, 15 s timeout, two retries on 429/5xx, error text never includes the header), `wpGet`/`wcGet`, pure parsers `pickWpUser` (exact, unique email match; two matches → null, same rule as `linking.ts`), `listingFromWp` (allowlist over `drts_fields`), `orderFromWc` (int cents), `termNames` with a 24 h cache in `_internal/wpTaxonomies`.
- `functions/src/diagnostics.ts`: `wordpress` probe (public listing count, then `/wp/v2/users/me?context=edit` and assert role `administrator`) and `woocommerce` probe (`/wc/v3/orders?per_page=1`).
- `functions/scripts/doctor.mjs`: the `wordpress` line from D0 grows the authenticated check; new `woocommerce` line; WARN "directory features off" when `WP_APP_USER` is empty. New `functions/scripts/wp-probe.mjs` (`npm run wp:probe -- --email <addr>`): WP user found?, listing count by status, `drts_fields` key names, WC customer id, order count. Secret-free output you can paste.
- Tests: `functions/test/wordpress.test.ts` on recorded JSON.

**Grace does:** the three secrets and `WP_APP_USER` from §2 (all made on staging), then `scripts\deploy-dev.ps1`, then `scripts\doctor.ps1`.
**Pass:** doctor shows `PASS wordpress … administrator … N listings public` and `PASS woocommerce … M orders`. Diagnostics → Run backend health check shows both green.
**If it fails:** `WP 401 rest_cannot_access` → wrong Application Password or the feature is off. `roles [subscriber]` → the password must be your administrator user's. `woocommerce_rest_cannot_view` → key is not Read, or key and secret are from different pairs. `403` with an HTML page → a firewall strips the Authorization header; paste the doctor block.

### CP-D2 Link your directory account and see website orders (M)

**Claude builds**
- `functions/src/directory.ts` `syncDirectory(uid, emailLower, {force})`: find WP user by email → WooCommerce customer by email → orders by customer id (or by billing email exactly, for guest checkouts) → write `directory/{uid}` `{wpUserId, wpLogin, wpEmailLower, wcCustomerId, listingIds[], orderCount, status:'linked'|'notFound', linkedAt, checkedAt, refreshedAt}` and `users/{uid}/directoryOrders/{wcOrderId}` `{number, status, createdAt, totalCents, currency, items[], viewUrl}`. Skips when refreshed under 10 minutes ago unless forced. A `notFound` result is stored so non-WP users are re-checked at most weekly.
- `index.ts`: callables `directoryLinkMe` and `directoryRefresh` (email from the verified token only, same "Confirm your email address first." precondition as `sellerSyncMe`; secrets: the three WP/WC ones; 120 s).
- Rules: `directory/{uid}` owner read, no writes; `users/{uid}/directoryOrders` owner read, no writes. Rules tests in `functions/test/rules.test.mjs`.
- Flutter: `lib/models/directory.dart` (`DirectoryLink`, `DirectoryOrder`, `DirectoryLinkStatus {linked, alreadyLinked, notFound}`, `DirectoryLinkResult`); `DirectoryRepository` interface in `lib/data/repositories/repositories.dart`; `lib/data/firebase/firestore_directory_repository.dart` (copy `syncSellerStatus` in `firestore_profile_repository.dart:275-295`) plus a fixture twin; providers `directoryLinkProvider`, `directoryOrdersProvider`; a once-per-launch silent link in `lib/state/session.dart` next to `_linkOnce` (:132-141): when verified and the link doc is missing or `notFound` older than 7 days, call `link()` best-effort. This is how directory customers get orders without picking a role.
- `lib/screens/you/directory_screen.dart` (`/you/directory`): `UnverifiedBanner`; status card (**Link my directory account** / "Linked as <login>" + **Refresh**); "Orders from littlebluecart.com" rows (number, date, total, status; tap opens `viewUrl`). Result copy: linked → "Linked. N orders and M listings found."; notFound → "No account at littlebluecart.com uses this email. If your listing or orders are under another address, sign in with that one." Entry row "Little Blue Cart directory" in `edit_profile_screen.dart` for every member.

**Grace does:** create the `+dir1` WP user and order on staging (§2). In the app: Create a Profile with `+dir1`, confirm the email, You → Edit profile → Little Blue Cart directory → **Link my directory account**.
**Pass:** the card says Linked and the order shows with its number and total. Firebase console shows `directory/<uid>` and `users/<uid>/directoryOrders/<id>`. Kill and reopen the app: same result without tapping.
**If it fails:** "No account at littlebluecart.com uses this email" → the WP user's email is not exactly `+dir1`. Linked but no orders → the order's billing email differs; run `npm run wp:probe -- --email grace-s+dir1@…` and paste. Anything red → Copy for Claude.

### CP-D3 Your listings, with tap-to-call, website and directions (M)

**Claude builds**
- `directory.ts`: fetch the owner's listings (`/wp/v2/vendors_dir_ltg?author=<wpUserId>&status=publish,pending,draft&context=view`, authenticated so pending ones come back, `context=view` so only public fields are mirrored), featured image via `/wp/v2/media/{id}`, term names from the cache. Upsert the **public** mirror `directoryListings/{wpPostId}` `{ownerUid, wpUserId, title, slug, link, website, email?, phone?, address, city, state, zip, categories[], tags[], locations[], plan, imageUrl, status, updatedAt, refreshedAt}`; remove docs that vanished from WP; set `directory/{uid}.listingIds`. Scheduled `directorySyncScheduled` every 6 hours over linked owners.
- Privacy rule: mirror only what the unauthenticated WordPress endpoint already returns. Nothing from `context=edit` reaches Firestore.
- `appConfig` returns `directoryAddListingUrl`; `AppConfig` in `lib/models/seller_sync.dart` gains the field.
- Flutter: `DirectoryListing` model; `watchMyListings()`; `lib/widgets/directory_listing_card.dart` (`LbmCard`: title, plan, "Published" / "Under review" chip, category and state chips, ownership-tag chips, a `Wrap` of small `PillButton`s Website / Call / Email / Directions via `url_launcher` with `https:`, `tel:`, `mailto:`, `geo:0,0?q=`; "View on littlebluecart.com"). "My listings" section and an **Add a listing** button on the directory screen that opens the website form (the `_openRegistration` pattern in `sell_screen.dart:61-74`). `/you/sell` untouched.
- `AndroidManifest.xml` `<queries>`: add `tel`, `mailto`, `geo` so Android 11+ resolves them.
- Rules: `directoryListings` read when `status == 'publish'` or owner; no writes. Indexes: `ownerUid + updatedAt`, `ownerUid + status + updatedAt`.

**Grace does:** logged in as `+dir1` on staging, Add Your Business → Free → business name, website, phone, address, a category, a state, an ownership tag → submit. In the app: Directory → **Refresh** → "Under review" card. Then as WP admin publish it → Refresh again.
**Pass:** the card flips to Published. Website opens the site, Call opens the dialler, Directions opens Maps. **Add a listing** opens the staging website form. `directoryListings/<postId>` has `status: publish`.
**If it fails:** card missing → `npm run wp:probe -- --email …` and paste (field names can differ per plan; expect one round of fixes). "Could not open …" → paste the URL. Refresh says "Try again in a few minutes" → the 10-minute limit, expected.

### CP-D4 Directory owners are visible to everyone (M)

**Claude builds**
- `directory.ts`: for each published listing, write a feed post `posts/directory_{wpPostId}` `{kind:'directory', authorId: ownerUid, listingId, auto:true, …}` the way `autoPostFor` in `catalog.ts:234-249` does for products; delete it when the listing is unpublished.
- Flutter: `PostKind.directory` + `DirectoryPost` in `lib/models/post.dart`; `case 'directory'` in `mappers.dart` (the `default: return null` there would otherwise drop it silently); `_DirectoryBody` in `lib/widgets/post_card.dart` rendering `DirectoryListingCard` from a `directoryListingProvider(listingId)`; the `_TextCell` switch in `profile_screen.dart:290-296`. The compiler flags the remaining exhaustive switches.
- Public profile: `_DirectorySection(personId)` in `lib/screens/market/seller_feed_screen.dart` after `ProfileIdentity`, backed by a `where ownerUid == X && status == 'publish'` query; renders nothing for people without a listing, so no `Person` field is needed.
- Own profile: a "Little Blue Cart directory · 1 listing · 3 orders" card in `profile_screen.dart` when linked, tapping to `/you/directory`.
- Golden screenshots regenerated once (`--update-goldens`), said so in the commit.

**Grace does:** sign in as `+buyer1` → Market feed → the directory post for `+dir1`'s business → tap the avatar.
**Pass:** buyer sees business name, category, state, ownership tags, Website / Call / Email / Directions. A pending listing is not visible to the buyer.
**If it fails:** post missing → `npm run peek -- --collection posts` (look for `directory_`), paste. Card says "Could not load" for the buyer → rules; paste Copy for Claude.

### CP-D5 (optional, later, L) Browse all 1,700 businesses
Hourly delta import of the whole `vendors_dir_ltg` type into `directoryListings` with `ownerUid: null`, category / state / ownership-tag filters, a Directory chip in Market search. Two to three sessions. Not scheduled now.

### Cutover note (not a checkpoint yet)
When the app goes live, the production Firebase project gets its own `WP_APP_PASSWORD`, `WC_CONSUMER_KEY`, `WC_CONSUMER_SECRET` made on littlebluecart.com, `WP_BASE_URL=https://littlebluecart.com`, and the live add-listing URL. Staging drifts from live over time; re-clone it from Cloudways (Staging Management → Push/Pull) before any big directory test. This joins Part 2 of `Planning/answers-to-open-questions.md`.

## 5. Stage 11 — Onboarding doors (CP-O)

**Goal:** Welcome artwork stays screen 1 (**Sign in** = returning to the app). "Create a Profile" opens "Are you…" with **seven doors** (widened on 2026-09-08 from the original three, at Grace's request): the door chosen survives sign-up and lands the person on the right screen.

| Door | Intent (`?intent=`) | Lands on |
|---|---|---|
| New here | `new` | `/market` |
| I've bought on littlebluecart.com | `dircust` | `/market` (changed 2026-09-08: the site has no customer accounts, WooCommerce checks people out as guests; their orders still arrive through the silent link, which matches guest orders by billing email) |
| I've bought on Little Blue Market | `mktcust` | `/you` on the Bought tab (the existing email link fills it) |
| I'm listed in the directory | `dirseller` | `/you/directory?auto=1` (links by itself, shows listings) |
| I sell on Little Blue Market | `mktseller` | `/you/sell?auto=1` (checks the roster by itself) |
| I want to list my business in the directory | `newdir` | `/you/directory?add=1` (opens Add Your Business, explains "come back and tap Refresh once approved") |
| I want to sell on Little Blue Market | `newmkt` | `/you/sell?apply=1` (opens Apply on our website) |

### CP-O1 The "Are you…" screen and the intent that survives sign-up (M)

**Claude builds**
- `lib/models/onboarding.dart`: `enum OnboardingIntent { newHere, directoryCustomer, marketplaceCustomer, directorySeller, marketplaceSeller, newDirectorySeller, newMarketplaceSeller }` with `fromQuery`/`query` and `landingRoute`.
- `lib/screens/onboarding/orient_screen.dart` (`/orient`), same chrome as the other onboarding screens (`_OnboardingScaffold`, `_SlateButton`, `_QuietAction` moved to a shared `onboarding_chrome.dart`): headline "Are you…", a scrolling list of seven `ListRow`-style doors under two small headings, *Shopping* (three) and *Selling* (four), each → `/signin?create=1&intent=<value>`; quiet link "I already have a profile" → `/signin`. A scrolling list, not seven big buttons, so the 2.0 text-scale test passes.
- `welcome_screen.dart:125-128`: Create a Profile hotspot pushes `/orient`.
- `app_router.dart`: `/orient` route; `/signin`, `/verify`, `/setup` read `intent` from the query; the onboarding allow-list gains `/orient`; the cold-start redirect forwards `intent` when present.
- `auth_screens.dart`: `EmailScreen` and `VerifyScreen` carry `intent` on every hop (:213, :314, :474); `ProfileSetupScreen._finish` goes to `intent.landingRoute`. Delete the dead `_SellCheckbox` and `_sells`.
- Why a query param: visible, testable, no global state. Known limit: killing the app between email and setup loses the intent and lands on Market; both doors are one tap away in Edit profile.
- Tests: `welcome_handoff_test.dart` (updated on purpose), `auth_screens_test.dart`, `router_redirect_test.dart`, smoke and scaling routes.

**Grace does:** sign out → Welcome → Create a Profile → **An existing seller on the directory** → `+dir1` → confirm → handle → Create a profile. Repeat with **New to Little Blue Cart**.
**Pass:** first run lands on the Directory screen already linking; second lands on Market. The **Sign in** hotspot still goes straight to Welcome back.
**If it fails:** lands on Market after a seller door → the intent was dropped on one hop; paste Copy for Claude with the route shown in the dev badge.

### CP-O2 The two landing screens finish the job (S)

**Claude builds**
- `sell_screen.dart`: `?auto=1` runs **Check my seller status** by itself once the email is verified; if not yet verified, the existing banner stays and the check fires when "I've confirmed it" flips the session. `VerifyScreen` stays a non-gate.
- `directory_screen.dart`: same `auto` handling (the silent link from D2 already does the work; the screen shows the result line).
- Tests on fixtures: `?auto=1` calls the sync exactly once when verified, zero when not.

**Grace does:** Create a Profile → **An existing seller on the marketplace** → `+seller1` → skip confirming → handle → Create.
**Pass:** Sell with us opens with the Confirm-your-email card and a disabled Check button; confirm the email, tap "I've confirmed it" → the check runs by itself → "You already sell as …".
**If it fails:** the check never runs after confirming → Copy for Claude. "This email is not on our vendor list yet" → expected for a non-vendor address.

## 6. Stage 12 — Push notifications (CP-N)

**Goal:** phones get pushes for the five events; you send announcements from your phone; every notification also lands in the in-app bell.

### CP-N0 Plumbing: a token per phone, one test push (M)

**Claude builds**
- `pubspec.yaml`: `firebase_messaging`, `flutter_local_notifications`.
- Android: `POST_NOTIFICATIONS` permission, default channel `lbm_default`, a white-on-transparent status icon `res/drawable/ic_stat_lbm.xml` and colour, in `AndroidManifest.xml` / `res/`.
- `lib/data/push/push_service.dart` (pure Dart interface) + `lib/data/firebase/firebase_push_service.dart`: permission request, token → `users/{uid}/devices/{token}` `{platform, createdAt, lastSeenAt, appVersion}`, `onTokenRefresh`, delete the device doc on sign-out **before** `signOut()`, foreground banner, `onMessageOpenedApp` / `getInitialMessage` → `data.route` → `router.go`. Fixture no-op twin; `pushCoordinatorProvider` in `lib/state/` tied to `sessionProvider`; background handler registered in `main.dart` only in the live branch. Nothing runs under fixtures or `FLUTTER_TEST`.
- `lib/screens/you/notification_settings_screen.dart` (`/you/notification-settings`): permission line + **Allow notifications**, toggles saved to `users/{uid}/settings/notifications` `{mentions, comments, forums, reviews, newProducts, announcements, mutedForums[], lastAnnouncementsSeenAt}`, and **Send me a test notification** (callable `pushTestMe`). Entry row "Notifications" in Edit profile.
- `functions/src/push.ts`: `sendPushToUid(uid, {title, body, data})` via `getMessaging().sendEachForMulticast` (Android channel + APNs sound set), pruning tokens that return `registration-token-not-registered` / `invalid-argument`; pure `shouldPush(prefs, {type, forumId})`, `titleFor`. `notifications.ts` `notify()` becomes the single choke point: reads prefs once, writes the bell doc, then pushes best-effort (a push failure never fails a trigger). Existing `mention` / `comment` gain a `route`.
- `doctor.mjs` `push` check: manifest bits present; WARN when the running emulator has no Google Play services, with the fix.
- Rules: `users/{uid}/devices` owner read/write (members only), `users/{uid}/settings/notifications` owner read/write. Tests for rules and the pure functions.

**Grace does:** `scripts\deploy-dev.ps1` → `run-live.ps1` on a Google Play image → sign in as `+buyer1` → Edit profile → Notifications → **Allow notifications** → Allow → **Send me a test notification** → press Home.
**Pass:** a banner "Little Blue Market — This phone is set up for notifications" appears; tapping opens the bell. Firestore shows `users/<uid>/devices/<token>`. A shoutout from `+seller1` tagging `@buyer1` arrives as a push and in the bell.
**If it fails:** no permission prompt → Android 13+ image needed, or already denied in App info. `pushTestMe failed: … no devices` → the device doc was not written; Copy for Claude. Token present but nothing arrives → emulator without Play services (doctor WARN).

### CP-N1 Announcements from your phone (M)

**Claude builds**
- `push.ts` `sendAnnouncement({title, body, audience, route, byUid})`: writes `announcements/{id}` then sends to an FCM **topic** (`all`, `sellers`, `directory`; `buyers` = condition `all && !sellers`). Callable `adminSendAnnouncement` behind `requireAdmin`.
- Client subscribes to topics from the session (`all` for every member, `sellers` when `isSellerProvider`, `directory` when linked).
- `AdminRepository` (interface + Firestore + fixture) and `lib/screens/you/admin_screen.dart` (`/you/admin`, visible in release builds, shows "Admins only" unless `isAdminProvider`): title, body, audience `SegmentedTabs` All / Sellers / Buyers / Directory, optional open-on-tap target, **Send** with a confirm dialog, "Recent announcements" list. Entry row "Admin" in Edit profile for admins.
- Bell: merges the last 20 `announcements` (filtered by audience client-side) with personal notifications; `NotificationKind.announcement`; read state via `lastAnnouncementsSeenAt`.
- Rules: `announcements` read for signed-in, no writes.

**Grace does:** as your admin account → Edit profile → Admin → title "Hello from Little Blue Market", body "Testing announcements", All → Send → Yes. Background the app.
**Pass:** the push lands on this phone and any other signed-in test phone; the bell shows it at the top; `announcements/<id>` exists. Sending to Sellers leaves `+buyer1`'s phone silent.
**If it fails:** "Admins only" → CP-C0 Claim admin first. Sent but no push → sign out and in once (topic subscription), then `firebase functions:log --only adminSendAnnouncement`.

### CP-N2 Forums, shoutouts, reviews (M)

**Claude builds** (all in `index.ts` triggers, recipients computed in `push.ts`)
- `onThreadWritten` on create: every `forums/{forumId}/members` id except the author, type `forumThread`, route to the thread, `forumId` carried so per-forum mute can be added later (`mutedForums` is already honoured by `shouldPush`).
- `onThreadCommentWritten` on create: thread author + earlier commenters, minus the replier, deduped, type `forumReply`. Not all members.
- `onPostWritten`: also notify `aboutSellerId` (new, not the author) alongside `mentionedUids`, type `mention` with "gave you a shoutout" copy.
- `onReviewWritten` on create: notify `catalog/{productId}.sellerId` unless the seller wrote it, type `review`, route to the mirrored review post.
- TS type union and Dart `NotificationKind` extended in lockstep (`mention, comment, review, forumThread, forumReply, newProduct, announcement`); bell headlines per kind.

**Grace does:** `+buyer1` joins forum F; `+seller1` starts a thread in F; `+buyer1` replies; `+customer1` replies. `+buyer1` reviews a `+seller1` product. `+buyer1` posts a shoutout tagging `@seller1`.
**Pass:** buyer gets the new thread; seller and buyer (not `+customer1`) get the second reply; seller gets the review and the shoutout. Each push opens the right thread or post.
**If it fails:** wrong recipients → `firebase functions:log --only onThreadCommentWritten`, paste. Nothing at all → N0 device check for that account.

### CP-N3 "New from a shop you bought from" (M)

**Claude builds**
- `orders.ts` `recordPaidOrder` (:253-271): in the same transaction, write the reverse index `sellers/{sellerUid}/buyers/{buyerUid}` `{lastOrderId, lastPurchaseAt, count: increment(1)}`; `linking.ts` backfill writes the same for historical orders. `adminBackfillBuyerIndex` callable + **Rebuild buyer index** button on `/you/admin`.
- New trigger `onCatalogWritten` on `catalog/{productId}`: when `active` flips false→true (or a brand-new doc created active within 10 minutes), `sellerId` set and no `announcedAt` yet → stamp `announcedAt` (server-only field) → notify every buyer in the reverse index, type `newProduct`, route to the product. The transition guard stops the first deploy or a catalog backfill from announcing every product.
- Rules: `sellers/{uid}/buyers/**` denied to all clients.

**Grace does:** Admin → Rebuild buyer index. As `+seller1` add a product → set it Active in Shopify. `+buyer1` (bought from `+seller1` in Stage 3) backgrounds the app.
**Pass:** buyer's phone: "New from <shop>: <title>", tap opens the product. `+customer1` gets nothing. `catalog/<id>.announcedAt` set; re-approving does not re-send.
**If it fails:** nothing → `sellers/<sellerUid>/buyers` empty (rebuild again, paste the count) or the product never transitioned (`npm run inspect:product`). Duplicates → paste `firebase functions:log --only onCatalogWritten`.

### CP-N4 iPhone (M; server side already done, app side needs a Mac)

**Claude builds (pre-wired, safe to commit):** `ios/Runner/Runner.entitlements` (`aps-environment`), `CODE_SIGN_ENTITLEMENTS` in `project.pbxproj`, `UIBackgroundModes: remote-notification` in `Info.plist`; doctor MANUAL line with the console steps; FAIL once the entitlements exist but `ios/Runner/GoogleService-Info.plist` is still missing (it is missing today).

**Grace does (on a Mac):** `flutterfire configure --project=little-blue-610e5 --platforms=ios`; the Apple Developer and Firebase console steps from §2; Xcode → Runner → Signing & Capabilities → your Team, confirm Push Notifications and Background Modes; run on a plugged-in iPhone with `--dart-define=LBM_BACKEND=live`; Edit profile → Notifications → Allow → **Send me a test notification** → lock the phone.
**Pass:** banner on the locked iPhone; an announcement sent from the Android emulator lands on the iPhone too; `devices/<token>` shows `platform: ios`.
**If it fails:** Xcode `no valid "aps-environment" entitlement` → capability not on the signed build. Functions log `messaging/third-party-auth-error` → the `.p8` / Key ID / Team ID do not match the bundle id's team. Nothing and no error → it is a Simulator; APNs needs a real device.

## 7. Engineering notes (for Claude)

**New files:** `functions/src/wordpress.ts`, `functions/src/directory.ts`, `functions/src/push.ts`, `functions/scripts/wp-probe.mjs`, `lib/models/directory.dart`, `lib/models/onboarding.dart`, `lib/data/firebase/firestore_directory_repository.dart`, `lib/data/firebase/firestore_admin_repository.dart`, `lib/data/push/push_service.dart`, `lib/data/firebase/firebase_push_service.dart`, `lib/state/push_coordinator.dart`, `lib/widgets/directory_listing_card.dart`, screens `orient_screen.dart`, `directory_screen.dart`, `notification_settings_screen.dart`, `admin_screen.dart`, `ios/Runner/Runner.entitlements`, `android/.../res/drawable/ic_stat_lbm.xml`.

**Modified hubs:** `functions/src/index.ts` (callables `directoryLinkMe`, `directoryRefresh`, `pushTestMe`, `adminSendAnnouncement`, `adminBackfillBuyerIndex`; schedule `directorySyncScheduled`; trigger `onCatalogWritten`; `appConfig`; the five social triggers), `functions/src/notifications.ts`, `functions/src/config.ts`, `functions/src/orders.ts`, `functions/src/linking.ts`, `functions/src/diagnostics.ts`, `functions/scripts/doctor.mjs`, `firebase/firestore.rules`, `firebase/firestore.indexes.json`, `lib/router/app_router.dart`, `lib/screens/onboarding/{welcome_screen,auth_screens}.dart`, `lib/screens/you/{sell_screen,edit_profile_screen,profile_screen,notifications_screen}.dart`, `lib/screens/market/seller_feed_screen.dart`, `lib/models/{post,notification,seller_sync,models}.dart`, `lib/data/firebase/mappers.dart`, `lib/widgets/post_card.dart`, `lib/state/{session,providers}.dart`, `lib/data/providers.dart`, `lib/data/repositories/repositories.dart` + fixtures, `pubspec.yaml`, `AndroidManifest.xml`, `ios/Runner/Info.plist`, `Planning/identity-and-catalog.md`, `Planning/answers-to-open-questions.md`.

**Reuse, do not rebuild:** `withLoudErrors`, `requireUid` (`index.ts:58`), `requireAdmin` (`admin.ts:69`), `autoPostFor` (`catalog.ts:234`), `_linkOnce` (`session.dart:132`), `syncSellerStatus` client shape (`firestore_profile_repository.dart:275`), `_openRegistration` (`sell_screen.dart:61`), `UnverifiedBanner`, `LbmAsync`, `LbmCard` / `PillButton` / `LbmChip` / `SegmentedTabs` / `ListRow`, `describeError`, `DevErrorSink`, doctor `record()` helpers, `secretValue()` and its production-domain guard, rules test contexts in `functions/test/rules.test.mjs`.

**Rules additions (summary):**
```
match /directory/{uid}                 { allow read: if isSelf(uid); allow write: if false; }
match /directoryListings/{postId}      { allow read: if resource.data.status == 'publish' || isSelf(resource.data.ownerUid); allow write: if false; }
match /announcements/{id}              { allow read: if signedIn(); allow write: if false; }
match /sellers/{uid}/buyers/{buyerUid} { allow read, write: if false; }
// under /users/{uid}
match /directoryOrders/{orderId}       { allow read: if isSelf(uid); allow write: if false; }
match /devices/{token}                 { allow read, write: if isSelf(uid) && member(); }
match /settings/{doc}                  { allow read, write: if isSelf(uid) && doc == 'notifications'; }
```

## 8. Risks and unknowns

- Cloudways staging may come up with Password Protection on, an `http`-only address, or WooCommerce still pointed at live payment gateways; D0's pass line checks all three.
- Directories Pro's licence is per site; staging usually runs fine unlicensed (no plugin updates), but if the plugin locks, SabaiApps allows a staging activation on request.
- Staging drifts from live; re-clone before big tests. Test users and listings made on staging are wiped by a re-clone, so recreate `+dir1` after one.
- `drts_fields` differs per listing plan; the parser is an allowlist and `wp:probe` prints the keys. Expect one round of field fixes after your first probe.
- Reading WP user emails needs an administrator Application Password; the doctor asserts the role. Guest WooCommerce orders under a different billing email will not link, by design.
- Security plugins or a firewall can strip the Authorization header; the doctor's 401/403 text says which.
- Pending listings through the REST API depend on Directories Pro's capabilities; if they do not come back, the owner sees only published ones and the card says so.
- Adding a `Post` subclass touches every exhaustive switch and the golden screenshots.
- FCM needs a Google Play emulator image; iOS needs a Mac and a real iPhone.
- Cold-start mid-onboarding loses the door choice; both doors remain in Edit profile.

## 9. Order and sizes

Stage 10 → 11 → 12. D0 first, always: nothing else in Stage 10 may start until the doctor confirms the dev project points at staging. D1 next, because it surfaces the WordPress unknowns while nothing depends on them. Stage 11's directory door needs D2. Stage 12 is independent; its Android path is testable on the emulator, N4 last. The Apple console steps can be done any time.

| Checkpoint | Size |
|---|---|
| CP-D0 development WordPress + WooCommerce (Cloudways staging), doctor guard | S (Claude) + ~1 h of your clicks |
| CP-D1 credentials, WP client, doctor, `wp:probe` | S |
| CP-D2 link + orders, directory screen, silent autolink | M |
| CP-D3 listings mirror, contact actions, Add a listing, 6 h re-sync | M |
| CP-D4 `directory` post kind, public profile section, own-profile card | M |
| CP-D5 browse all 1,700 (optional, later) | L |
| CP-O1 "Are you a…" screen, intent plumbing, dead checkbox removed | M |
| CP-O2 auto-check on the Sell / Directory landings | S |
| CP-N0 FCM plumbing, devices, prefs screen, test push, `notify()` choke point | M |
| CP-N1 announcements, topics, `/you/admin`, bell merge | M |
| CP-N2 forum / shoutout / review pushes | M |
| CP-N3 buyer index + new-product trigger | M |
| CP-N4 iPhone | M |

## 10. Verification

Per checkpoint: `scripts\test-all.ps1` green (analyze clean, flutter test, tsc, npm test, plus `npm run test:rules` when rules change) → `scripts\deploy-dev.ps1` → `scripts\doctor.ps1` all PASS (including the staging guard) → your tap-through per the "Grace does / Pass" lines above, on `run-live.ps1` against `little-blue-610e5`, the dev Shopify shop and the staging WordPress → commit and push → tick the box in `Planning/checkpoints.md`. Journeys J12 (directory customer), J13 (directory owner), J14 (onboarding doors), J15 (push) get added to `Planning/manual-test.md`.
