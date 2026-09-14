// The admin console is a static page; this is only the web server Railway
// runs it under. Everything that matters happens in the browser against
// Firebase: sign-in, the admin claim, the adminSendAnnouncement function.
import express from 'express';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
const app = express();
app.disable('x-powered-by');
app.use((req, res, next) => {
  res.setHeader('X-Frame-Options', 'DENY');
  res.setHeader('Referrer-Policy', 'no-referrer');
  next();
});
// Never cache the page or its script.
//
// Grace pressed a button that had just been fixed and still got the old
// error, because her tab had been open since before the deploy and was
// running the previous app.js from memory (2026-09-14). An admin console
// used by two people does not need caching; it needs to be right.
app.use((req, res, next) => {
  if (/[.](?:html|js)$/.test(req.path) || req.path === '/') {
    res.setHeader('Cache-Control', 'no-store, must-revalidate');
  }
  next();
});
app.use(express.static(join(here, 'public'), { extensions: ['html'] }));
app.get('/healthz', (req, res) => res.send('ok'));

const port = Number(process.env.PORT ?? 3000);
app.listen(port, () => console.log(`LBM admin console on :${port}`));
