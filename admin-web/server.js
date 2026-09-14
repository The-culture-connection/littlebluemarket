// The admin console is a static page; this is only the web server Railway
// runs it under. Everything that matters happens in the browser against
// Firebase: sign-in, the admin claim, the adminSendAnnouncement function.
import express from 'express';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));

// Which Firebase project this console talks to: 'prod' (the default) or
// 'dev' for the staging service. Refused rather than guessed, because a
// console that quietly pointed at production while Grace believed it was
// staging would send real people a test announcement.
const env = (process.env.LBM_ENV ?? 'prod').trim().toLowerCase();
if (env !== 'prod' && env !== 'dev') {
  console.error(`LBM_ENV must be 'prod' or 'dev', got '${env}'.`);
  process.exit(1);
}
const configFile = env === 'dev' ? 'firebase-config.dev.js' : 'firebase-config.js';

const app = express();
app.disable('x-powered-by');
app.use((req, res, next) => {
  res.setHeader('X-Frame-Options', 'DENY');
  res.setHeader('Referrer-Policy', 'no-referrer');
  next();
});

// Never cache the page, its script, or the configuration that decides which
// project it talks to.
//
// Grace pressed a button that had just been fixed and still got the old
// error, because her tab had been open since before the deploy and was
// running the previous app.js from memory (2026-09-14). An admin console
// used by two people does not need caching; it needs to be right. A cached
// firebase-config.js would be worse still: the wrong backend, invisibly.
app.use((req, res, next) => {
  if (/[.](?:html|js)$/.test(req.path) || req.path === '/') {
    res.setHeader('Cache-Control', 'no-store, must-revalidate');
  }
  next();
});

// The page always asks for /firebase-config.js; staging is handed the dev
// project's copy. Both files are public configuration and both are
// committed, so the same image serves either environment from a variable,
// with none of the old "copy the file over and remember to copy it back".
app.get('/firebase-config.js', (req, res) => {
  res.type('application/javascript');
  res.sendFile(join(here, 'public', configFile));
});

app.use(express.static(join(here, 'public'), { extensions: ['html'] }));
app.get('/healthz', (req, res) => res.send(`ok (${env})`));

const port = Number(process.env.PORT ?? 3000);
app.listen(port, () =>
  console.log(`LBM admin console on :${port} · ${env} (${configFile})`),
);
