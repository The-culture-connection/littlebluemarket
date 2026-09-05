# Little Blue Market — the manual test, every journey

*Written for Grace on 2026-09-05. Run it on the Android emulator against the real dev project (`scripts/run-live.sh` in Git Bash, or `scripts\run-live.ps1` in PowerShell). Every step says what to tap, what "pass" looks like, and what to paste to Claude if it fails. Work top to bottom; later journeys assume earlier ones passed.*

**Before you start**

- `scripts/doctor.sh` → 0 FAIL. The four WARN lines are known (store password; three optional Shopify scopes).
- Quit the app and run `scripts/run-live.sh` so the phone has the current build. If a screen described here is missing, that is almost always an old build.
- Test identities: `grace-s@…` (your admin account), `grace-s+buyer1@…`, `grace-s+customer1@…` (has website orders), `grace-s+seller1@…` (claimed seller, vendor `cc`), `grace-s+seller2@…` (new, for the roster and application journeys). Verification mail lands in Spam.
- How to report a failure: tap **Copy for Claude** on the red strip, or copy the Diagnostics report, and paste it with the journey and step number.

---

## J1 · New customer (someone who has never used the website)

1. Open the app → **Create a Profile** → `grace-s+buyer2@…` + a password → Next.
2. **Confirm your email** screen appears. Do not tap anything yet. Open the mail, click the link, come back. Within 5 s the screen says **Confirmed. Thank you.** (or tap **I've confirmed it**). *Pass:* it never skips this screen on its own.
3. Continue → **Set up your profile** → handle, bio → Create. *Pass:* Market feed with a **You** tab; no "Confirm your email" banner on the feed.
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
2. **Near me** on the emulator: first set a location (the emulator's ⋯ → Location → pick a point, e.g. Detroit → Set location; or Claude runs `adb emu geo fix -83.0458 42.3314`), then Market → **Near me**. The first time Android asks for permission. *Pass:* "Near Current location" within a few seconds, and results narrow to sellers whose profile City is nearby. With no fix on the phone it uses your own profile City; with neither it stays off, says so, and the message has an **Add my city** button. A slow fix is not an error any more: nothing red appears for it.

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

---

### If a journey fails

Paste the **Copy for Claude** block (or the doctor output) and say the journey and step, e.g. "J5 step 2". Claude names the file and line, quotes the message, gives one command, and stops.
