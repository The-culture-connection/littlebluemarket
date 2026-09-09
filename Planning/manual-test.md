# Little Blue Market — the manual test, every journey

*Written for Grace on 2026-09-05. Run it on the Android emulator via `scripts/run-live.sh` in Git Bash or `scripts\run-live.ps1` in PowerShell (since 2026-09-09 that is production data with the developer surfaces on; add `-Dev` for the dev project and test shop). Every step says what to tap, what "pass" looks like, and what to paste to Claude if it fails. Work top to bottom; later journeys assume earlier ones passed.*

**Before you start**

- `scripts/doctor.sh` → 0 FAIL. The four WARN lines are known (store password; three optional Shopify scopes).
- Quit the app and run `scripts/run-live.sh` so the phone has the current build. If a screen described here is missing, that is almost always an old build.
- Test identities: `grace-s@…` (your admin account), `grace-s+buyer1@…`, `grace-s+customer1@…` (has website orders), `grace-s+seller1@…` (claimed seller, vendor `cc`), `grace-s+seller2@…` (new, for the roster and application journeys), `grace-s+dir1@…` (a littlebluecart.com customer and listing owner, on the staging site). Verification mail lands in Spam.
- How to report a failure: tap **Copy for Claude** on the red strip, or copy the Diagnostics report, and paste it with the journey and step number.

---

## J1 · New customer (someone who has never used the website)

1. Open the app → **Create a Profile** → `grace-s+buyer2@…` + a password → Next.
2. **Confirm your email** screen appears. Do not tap anything yet. Open the mail, click the link, come back. Within 5 s the screen says **Confirmed. Thank you.** (or tap **I've confirmed it**). *Pass:* it never skips this screen on its own.
3. Continue → **Set up your profile** → tap the circle or **Add a photo** → Take a photo / Choose from your photos → the picture shows in the circle → **your name** (required since 2026-09-09: the Create button stays off until at least two characters are typed, so nobody is ever shown as "Someone"), handle, bio → Create. *Pass:* Market feed with a **You** tab, your photo on the You tab; no "Confirm your email" banner on the feed.
4. **Cold-start check:** force-close the app mid-way (after step 1, before step 2) and reopen. *Pass:* it opens on the Confirm your email screen, not the market.
5. **Unconfirmed member check:** sign out, Create a Profile with `grace-s+buyer3@…`, tap **Continue for now** on the confirm screen, finish setup. *Pass:* the feed shows a **Confirm your email** card with **I've confirmed it** and **Resend**; buying, posting and commenting still work; Edit profile → Sell with us keeps "Check my seller status" disabled until the email is confirmed.
6. Edit profile → **City, State** = `Detroit, MI` → Save. *Pass:* saved; Diagnostics shows nothing red. (This powers Near me later.)

## J2 · Existing customer (has bought on the website before)

1. Create a Profile with `grace-s+customer1@…` (the email on the Shopify customer) → confirm the email → finish setup.
2. *Pass:* within ~10 s the profile's **Bought & received** tab lists the website orders; Diagnostics shows **Linked to the store: yes**. Nothing to tap: the link runs on its own once the email is confirmed.
3. Place an order **on the website** with that email (dev store, test card 4242…). *Pass:* it appears under Bought within a minute (attributed by email).
4. Tap a purchase on Bought → **Write a review** / **View product** sheet appears.

## J3 · Buying in the app

1. As any confirmed member: Market → a listing card → tap the **cart** icon. *Pass:* the icon fills purple; the tip dialog appears the first time; "N added" under the card ticks up a second later.
2. Tap the filled cart again → *Pass:* "Removed from your cart", icon empties. Add it again.
3. Cart → **Checkout** → the Shopify checkout opens in-app (password page workaround if the dev store asks: enter it, close, tap Open checkout again) → pay with 4242 4242 4242 4242 → close. *Pass:* the cart says "Thanks! We'll confirm shortly"; within a minute Bought shows the item; the seller's **Total sales** rises.
4. Cart → **Post my cart** → caption → Post it. *Pass:* the cart post is in the feed with **Add all to my cart**; from another account tapping it adds the items ("Added N to your cart").

## J4 · Existing seller (already a vendor in Shipturtle)

1. Create a Profile with the email you use in Shipturtle (`grace-s+seller2@…`) → confirm the email → finish setup. **Change photo** on Edit profile asks Take a photo / Choose from your photos and the new face shows at once (the emulator's camera gives a test scene; the gallery may be empty).
2. Edit profile → **Sell with us** → **Check my seller status**. *Pass:* "You now sell as <brand>", where the brand is the company's **Brand name** in Shipturtle (the vendor string Shopify uses); back on the profile the **Products** tab is there, and Edit profile shows the seller rows. No code, no restart, no waiting: the check asks Shipturtle fresh every time, so a vendor approved a minute ago passes.
3. If it says the email is not on the vendor list: the email on the Shipturtle vendor user differs from the one you signed up with. Fix it in Shipturtle, then tap again. A company with no brand name and no products yet cannot be granted; give it a brand name in Shipturtle. **I have a claim code** on the same page is the manual way in.
4. Products tab → **Add a product** → photo (Take a photo works on the emulator; Choose from your photos needs pictures in the gallery), title, price, quantity, Category, a collection → **Add to my shop**. *Pass:* Under review modal; the draft with an **Under review** chip; in Shopify a Draft product under your vendor.
5. Shopify admin → set it **Active**. *Pass:* chip turns **Live**; product buyable in the app.
6. **Edit** on a product → change price/stock → Save changes. *Pass:* "Saved to the store", variants intact in Shopify.
7. Post → A good or a service → pick a product → caption with `@` + a buyer's handle → Post it. *Pass:* in the feed; the buyer gets a bell notification.

## J5 · New seller (not in Shipturtle yet)

1. As a confirmed buyer: Edit profile → **Sell with us** → **Apply on our website**. *Pass:* the store's Become a vendor page opens in the browser. Fill it in there.
2. You (Little Blue Market) approve the vendor in Shipturtle. The company needs a **Brand name** (that becomes their vendor string on Shopify) and a vendor user with the applicant's email. No products are needed first.
3. The applicant: Sell with us → **Check my seller status**. *Pass:* "You now sell as <vendor>"; Products tab appears. Then J4 steps 4–7 work for them.
4. Six hours later at the latest the same grant would have happened on its own (the roster sweep), so a seller who never taps the button still becomes one.

## J6 · Shipping (handled entirely in Shipturtle, 2026-09-08)

*The Packages screen is gone, along with every "on its way" line. Shipping is Shipturtle's and the store's emails; the app only opens the door for sellers.*

1. **Buyers** hear from the store by email. In the app a purchase under Bought says "Ordered N days ago" until it is delivered, then "Received N days ago". There is no tracking screen and no shipping icon on the profile.
2. **Sellers** manage orders and shipping in Shipturtle: Edit profile → **Orders & shipping** opens the vendor dashboard in the browser. Add tracking to an app order there; the buyer hears about it by email.
3. **Delivered:** the store's fulfilment reaches the app on its own (or ask Claude to run `npm run replay-order -- --order <number> --deliver`). *Pass:* the purchase under Bought reads Received; the feed shows **How was it?**; tapping the purchase offers Write a review.

## J7 · Reviews

1. From **How was it?** or Bought → a purchase → **Write a review** → stars, text (optionally `@` someone) → Post review.
2. *Pass:* the review is on the product page under Reviews within seconds, the stars and count update without leaving the page, the review is in the feed as its own post, the purchase shows **Reviewed**, and a mentioned member gets a notification.

## J8 · Search and Near me

1. Search → `snowboard` → real products. `balm mint` (out of order) → the lip balm. A word that is only in a product's **description** → that product (descriptions are searched too). `zzzz` → "Nothing for zzzz" with **Did you mean** chips. Tap a chip → results or a collection.
2. **Hashtags.** Every store tag on a product is a hashtag now ("feminist gift" on Shopify is `#FeministGift` in the app), and any `#tag` typed into a shoutout, review, cart post or listing caption counts too. Market → the hashtag rail under the search pill shows the popular ones → tap one → results. Search → `#sport` (lowercase is fine) → the products tagged Sport. Post a shoutout with `#Detroit` in it → search `#detroit` → the shoutout's tag is found and the rail gains #Detroit. *Pass:* results, not "Nothing for #…". Empty rail and empty results everywhere → Claude runs `npm run touch-products` to re-mirror the catalog.
3. **Near me** on the emulator: first set a location (the emulator's ⋯ → Location → pick a point, e.g. Detroit → Set location; or Claude runs `adb emu geo fix -83.0458 42.3314`), then Market → **Near me**. The first time Android asks for permission. *Pass:* "Near Current location" within a few seconds, and results narrow to sellers whose profile City is nearby. With no fix on the phone it uses your own profile City; with neither it stays off, says so, and the message has an **Add my city** button. A slow fix is not an error any more: nothing red appears for it.

## J9 · Community and messages

1. **Chatroom:** Community → type a message → send. From the other account it appears within seconds.
2. **Forums:** Community → Forums → create a forum → open it → start a thread → from the other account, join the forum (member count moves) and comment on the thread (comment count moves).
3. **Direct messages:** open a seller's storefront → the envelope → send a message. As the seller: You → the envelope badge → reply. *Pass:* both sides see the thread; unread badge clears when opened.
4. **Comments:** on any feed post → Comments → write one. *Pass:* it appears; "M comments" ticks up a moment later; the post's author gets a notification; the heart on a comment toggles.

## J10 · Shoutouts with a photo

1. You → **Post → A shoutout** → **Add a photo** → pick one → type text with `@` + a seller's handle (pick from the suggestions) → Post shoutout.
2. *Pass:* the feed card shows the photo above the text; the handle is bold and tappable (opens the storefront); **Visit the storefront** works; the mentioned seller has a notification.

## J11 · Admin

1. As `grace-s@…`: Edit profile → Diagnostics (dev builds) → Claim admin (once) → Sync collections, Backfill catalog, Set seller vendor, Try publish. Edit profile → **Seller applications** (release builds too).
2. **Sending a push to everyone or to a role:** in the app, Edit profile → **Admin** (the row shows only for an admin account) → title, message, Who, Send; or from a laptop on the admin website (J15 step 20). Both call the same function.
3. From the repo when something looks wrong: `npm run peek -- --reviews`, `npm run peek -- --doc catalog/<id>`, `npm run inspect:product -- --id <id>`, `npm run shipturtle:vendors`, `npm run move-stock -- --vendor <v> --to <location>`, `npm run replay-order -- --order <n> [--deliver|--ship]`.

## J12 · Directory customer (has bought on littlebluecart.com)

*Needs CP-D0 and CP-D1 done: the staging WordPress, the three secrets, and a deploy. On the **staging** site: a WP user `grace-s+dir1@…` (Subscriber) with one completed WooCommerce order (WooCommerce → Orders → Add order → that customer → any product → Status Completed).*

1. Create a Profile with `grace-s+dir1@…` → confirm the email → finish setup.
2. You → Edit profile → **Little Blue Cart directory**. *Pass:* the card already says **Linked** (the link ran on its own once the email was confirmed) and **Orders from littlebluecart.com** lists the order with its number, date, total and status. If it says "Bought or listed on littlebluecart.com?" instead, tap **Link my directory account**: the line under the button reads "Linked. 1 order and 0 listings found."
3. Tap the order. *Pass:* the browser opens the order on the staging site's My account page (a login box there is fine).
4. Tap **Refresh** straight away. *Pass:* "Checked a few minutes ago. Try again in a few minutes." (the ten-minute limit).
5. Sign in as `grace-s+buyer1@…` (no WordPress account) → Edit profile → Little Blue Cart directory → **Link my directory account**. *Pass:* "No account at littlebluecart.com uses this email…" and no red strip.
6. If step 2 finds nothing for `+dir1`: in `REPO\functions\` run `npm run wp:probe -- --email grace-s+dir1@the-culture-connection.com` and paste the block. It says whether the site has the user, the customer and the order.

## J13 · Directory owner (a business listed on littlebluecart.com)

*Needs J12's setup, plus a listing: on the **staging** site, logged in as `grace-s+dir1@…`, Add Your Business → Free plan → business name, website, phone, address, one category, one state, one ownership tag → submit. It sits in Pending until you publish it as WP admin.*

1. As `+dir1` in the app: Edit profile → **Little Blue Cart directory** → **Refresh**. *Pass:* **My listings** shows the business with an **Under review** chip, its category, state and ownership-tag chips, the address, and Website / Call / Email / Directions buttons (only the ones the listing has).
2. Tap **Website** (the business site opens in the browser), **Call** (the dialler opens with the number), **Email** (the mail app opens), **Directions** (Maps opens on the address). *Pass:* each opens the right app; nothing says "Could not open".
3. On staging as WP admin: Directory → Listings → Pending → publish the listing. In the app: **Refresh** (after the ten-minute limit, or force-close and reopen the app). *Pass:* the chip reads **Published**. Firebase console: `directoryListings/<postId>` has `status: publish`, `ownerUid` = your uid, and `categories`, `tags`, `locations` as names, not numbers.
4. Tap **Add a listing**. *Pass:* the browser opens the staging site's Add Your Business page.
5. Leave it: within six hours (`directorySyncScheduled`) an edit made to the listing on the website reaches the card without a tap.
6. **Everyone sees it (CP-D4).** Sign in as `grace-s+buyer1@…` → Market feed: a post by `+dir1` shows the business card (name, category, state, ownership tags, Website / Call / Email / Directions). Tap the avatar → the profile shows a **Little Blue Cart directory** section with the same card. *Pass:* a pending listing never appears for the buyer; unpublishing it on staging removes the post within six hours (or on the owner's next Refresh). Back as `+dir1`: the You tab shows a **Little Blue Cart directory** row under the profile header with the listing and order counts.
7. If the card is missing or a field looks wrong: `npm run wp:probe -- --email grace-s+dir1@the-culture-connection.com` and paste the block (it prints the listing's status and its field names; the Free plan may carry different fields than the recorded Showcase one).
9. **Products sold on your website (CP-E2).** Directory → **My products (sold on my website)** → **Add a product** → a photo, a name, a price (or leave it empty for "See website"), a few words; the buy address is already your listing's website → **Add to my profile**. *Pass:* it is listed under My products; it is in the Market feed as a listing post with **Buy on their website**; opening it shows the product page with one **Buy on their website** button and no cart icon; tapping it opens your site in the browser. Tap the product under My products → change the price → **Save changes**; then **Remove this product** → it leaves the feed.
10. As `+buyer1`: open the same post. *Pass:* Buy on their website opens the site; there is no Add to cart anywhere on it; the seller strip shows the business name from the listing.
11. If **Add a product** says "Only businesses in the Little Blue Cart directory can add products this way" → the account is not linked (step 1 of J12).
12. **The Products tab (CP-E3).** As the directory account: the You tab now has **Products · Posted · Bought**. Products shows the listing's photo strip on top (when the listing has a photo), then **Add a product (sold on my website)**, then the website-link products three across; tapping one opens its edit form. As `+buyer1` on that profile: the same strip and grid, tapping a product opens its page with Buy on their website. As `+seller1` (a Market seller) after linking a directory listing: Products shows the strip, the Shopify grid, then a small "Sold on your website" heading and the website-link products; nothing is removed.
13. **Apply from Edit profile (CP-E4).** Edit profile → **List my business in the directory**. *Pass:* the browser opens littlebluecart.com/add-directory-listing/.
14. **"Did you buy it?" (CP-E5).** As `+buyer1` (signed in, not a guest): open a website-link product → **Buy on their website** → the browser opens → switch back to the app. *Pass:* a dialog **Did you buy it?**; **Yes, I bought it** → toast "Added under Bought on your profile."; You → Bought shows the product with the business as the seller; tapping it offers Write a review. Do it again and pick **Not this time**: Bought is unchanged. Firestore: `users/<uid>/purchases/website_<id>_<time>` with `selfReported: true`. If no dialog appears: you were a guest, or the browser never opened ("Could not open …").
8. **The listing fills the profile (CP-E1).** The first successful link with a listing did this by itself; to see it again: Directory → **Use my directory listing**. *Pass:* a toast "Your profile now reads as FoundHouse (@foundhouse)"; the You tab shows the business name, the handle, the description and website in the bio, the category as a hashtag, and City, State from the listing's location (Edit profile → City, State shows it; Near me in J8 measures from it). Edits you make afterwards in Edit profile stay until you tap the button again. *(Your own account on the live site: the listing is FoundHouse, so this renames your account to FoundHouse; use Edit profile to put it back if you want your name on it.)*

## J14 · The seven doors (onboarding)

*The welcome artwork is unchanged: **Sign in** is "returning to the app"; **Create a Profile** now opens **Are you…** with seven doors under Shopping and Selling. The door only decides where you land first; every landing screen is also in Edit profile.*

1. Sign out → Welcome → **Create a Profile**. *Pass:* the blue **Are you…** screen with seven rows and "I already have a profile" underneath. The **Sign in** hotspot still opens Welcome back directly.
2. **I'm new here** → a fresh `+buyer4@…` → confirm → handle → Create a profile. *Pass:* lands on the Market feed.
3. **My business is listed in the directory** → `+dir1@…` (delete that account in the Firebase console first if it exists) → confirm → handle → Create. *Pass:* lands on **Little Blue Cart directory** and the link runs by itself ("Linked. …" appears with no tap).
4. **I sell on Little Blue Market** → `+seller1@…` (delete the account first) → *skip* confirming with **Continue for now** → handle → Create. *Pass:* lands on **Sell with us** with the Confirm-your-email card and a disabled Check button. Open the mail, click, tap **I've confirmed it** → the check runs by itself → "You already sell as …".
5. **I want to sell on Little Blue Market** → any fresh address → confirm → Create. *Pass:* lands on Sell with us and the browser opens the Become a vendor page once; back in the app the page is still there.
6. **I want to list my business in the directory** → any fresh address → confirm → Create. *Pass:* lands on Little Blue Cart directory and the browser opens the staging Add Your Business page once; the card underneath says to come back and tap Refresh.
7. **I've bought on Little Blue Market** → `+customer1@…` (delete first) → confirm → Create. *Pass:* lands on your profile with the **Bought** tab open and the website orders in it.
8. **Cold start mid-way:** pick any Selling door, enter the email, then force-close before confirming. Reopen. *Pass:* the Confirm screen, then setup, then the Market (the door is lost on a cold start, on purpose; the screen you wanted is in Edit profile).

## J15 · Push notifications

*The emulator must be a **Google Play** image, Android 13 or newer (Android Studio → Device Manager → Create device → a system image marked "Google Play"). The doctor's `android push` line says whether the running one has Play services; without them nothing ever arrives and nothing says why.*

1. `scripts\deploy-dev.ps1` → `run-live.ps1` → sign in as `grace-s+buyer1@…` → Edit profile → **Notifications** → **Allow notifications** → Allow on Android's prompt. *Pass:* the card reads "Allowed on this phone." and Firestore shows `users/<uid>/devices/<token>` with `platform: android`.
2. **Send me a test notification** → press the emulator's Home button. *Pass:* a banner "Little Blue Market — This phone is set up for notifications." with the cart icon; tapping it opens the app on the bell.
3. With the app open in the foreground, send the test again. *Pass:* the banner still appears (the app draws it itself when it is in front).
4. As `+seller1` post a shoutout that tags `@buyer1`. *Pass:* buyer's phone: "<seller name> mentioned you" as a push, and the same line under the bell; tapping the push opens that post.
5. Notifications → switch **Mentions and shoutouts** off → repeat step 4. *Pass:* the bell still shows it, the phone stays silent. Switch it back on.
6. Sign out. *Pass:* Firestore `users/<uid>/devices` is empty for that account (the phone forgets itself before it signs out).
7. If nothing arrives: the doctor's `android push` line (Play services), `firebase functions:log --only pushTestMe --project dev` (a `registration-token-not-registered` means the token was stale and has been pruned; tap Allow again), or Copy for Claude.
8. **Announcements (CP-N1).** As `grace-s@…` (admin; Claim admin in Diagnostics if the row is missing): Edit profile → **Admin** → title "Hello from Little Blue Market", message "Testing announcements", Who: **Everyone**, A tap opens: **The bell** → **Send** → Send. Background the app. *Pass:* the push lands on this phone and on any other signed-in test phone; the bell shows it at the top with the megaphone icon; Firebase console `announcements/<id>` has `messageId` and `sentAt`.
9. Send another with Who: **Sellers**. *Pass:* `+seller1`'s phone gets it; `+buyer1`'s stays silent and their bell does not list it. Opening the bell clears the unread tint on announcements too.
10. If the push never lands but the bell has it: the phone was not subscribed to the topic yet; sign out and in once (the topics follow the session), then `firebase functions:log --only adminSendAnnouncement --project dev`.
11. **Forums (CP-N2).** `+buyer1` joins a forum; `+seller1` starts a thread there. *Pass:* buyer's phone: "<seller> started a thread" with the title; tapping opens that thread. `+buyer1` replies; then `+customer1` (not a member of the thread yet) replies. *Pass:* seller (the author) and buyer (an earlier commenter) get "<customer> replied"; `+customer1` gets nothing; nobody gets pushed for their own reply.
12. **Reviews.** `+buyer1` reviews one of `+seller1`'s products. *Pass:* seller's phone: "<buyer> reviewed your product" with the stars and the product name; tapping opens the review post.
13. **Shoutout about a seller.** `+buyer1` posts a shoutout that picks `+seller1` as the seller it is about (without typing `@seller1`). *Pass:* seller's phone: "<buyer> mentioned you" with "Gave you a shoutout: …"; only once, even when the shoutout also @-mentions them.
14. Wrong people, or nobody: `firebase functions:log --only onThreadCommentWritten --project dev` (or `onThreadWritten`, `onReviewWritten`, `onPostWritten`) and paste.
15. **New from a shop you bought from (CP-N3).** As admin: Edit profile → Admin → **Rebuild buyer index**. *Pass:* "Indexed N shop–buyer pairs across M people." As `+seller1`: Products → Add a product → fill it in → Add to my shop; then in the Shopify admin set that product **Active**. `+buyer1` (who bought from `+seller1` in J3) has the app in the background. *Pass:* buyer's phone: "New from <shop>: <title>"; tapping opens the product; `+customer1` (never bought from that shop) gets nothing; the bell lists it under "added something new".
16. Set the same product to Draft and back to Active in Shopify. *Pass:* no second push (the product is stamped `announcedAt` in `catalog/<id>`). If nothing arrived in step 15: `npm run inspect:product -- --id <id>` (was it Active with a vendor that maps to `+seller1`?), then `firebase functions:log --only onCatalogWritten --project dev`.
17. **iPhone (CP-N4, on a Mac with Xcode and a real iPhone).** In the repo: `flutterfire configure --project=little-blue-610e5 --platforms=ios` (writes `ios/Runner/GoogleService-Info.plist`; commit it, it is public config). Apple Developer → Identifiers → `com.littleblue.market` → tick **Push Notifications** → Save; Keys → **+** → `LBM FCM` → tick **Apple Push Notifications service (APNs)** → Register → **Download** the `.p8` once (keep it in `PARENT\`, never in the repo), note the Key ID and your Team ID. Firebase console → Project settings → **Cloud Messaging** → Apple app configuration → **Upload** the `.p8` with Key ID and Team ID. Xcode → `ios/Runner.xcworkspace` → Runner → Signing & Capabilities → your Team; **Push Notifications** and **Background Modes → Remote notifications** are already listed (pre-wired). iPhone plugged in: `flutter run --dart-define=LBM_BACKEND=live -d <iphone>` → Edit profile → Notifications → **Allow** → **Send me a test notification** → lock the phone. *Pass:* the banner on the lock screen; an announcement sent from the Android emulator lands on the iPhone too; Firestore `devices/<token>` shows `platform: ios`.
18. If the iPhone stays silent: Xcode's console says `no valid "aps-environment" entitlement` → the capability is not on the signed build (Signing & Capabilities, step 17). `firebase functions:log --only pushTestMe` says `messaging/third-party-auth-error` → the `.p8`, Key ID or Team ID do not match the bundle id's team. Nothing and no error → it is a Simulator; APNs needs a real device.
19. **Asked at start-up (CP-N5).** Uninstall the app from the emulator (long-press the icon → App info → Uninstall) so it forgets its answer, then `run-live.ps1`. *Pass:* Android's "Allow Little Blue Market to send you notifications?" appears over the welcome artwork before you sign in; Allow; after signing in, Edit profile → Notifications already reads "Allowed on this phone."; the next launch does not ask again. Say **Don't allow** instead on a fresh install: nothing asks again, and Notifications → **Allow notifications** opens App info to turn it on.
20. **The admin website (CP-N6).** Once, from the README in `little_blue_market\admin-web\`: Railway → New Project → Deploy from GitHub repo → this repo → Settings → Root Directory `little_blue_market/admin-web` → Networking → Generate Domain; Firebase console → Authentication → Settings → Authorized domains → Add domain → that address. Open it → sign in as `grace-s@…` → "Hello from the website", Everyone → **Send** → OK. *Pass:* "Sent to everyone.", the push lands on the signed-in test phone, the announcement is in the page's Recent list and in the app's bell. Sign out and in as `+buyer1` on the website: only "Admins only" shows. Before Railway, the same page runs on your computer: `cd little_blue_market\admin-web`, `npm install`, `npm start`, http://localhost:3000.

---

## J16 · Polish: bug button, splash, bio links, first-time tour (2026-09-08)

1. **Splash and icon (CP-F2).** After a fresh `run-live`, the app icon on the home screen is the cart on blue (Android shapes it round or squircle; the wheels stay inside). Force-close the app and open it. *Pass:* blue immediately, the cart-and-wordmark artwork for about a second and a half, then the welcome screen, no white flash. On the welcome screen the cart rolls in, bounces, and the wordmark appears (your `Body.gif`); the three buttons under it are drawn by the app, sharp at any size, and work from the first frame. (Android 12+ draws the app icon on the blue first; that is the phone's own splash.)
2. **Bug button (CP-F1).** As `+buyer1`, open any product → the small round button at the bottom right → **Something is broken** → "The price looks wrong" → **Send**. *Pass:* the sheet showed a thumbnail of the product page; toast "Sent. Thank you for telling us." Try it from inside a sheet (the cart) and as a guest: both work. On the welcome screen the button is not there.
3. As `grace-s@…`: Edit profile → **Admin** → **Bugs and critiques**. *Pass:* the note is listed with its thumbnail, "Bug", the sender's name, the route and "android"; tapping the thumbnail shows the full screenshot; **Mark done** moves it under **Show done**; **Reopen** brings it back. On the admin website (J15 step 20) the same list, the same buttons, the picture opens in a new tab.
4. If the note arrives without a picture: the phone refused the capture (rare; the note still counts). If nothing arrives: Copy for Claude from the sheet's red line.
5. **Bio links (CP-F3).** Edit profile → Bio → add "Shop at www.littlebluecart.com" → Save → You tab. *Pass:* the address is underlined, tapping it opens the browser, the rest of the bio is plain. Open your profile from another account: the same.
7. **Reporting and bans (CP-F5).** As `+buyer1`: open `+seller1`'s profile → the **…** button top right → **Report @seller1** → pick a reason → Send. *Pass:* "Reported. Thank you." Open one of their posts → **…** → **Report this post** → Something else → a sentence → Send. As a guest, the same … → Report opens the make-a-profile sheet instead. As `grace-s@…`: Edit profile → Admin → **Reports about members**. *Pass:* both reports, open, with reason, reporter and (for the post) **Open the post**; **Resolve** moves one under Show closed; **Ban @seller1** → confirm → both read Banned, `+seller1`'s posts leave the feed, signing in as `+seller1` says the account is suspended; **Unban** lets them sign in again (posts stay gone). The admin website shows the same rows with the same buttons.
8. **Notify me (CP-F6).** As `+buyer1`: open `+seller1`'s profile → **Notify me**. *Pass:* "You will hear when they post." and the button reads **Notifying you**; Edit profile → Notifications shows **Posts from people you follow** on. Background the app; as `+seller1` post a listing or a shoutout. *Pass:* buyer's phone shows "<seller> posted" with the post's first line; tapping opens the post; the bell has "<seller> posted something new". Tap **Notifying you** to unfollow and post again: nothing arrives. As a guest, **Notify me** opens the make-a-profile sheet.
6. **First-time tour (CP-F4).** Uninstall and reinstall the app (the phone remembers the tour), then Create a Profile with a fresh `grace-s+tour1@…` → confirm → handle → Create a profile. *Pass:* a five-page card appears over the feed (Welcome, Find what is near you, Join the community, Your profile, Tell us what you think); **Next** pages, **Done** closes; kill and reopen: nothing; sign out and make another profile on the same phone: nothing. A guest never sees it; an existing account that only signs in never sees it.

## J17 · Production (2026-09-08)

*Everything here runs against little-blue-cart-prod and the REAL shop. `run-prod.ps1` (or a plain `flutter run`) is the production app; `run-live.ps1` is the same production data with the developer surfaces on; `run-live.ps1 -Dev` is the dev project.*

1. **Console, once:** Firebase console → little-blue-cart-prod → Blaze plan; Authentication → Sign-in method → Email/Password on, Anonymous on; Authentication → Settings → Authorized domains → add the Railway domain of the admin website.
2. `scripts\doctor-prod.ps1`. *Pass:* 0 FAIL; `env params … (the real shop)`; `secrets all 8 exist`; `auth providers` green. If `SHOPIFY_LOCATION_ID` is reported empty, take the online-fulfilment location id it prints, put it in `functions\.env.little-blue-cart-prod`, then `scripts\deploy-prod.ps1`.
3. `scripts\run-prod.ps1`. *Pass:* splash → welcome; **no** "DEV · …" badge in the corner, **no** error strip at any point; Sign in with a wrong password says only "That email and password do not match".
4. Create a Profile with `grace-s@…` → confirm → handle → Create. *Pass:* the tour shows once; Edit profile shows **Staff tools** (your domain) but no Admin row yet.
5. Staff tools → **Claim admin** (your address must be in the prod project's `_internal/admins` document, as on dev) → **Sync collections** → **Backfill catalog**. *Pass:* "Admin claim granted"; back in Edit profile the **Admin** row is there; the Market feed fills with the real catalog within a minute.
6. Sign in as a test account on another email domain. *Pass:* no Staff tools row, no Admin row.
7. Admin website: open the Railway address → sign in as `grace-s@…` → send "Hello" to Everyone. *Pass:* it lands on the phone signed in to the production app; the Recent list shows it; Firestore (prod) `announcements/<id>`.
8. **iPhone, first production run (2026-09-09 fixes).** Near me now asks for location the first time (iOS needed the reason strings in `Info.plist`; camera and photo library have theirs too). A tap anywhere outside a text field closes the keyboard. Searching people by handle works on production (its index was missing there). Push: after **Allow notifications** the app waits up to six seconds for Apple's push token; on a developer build (`run-live-mac.sh`) a missing token shows on the error strip with the reason (no push capability on the signed build, or no APNs key on the project). The "find devices on your local network" prompt is Xcode's debugger, not the app: it does not appear in a release or TestFlight build.
9. Anything red on the phone shows only the friendly line now. To see the raw cause and Copy for Claude, reproduce it on `run-live.ps1` (dev) or run `flutter run --dart-define=LBM_DEV=true` against prod, which is the production backend with the developer surfaces on.

---

### If a journey fails

Paste the **Copy for Claude** block (or the doctor output) and say the journey and step, e.g. "J5 step 2". Claude names the file and line, quotes the message, gives one command, and stops.
