# Little Blue Market admin console

A one-page website for sending an announcement (a push to every phone in the audience, and a line under their bell) to everyone, sellers, buyers or directory businesses, and for reading what people sent from the app's floating bug button (each note with a screenshot of the screen it came from; Mark done hides it, nothing is deleted). Announcements go through the same function the app's Admin screen calls (`adminSendAnnouncement`); the bug list reads `feedback/` directly, which the Firestore rules open to the admin claim only. Sign-in is the app's own Firebase account; the page only shows the form to an account that holds the admin claim, and the function refuses everyone else regardless.

## Adverts and popups (Stage 17)

The **Adverts and popups** card posts the card that fades in gently over the
app: a title, a caption, up to four photos, the wording on the button and
where the button goes. Two kinds:

- **Advert** is the popup and nothing else. No push, no bell.
- **Announcement** is the same popup **plus** the push and the bell line, so
  it goes through the same `adminSendAnnouncement` function the older card
  uses. The older **Send an announcement** card is still there for words-only
  news, and still has the "a tap opens" choice.

A person is shown at most one popup per app opening, and never the same one
twice. **Live now** lists everything posted with **seen** (how many phones it
faded in on) and **tapped** (how many tapped the button); **Pause** takes one
out of the app without deleting it.

Photos upload from this page straight into Storage under `promos/`, which the
Storage rules allow only for an account holding the admin claim. The page
waits for each upload before the Post button lights up, so a slow connection
cannot post an advert whose photo is not there yet. Links must be `https`:
the function refuses anything else, because the button opens whatever it says
in the phone's browser.

There is no server logic: `server.js` only serves the static page. All the values in `public/firebase-config.js` are public configuration (the same kind the app ships in `google-services.json`); the security is Firebase's sign-in plus the admin claim.

## Run it on your computer

```
cd little_blue_market/admin-web
npm install
npm start
```

Open http://localhost:3000. Firebase already allows `localhost`.

## Put it on Railway (once)

1. railway.app → **New Project** → **Deploy from GitHub repo** → pick `The-culture-connection/littlebluemarket`.
2. In the service's **Settings**: **Root Directory** = `little_blue_market/admin-web`. Build and start are detected (`npm install`, `npm start`). No environment variables are needed.
3. **Settings → Networking → Generate Domain**. Copy the address (`something.up.railway.app`).
4. Firebase console → **Authentication** → **Settings** → **Authorized domains** → **Add domain** → paste that address. Without this, sign-in on the site says the domain is not authorized.
5. Open the address, sign in with your admin account, send a test announcement to Everyone.

Every push to `main` redeploys it.

## Where the config comes from

`public/firebase-config.js` holds the web app registered in the Firebase project (`firebase apps:sdkconfig WEB <appId> --project dev`). To point the console at a different project later (production), register a web app there and replace the values.

## If it fails

- "This website address is not on the Firebase Authentication authorized-domains list" → step 4.
- "Admins only" after signing in → the account has no admin claim: in the app, Edit profile → Diagnostics → Claim admin, then sign out and in here.
- Sent, but no phone rings → the phones are not subscribed to the topic yet (they subscribe when the app signs in); the bell still shows it.
