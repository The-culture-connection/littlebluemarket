# hosting/: the pages the app's emails open

Static files, served by Firebase Hosting on the project's default site
(`https://little-blue-610e5.web.app` for dev, `https://little-blue-cart-prod.web.app`
for production). Deployed by `scripts\deploy-dev.ps1` / `deploy-prod.ps1` along
with everything else, or on its own with `npm run deploy:hosting` in `functions\`.

| Path | What it is |
| --- | --- |
| `/auth/action` | Where the confirmation email's button lands. Hands the code in the link back to Firebase and shows **You're confirmed** in the app's own style. Also handles password-reset and email-recovery links, so it can be set as the project's custom action URL (Firebase console → Authentication → Templates → *Customize action URL*) and Firebase's own emails land here too. |
| `/verified` | The same screen, static. Where Firebase's stock handler page continues to when the plain fallback mail was used. |
| `/email/cart.png` | The cart mark the email shows. |
| `/lbm.css` | The look: the welcome blue, the white card, the slate pill. Keep in step with `functions/src/verify_email.ts` (the email) and `lib/screens/onboarding/auth_screens.dart` (the app). |

The Firebase config on `/auth/action` comes from Hosting's reserved
`/__/firebase/init.js`, so the same file works on both projects with nothing to
edit. Both `*.web.app` domains are authorized for Auth by default; a custom
domain (`PUBLIC_WEB_URL`) has to be added under Authentication → Settings →
Authorized domains, and pointed at the site under Hosting → Add custom domain.
