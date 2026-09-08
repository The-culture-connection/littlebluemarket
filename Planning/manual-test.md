# Little Blue Market — the manual test, every journey

*Written for Grace on 2026-09-05. Run it on the Android emulator against the real dev project (`scripts/run-live.sh` in Git Bash, or `scripts\run-live.ps1` in PowerShell). Every step says what to tap, what "pass" looks like, and what to paste to Claude if it fails. Work top to bottom; later journeys assume earlier ones passed.*

**Before you start**

- `scripts/doctor.sh` → 0 FAIL. The four WARN lines are known (store password; three optional Shopify scopes).
- Quit the app and run `scripts/run-live.sh` so the phone has the current build. If a screen described here is missing, that is almost always an old build.
- Test identities: `grace-s@…` (your admin account), `grace-s+buyer1@…`, `grace-s+customer1@…` (has website orders), `grace-s+seller1@…` (claimed seller, vendor `cc`), `grace-s+seller2@…` (new, for the roster and application journeys), `grace-s+dir1@…` (a littlebluecart.com customer and listing owner, on the staging site). Verification mail lands in Spam.
- How to report a failure: tap **Copy for Claude** on the red strip, or copy the Diagnostics report, and paste it with the journey and step number.

---

## J1 · New customer (someone who has never used the website)

1. Open the app → **Create a Profile** → `grace-s+buyer2@…` + a password → Next.
2. **Confirm your email** screen appears. Do not tap anything yet. Open the mail, click the link, come back. Within 5 s the screen says **Confirmed. Thank you.** (or tap **I've confirmed it**). *Pass:* it never skips this screen on its own.
3. Continue → **Set up your profile** → tap the circle or **Add a photo** → Take a photo / Choose from your photos → the picture shows in the circle → handle, bio → Create. *Pass:* Market feed with a **You** tab, your photo on the You tab; no "Confirm your email" banner on the feed.
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

## J6 · Shipping

1. **Buyers** hear from the store by email. You → Packages shows "Check your email for shipping updates" and, below, anything with tracking under **On its way to you**.
2. **Sellers** manage shipping in Shipturtle: You → Packages → **Open Shipturtle** opens the vendor dashboard. Add tracking to an app order there.
3. Within 15 minutes the buyer's Packages screen shows the tracking with a progress bar. (The pull runs every 15 minutes on its own.)
4. **Delivered:** ask Claude to run `npm run replay-order -- --order <number> --deliver`. *Pass:* Packages shows **Delivered**; the feed shows **How was it?**; the Bought tab tap offers Write a review.

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
2. From the repo when something looks wrong: `npm run peek -- --reviews`, `npm run peek -- --doc catalog/<id>`, `npm run inspect:product -- --id <id>`, `npm run shipturtle:vendors`, `npm run move-stock -- --vendor <v> --to <location>`, `npm run replay-order -- --order <n> [--deliver|--ship]`.

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

---

### If a journey fails

Paste the **Copy for Claude** block (or the doctor output) and say the journey and step, e.g. "J5 step 2". Claude names the file and line, quotes the message, gives one command, and stops.
