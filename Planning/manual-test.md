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
5. **Unconfirmed member check:** sign out, Create a Profile with `grace-s+buyer3@…`, tap **Continue for now** on the confirm screen, finish setup. *Pass:* the feed shows a **Confirm your email** card with **I've confirmed it** and **Resend**; buying, posting and commenting still work; Edit profile → Start selling says confirm first.
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

*Two ways in. A claim code is the manual one; the roster is the automatic one.*

**A. Roster (automatic, Stage 8).**
1. In Shipturtle, make sure the vendor's user email is `grace-s+seller2@…` and the company's products carry one vendor string.
2. In the app, Create a Profile with that email → confirm → finish setup.
3. *Pass:* within a minute the profile shows the **Products** tab with that vendor's products; Edit profile shows Payouts & bank / Sales & shipping. Diagnostics → **Link my store account now** reports "granted as <vendor>" if you want to see it in words. If it reports a reason instead (no products yet, two companies on one email, string already claimed), that reason is the truth and the way in is B or J5.

**B. Claim code (manual).**
1. From the repo: `cd functions && npm run shipturtle:vendors` → note the vendor string for the seller's company. `scripts/issue-claim-code.ps1 -Vendor "<that string>" -Email grace-s+seller3@…` → create the printed Firestore document.
2. In the app as `+seller3`: Edit profile → **Start selling** → the code → Claim my shop. *Pass:* "You are now selling as <vendor>"; Products tab appears; no restart.

**Then, as the seller:**
3. Products tab → **Add a product** → photo, title, price, quantity, Category (type "sweat", pick one), a collection chip → **Add to my shop**. *Pass:* Under review modal; the draft on the Products tab with an **Under review** chip; in Shopify a Draft product under the right vendor.
4. Shopify admin → set it **Active**. *Pass:* the chip turns **Live** within seconds; the product is in the feed and buyable (it is published to the app's channel automatically).
5. **Edit** on a product → change price/stock → Save changes. *Pass:* "Saved to the store", both variants intact in Shopify.
6. Post from the profile: **Post → A good or a service** → pick a product → caption with `@` + a buyer's handle → Post it. *Pass:* the post is in the feed; the mentioned buyer sees a bell badge and the notification.

## J5 · New seller (not in Shipturtle yet)

1. As a confirmed member with no shop (`+buyer2`): Edit profile → **Apply to sell** → shop name, link, note → Send my application. *Pass:* the status card reads **Under review**; Edit profile's Apply row says Under review; sending again is refused.
2. As the admin (`grace-s@…`): Edit profile → **Seller applications** → the application → **Approve…** → vendor string (the one the shop will sell as on the store; for a brand-new shop choose it now, e.g. the shop name) → Approve and grant. *Pass:* "<shop> now sells as …".
3. Back as the applicant: pull down on the profile. *Pass:* Products tab appears, Edit profile shows the seller rows, Apply to sell shows **Approved**. Then J4 steps 3–6 work for them.
4. **Decline path:** a second applicant → Decline… with a reason. *Pass:* their status card shows "Not approved: <reason>".

## J6 · Shipping

1. **Vendor ships from Shipturtle:** in the Shipturtle vendor panel, add tracking to an app order. Wait up to 15 minutes, or You → Packages → **Sending** → **Check with Shipturtle**. *Pass:* buyer's **Receiving** shows the tracking and a progress bar; the seller's Sending card shows "Shipturtle: payout pending".
2. **Seller ships from the app:** You → Packages → **Manage sales** → order number, tracking, courier → Add tracking. *Pass:* "Tracking added"; buyer's Receiving shows it. With the two fulfilment-order scopes granted, Shopify shows the order Fulfilled too.
3. **Delivered:** ask Claude to run `npm run replay-order -- --order <number> --deliver`. *Pass:* Receiving shows **Delivered**; the feed shows **How was it?**; Bought tab tap → Write a review.

## J7 · Reviews

1. From **How was it?** or Bought → a purchase → **Write a review** → stars, text (optionally `@` someone) → Post review.
2. *Pass:* the review is on the product page under Reviews within seconds, the stars and count update without leaving the page, the review is in the feed as its own post, the purchase shows **Reviewed**, and a mentioned member gets a notification.

## J8 · Search and Near me

1. Search → `snowboard` → real products. `balm mint` (out of order) → the lip balm. `zzzz` → "Nothing for zzzz" with **Did you mean** chips (hashtags, collections). Tap a chip → results or a collection.
2. **Near me:** on the emulator, set a location (⋯ → Location → e.g. Detroit) → Market → **Near me**. *Pass:* the first time, Android asks for location permission; results narrow to sellers whose city is nearby (a seller must have saved a City in Edit profile, which the backend turns into a point). Deny the permission → the toggle falls back to your own profile city; with no city either it stays off and a message says what to add.

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
