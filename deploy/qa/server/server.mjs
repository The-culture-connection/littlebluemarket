// QA suite server for Railway (service: lbm-qa, staging environment). Ported
// from the Empower Health suite on 2026-10-22. No dependencies.
//
//   /                QA harness (static, from SITE_DIR)
//   /app/*           the app under test (SPA fallback to /app/index.html)
//   /api/*           shared checklist state: statuses, notes, bug reports
//   /shots/<file>    screenshots attached to bug reports and notes
//   /img?u=<url>     the app's picture pass-through, as on the web app
//   /healthz         ok
//
// Data lives in DATA_DIR (a Railway volume mounted at /data) as db.json plus
// image files. Set QA_PASSCODE to require a team passcode for /api, /shots and
// /review (the review screenshots contain real app data).

import { createServer } from 'node:http';
import { randomUUID } from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';

const PORT = Number(process.env.PORT || 8080);
const SITE_DIR = path.resolve(process.env.SITE_DIR || '/srv');
const DATA_DIR = path.resolve(process.env.DATA_DIR || '/data');
const SHOTS_DIR = path.join(DATA_DIR, 'shots');
const DB_FILE = path.join(DATA_DIR, 'db.json');
const PASSCODE = process.env.QA_PASSCODE || '';
const MAX_BODY = 15 * 1024 * 1024;

fs.mkdirSync(SHOTS_DIR, { recursive: true });

// ---------- storage ----------
let db = { results: {}, notes: {}, bugs: [] };
try {
  db = { ...db, ...JSON.parse(fs.readFileSync(DB_FILE, 'utf8')) };
} catch (e) {
  if (e.code !== 'ENOENT') console.error('Could not read db.json:', e.message);
}
function save() {
  const tmp = DB_FILE + '.tmp';
  fs.writeFileSync(tmp, JSON.stringify(db, null, 1));
  fs.renameSync(tmp, DB_FILE);
}
function saveShot(dataUrl) {
  if (typeof dataUrl !== 'string' || !dataUrl) return null;
  const m = /^data:image\/(png|jpeg);base64,(.+)$/s.exec(dataUrl);
  if (!m) throw httpError(400, 'Screenshot must be a PNG or JPEG data URL');
  const file = `${Date.now()}-${randomUUID().slice(0, 8)}.${m[1] === 'jpeg' ? 'jpg' : 'png'}`;
  fs.writeFileSync(path.join(SHOTS_DIR, file), Buffer.from(m[2], 'base64'));
  return `/shots/${file}`;
}

// ---------- helpers ----------
function httpError(status, message) {
  return Object.assign(new Error(message), { status });
}
const clean = (v, max = 4000) => (typeof v === 'string' ? v.trim().slice(0, max) : '');
const now = () => new Date().toISOString();

function readJson(req) {
  return new Promise((resolve, reject) => {
    let size = 0;
    const chunks = [];
    req.on('data', (c) => {
      size += c.length;
      if (size > MAX_BODY) {
        reject(httpError(413, 'Request too large'));
        req.destroy();
      } else chunks.push(c);
    });
    req.on('end', () => {
      try {
        resolve(chunks.length ? JSON.parse(Buffer.concat(chunks).toString('utf8')) : {});
      } catch {
        reject(httpError(400, 'Invalid JSON'));
      }
    });
    req.on('error', reject);
  });
}
function sendJson(res, status, body) {
  res.writeHead(status, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' });
  res.end(JSON.stringify(body));
}
function authorized(req) {
  if (!PASSCODE) return true;
  const cookie = req.headers.cookie || '';
  const m = /(?:^|;\s*)qa_pass=([^;]+)/.exec(cookie);
  return (m && decodeURIComponent(m[1]) === PASSCODE) || req.headers['x-qa-passcode'] === PASSCODE;
}

// ---------- API ----------
async function api(req, res, pathname) {
  if (pathname === '/api/state' && req.method === 'GET') {
    return sendJson(res, 200, { ...db, passcode: !!PASSCODE });
  }
  if (req.method !== 'POST' && req.method !== 'DELETE') throw httpError(405, 'Method not allowed');

  if (pathname === '/api/status') {
    const b = await readJson(req);
    const id = clean(b.id, 200);
    if (!id) throw httpError(400, 'id required');
    if (b.status && !['pass', 'fail', 'na'].includes(b.status)) throw httpError(400, 'bad status');
    if (b.status) db.results[id] = { status: b.status, by: clean(b.author, 80) || 'Tester', at: now() };
    else delete db.results[id];
    save();
    return sendJson(res, 200, { ok: true, result: db.results[id] || null });
  }

  if (pathname === '/api/notes') {
    const b = await readJson(req);
    const id = clean(b.id, 200);
    const text = clean(b.text);
    if (!id || (!text && !b.shot)) throw httpError(400, 'id and text or screenshot required');
    const note = { id: randomUUID(), text, author: clean(b.author, 80) || 'Tester', at: now(), shot: saveShot(b.shot) };
    (db.notes[id] ||= []).push(note);
    save();
    return sendJson(res, 200, { ok: true, note });
  }

  const noteDel = /^\/api\/notes\/([^/]+)\/([^/]+)$/.exec(pathname);
  if (noteDel && req.method === 'DELETE') {
    const [, itemId, noteId] = noteDel.map(decodeURIComponent);
    db.notes[itemId] = (db.notes[itemId] || []).filter((n) => n.id !== noteId);
    save();
    return sendJson(res, 200, { ok: true });
  }

  if (pathname === '/api/bugs' && req.method === 'POST') {
    const b = await readJson(req);
    const title = clean(b.title, 200);
    if (!title) throw httpError(400, 'title required');
    const bug = {
      id: 'bug-' + randomUUID().slice(0, 8),
      title,
      comment: clean(b.comment),
      pri: ['P0', 'P1', 'P2'].includes(b.pri) ? b.pri : 'P1',
      group: clean(b.group, 80) || 'Other screens',
      screens: Array.isArray(b.screens) ? b.screens.map((s) => clean(s, 80)).slice(0, 6) : [],
      nav: b.nav && typeof b.nav === 'object'
        ? { tab: Number.isInteger(b.nav.tab) ? b.nav.tab : undefined, route: clean(b.nav.route, 120) || undefined }
        : {},
      device: b.device && typeof b.device === 'object' ? b.device : {},
      issues: Array.isArray(b.issues) ? b.issues.slice(0, 30) : [],
      author: clean(b.author, 80) || 'Tester',
      at: now(),
      shot: saveShot(b.shot),
    };
    db.bugs.push(bug);
    save();
    return sendJson(res, 200, { ok: true, bug });
  }

  const bugDel = /^\/api\/bugs\/([^/]+)$/.exec(pathname);
  if (bugDel && req.method === 'DELETE') {
    const id = decodeURIComponent(bugDel[1]);
    db.bugs = db.bugs.filter((x) => x.id !== id);
    delete db.results[id];
    delete db.notes[id];
    save();
    return sendJson(res, 200, { ok: true });
  }

  throw httpError(404, 'Not found');
}

// ---------- pictures ----------
// The app asks for littlebluecart.com and Firebase Storage pictures through
// /img, because neither sends a CORS header and Flutter on the web cannot
// draw a cross-origin picture without one. Same rules as web-server/server.js:
// https only, these hosts and buckets only, images only, a few MB at most.
// Keep in step with that file and with lib/widgets/remote_image.dart.
const IMAGE_HOSTS = new Set(['littlebluecart.com', 'www.littlebluecart.com']);
const IMAGE_BUCKET_HOST = 'firebasestorage.googleapis.com';
const IMAGE_BUCKETS = ['little-blue-610e5.firebasestorage.app', 'little-blue-cart-prod.firebasestorage.app'];
const IMAGE_TIMEOUT_MS = 15_000;
const IMAGE_MAX_BYTES = 8 * 1024 * 1024;

function imageAllowed(url) {
  if (url.protocol !== 'https:') return false;
  if (IMAGE_HOSTS.has(url.hostname)) return true;
  return url.hostname === IMAGE_BUCKET_HOST &&
    IMAGE_BUCKETS.some((b) => url.pathname.startsWith('/v0/b/' + b + '/o/'));
}

async function serveImage(req, res) {
  let url;
  try {
    url = new URL(new URL(req.url, 'http://local').searchParams.get('u') || '');
  } catch {
    throw httpError(400, 'Not a web address.');
  }
  if (!imageAllowed(url)) throw httpError(403, 'That host is not served here.');
  let answer;
  try {
    answer = await fetch(url, { signal: AbortSignal.timeout(IMAGE_TIMEOUT_MS), redirect: 'follow', headers: { Accept: 'image/*' } });
  } catch (e) {
    const timedOut = e?.name === 'TimeoutError' || e?.name === 'AbortError';
    throw httpError(timedOut ? 504 : 502, timedOut ? 'The picture took too long.' : 'The picture did not load.');
  }
  if (!answer.ok) throw httpError(answer.status === 404 ? 404 : 502, 'The picture did not load.');
  const type = answer.headers.get('content-type') || '';
  if (!type.startsWith('image/')) throw httpError(415, 'That is not an image.');
  const bytes = Buffer.from(await answer.arrayBuffer());
  if (bytes.byteLength > IMAGE_MAX_BYTES) throw httpError(413, 'That picture is too big.');
  res.writeHead(200, { 'Content-Type': type, 'Cache-Control': 'public, max-age=86400, immutable' });
  res.end(bytes);
}

// ---------- static ----------
const TYPES = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.mjs': 'text/javascript; charset=utf-8',
  '.json': 'application/json', '.css': 'text/css', '.wasm': 'application/wasm', '.png': 'image/png',
  '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.svg': 'image/svg+xml', '.ico': 'image/x-icon',
  '.ttf': 'font/ttf', '.otf': 'font/otf', '.woff2': 'font/woff2', '.map': 'application/json', '.txt': 'text/plain',
};
const NO_CACHE = new Set(['/', '/index.html', '/build.json', '/app/', '/app/index.html', '/app/flutter_bootstrap.js', '/app/flutter_service_worker.js', '/app/version.json']);

function resolveInside(base, rel) {
  const full = path.resolve(base, '.' + rel);
  return full === base || full.startsWith(base + path.sep) ? full : null;
}
function serveFile(req, res, file, pathname) {
  const headers = { 'Content-Type': TYPES[path.extname(file).toLowerCase()] || 'application/octet-stream' };
  headers['Cache-Control'] = NO_CACHE.has(pathname) ? 'no-cache' : 'public, max-age=300';
  // Pre-compressed copies (created at build time) for the large debug bundle.
  if (/\bgzip\b/.test(req.headers['accept-encoding'] || '') && fs.existsSync(file + '.gz')) {
    headers['Content-Encoding'] = 'gzip';
    headers.Vary = 'Accept-Encoding';
    file += '.gz';
  }
  res.writeHead(200, headers);
  if (req.method === 'HEAD') return res.end();
  fs.createReadStream(file).pipe(res);
}
function serveStatic(req, res, pathname) {
  if (pathname === '/app') {
    res.writeHead(308, { Location: '/app/' });
    return res.end();
  }
  let file = resolveInside(SITE_DIR, pathname);
  if (file && fs.existsSync(file) && fs.statSync(file).isDirectory()) file = path.join(file, 'index.html');
  if (!file || !fs.existsSync(file)) {
    file = path.join(SITE_DIR, pathname.startsWith('/app/') ? 'app/index.html' : 'index.html');
  }
  serveFile(req, res, file, pathname);
}

// ---------- server ----------
createServer(async (req, res) => {
  const pathname = decodeURIComponent(new URL(req.url, 'http://local').pathname);
  try {
    if (pathname.startsWith('/api/') || pathname.startsWith('/shots/') || pathname.startsWith('/review/')) {
      if (!authorized(req)) return sendJson(res, 401, { error: 'passcode required' });
    }
    if (pathname === '/healthz') {
      res.writeHead(200, { 'Content-Type': 'text/plain' });
      return res.end('ok');
    }
    if (pathname === '/img') return await serveImage(req, res);
    if (pathname.startsWith('/api/')) return await api(req, res, pathname);
    if (pathname.startsWith('/shots/')) {
      const file = resolveInside(SHOTS_DIR, pathname.slice('/shots'.length));
      if (!file || !fs.existsSync(file)) throw httpError(404, 'Not found');
      res.writeHead(200, { 'Content-Type': TYPES[path.extname(file)] || 'image/png', 'Cache-Control': 'private, max-age=86400' });
      return fs.createReadStream(file).pipe(res);
    }
    if (req.method !== 'GET' && req.method !== 'HEAD') throw httpError(405, 'Method not allowed');
    serveStatic(req, res, pathname);
  } catch (e) {
    if (!e.status) console.error(e);
    if (!res.headersSent) sendJson(res, e.status || 500, { error: e.status ? e.message : 'Server error' });
  }
}).listen(PORT, () => {
  console.log(`QA suite on :${PORT} (site ${SITE_DIR}, data ${DATA_DIR}${PASSCODE ? ', passcode on' : ''})`);
});
