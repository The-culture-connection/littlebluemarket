# Little Blue Market admin console

A one-page website for sending an announcement (a push to every phone in the audience, and a line under their bell) to everyone, sellers, buyers or directory businesses. It is the same function the app's Admin screen calls (`adminSendAnnouncement`), reached from a laptop instead of a phone. Sign-in is the app's own Firebase account; the page only shows the form to an account that holds the admin claim, and the function refuses everyone else regardless.

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
