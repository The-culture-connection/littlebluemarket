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
  // Nothing is cached without asking first. Flutter gives main.dart.js the
  // same name in every build, so a cached copy is simply the old app, which
  // is how a freshly deployed page kept showing the previous one. ETags make
  // the revalidation a 304 in the normal case, so this costs almost nothing.
  res.setHeader('Cache-Control', 'no-cache');
  next();
});
app.get('/healthz', (req, res) => res.send('ok'));

// Pictures from littlebluecart.com, served from this origin.
//
// The site sends its uploads with no Access-Control-Allow-Origin header
// (checked 2026-09-14), and Flutter's web renderers decode images through a
// canvas, which a browser refuses for a cross-origin image without that
// header. So every directory listing's photo was blank on the website while
// being perfectly fine on a phone, which does a plain GET and does not care.
//
// Fetching it here makes it same-origin, so no CORS question arises. This is
// deliberately NOT an open image proxy: only https, only the hosts below,
// only something that comes back as an image, and only up to a few MB. Keep
// the host list in step with `_hostsWithoutCors` in lib/widgets/remote_image.dart.
//
// The real fix, if the site ever gains one header, is to delete all of this:
// `Access-Control-Allow-Origin: *` on /wp-content/uploads would let the
// browser load the pictures directly.
const IMAGE_HOSTS = new Set(['littlebluecart.com', 'www.littlebluecart.com']);
const IMAGE_TIMEOUT_MS = 15_000;
const IMAGE_MAX_BYTES = 8 * 1024 * 1024;

app.get('/img', async (req, res) => {
  const raw = typeof req.query.u === 'string' ? req.query.u : '';
  let url;
  try {
    url = new URL(raw);
  } catch {
    res.status(400).type('text/plain').send('Not a web address.');
    return;
  }
  if (url.protocol !== 'https:' || !IMAGE_HOSTS.has(url.hostname)) {
    res.status(403).type('text/plain').send('That host is not served here.');
    return;
  }

  const stop = AbortSignal.timeout(IMAGE_TIMEOUT_MS);
  try {
    const answer = await fetch(url, {
      signal: stop,
      redirect: 'follow',
      headers: { Accept: 'image/*' },
    });
    if (!answer.ok) {
      res.status(answer.status === 404 ? 404 : 502).type('text/plain').send('The picture did not load.');
      return;
    }
    const type = answer.headers.get('content-type') ?? '';
    if (!type.startsWith('image/')) {
      // A login page or an error page dressed as a 200 is not a picture.
      res.status(415).type('text/plain').send('That is not an image.');
      return;
    }
    const declared = Number(answer.headers.get('content-length') ?? 0);
    if (declared > IMAGE_MAX_BYTES) {
      res.status(413).type('text/plain').send('That picture is too big.');
      return;
    }

    const bytes = Buffer.from(await answer.arrayBuffer());
    if (bytes.byteLength > IMAGE_MAX_BYTES) {
      res.status(413).type('text/plain').send('That picture is too big.');
      return;
    }
    // An upload URL names a specific file that never changes, so this is the
    // one thing here worth caching hard. Overrides the no-cache default set
    // for the app's own files above.
    res.setHeader('Cache-Control', 'public, max-age=86400, immutable');
    res.type(type).send(bytes);
  } catch (error) {
    const timedOut = error?.name === 'TimeoutError' || error?.name === 'AbortError';
    res
      .status(timedOut ? 504 : 502)
      .type('text/plain')
      .send(timedOut ? 'The picture took too long.' : 'The picture did not load.');
  }
});


// The page the app stores are given, served as plain HTML rather than by the
// app. Nothing on it is downloaded, so it renders whatever the browser has
// cached of the app, and whether or not the app loads at all. Inside the web
// app the same address is a screen, reached without asking the server, so
// both ways of arriving do the same thing.
app.get('/delete-account', (req, res) =>
  res.sendFile(join(here, 'delete-account.html')),
);

// A build that registers no service worker still ships one, and Flutter makes
// it a worker that removes itself: it unregisters and reloads the open tabs.
// That is what recovers anyone who visited a version which did register one,
// and it is served from the build like every other file.
app.use(express.static(site, { etag: true, lastModified: true, index: 'index.html' }));
// Every app route (/market, /you/...) is the same page; the app routes it.
app.get(/.*/, (req, res) => res.sendFile(join(site, 'index.html')));

const port = Number(process.env.PORT ?? 3000);
app.listen(port, () => console.log(`Little Blue Market web on :${port}`));
