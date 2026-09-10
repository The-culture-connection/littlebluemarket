// The web build of the app is static files; this is only the server Railway
// runs them under. Everything that matters happens in the browser against
// Firebase, exactly as it does on a phone.
import express from 'express';
import { existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
// `flutter build web` output, copied next to this file by Dockerfile.web.
const site = process.env.LBM_WEB_DIR ?? join(here, 'site');
if (!existsSync(join(site, 'index.html'))) {
  console.error(`No web build at ${site}. Run: flutter build web --release`);
  process.exit(1);
}

const app = express();
app.disable('x-powered-by');
app.use((req, res, next) => {
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('Referrer-Policy', 'strict-origin-when-cross-origin');
  // The shell and the service worker must never be cached: a stale
  // index.html would point at a main.dart.js that no longer exists.
  if (/\/(index\.html|flutter_service_worker\.js|flutter_bootstrap\.js|version\.json)?$/.test(req.path)) {
    res.setHeader('Cache-Control', 'no-cache');
  }
  next();
});
app.get('/healthz', (req, res) => res.send('ok'));
app.use(express.static(site, { maxAge: '1h', index: 'index.html' }));
// Every app route (/market, /you/...) is the same page; the app routes it.
app.get(/.*/, (req, res) => res.sendFile(join(site, 'index.html')));

const port = Number(process.env.PORT ?? 3000);
app.listen(port, () => console.log(`Little Blue Market web on :${port}`));
