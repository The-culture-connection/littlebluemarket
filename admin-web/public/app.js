// The admin console, in the browser. Signs in with the same Firebase project
// as the app, checks the admin claim on the token, and calls the same
// adminSendAnnouncement function the app's Admin screen calls. Nothing is
// sent from this server; there is no server logic at all.
import { initializeApp } from 'https://www.gstatic.com/firebasejs/10.14.1/firebase-app.js';
import {
  getAuth, onAuthStateChanged, signInWithEmailAndPassword, signOut,
} from 'https://www.gstatic.com/firebasejs/10.14.1/firebase-auth.js';
import { getFunctions, httpsCallable } from 'https://www.gstatic.com/firebasejs/10.14.1/firebase-functions.js';
import {
  getFirestore, collection, query, orderBy, limit, onSnapshot, doc, updateDoc, serverTimestamp,
} from 'https://www.gstatic.com/firebasejs/10.14.1/firebase-firestore.js';
import {
  getStorage, ref as storageRef, uploadBytes, getDownloadURL,
} from 'https://www.gstatic.com/firebasejs/10.14.1/firebase-storage.js';

const config = window.LBM_FIREBASE_CONFIG;
if (!config || !config.apiKey) {
  document.body.innerHTML = '<main><section class="card"><h2>Not configured</h2><p class="hint">public/firebase-config.js is missing its values. See admin-web/README.md.</p></section></main>';
  throw new Error('firebase-config.js missing');
}
const app = initializeApp(config);
const auth = getAuth(app);
const functions = getFunctions(app, config.functionsRegion || 'us-central1');
const db = getFirestore(app);
const storage = getStorage(app);

const $ = (id) => document.getElementById(id);

// Which project this console is talking to, in the header. Staging and
// production look identical otherwise, and an announcement sent from the
// wrong one reaches real phones.
{
  const tag = document.getElementById('envTag');
  const live = config.projectId === 'little-blue-cart-prod';
  tag.textContent = live ? 'LIVE · little-blue-cart-prod' : `STAGING · `;
  tag.className = live ? 'envtag live' : 'envtag';
  tag.hidden = false;
  document.title = live ? 'Little Blue Market · Admin' : 'STAGING · LBM Admin';
}
const show = (id, on) => { $(id).hidden = !on; };
const notice = (id, text, ok) => { const el = $(id); el.textContent = text; el.className = `notice ${ok ? 'ok' : 'bad'}`; el.hidden = !text; };

let unsubscribeRecent = null;
let unsubscribeFeedback = null;
let feedbackDocs = [];

function renderFeedback() {
  const list = $('feedback');
  const showDone = $('showDone').checked;
  const shown = feedbackDocs.filter((d) => showDone || (d.data().status || 'open') !== 'done');
  list.innerHTML = '';
  if (shown.length === 0) {
    const open = feedbackDocs.filter((d) => (d.data().status || 'open') !== 'done').length;
    list.innerHTML = `<li class="meta">${feedbackDocs.length === 0 ? 'Nothing sent yet.' : `Nothing open. ${feedbackDocs.length - open} done.`}</li>`;
    return;
  }
  for (const d of shown) {
    const f = d.data();
    const when = f.createdAt?.toDate ? f.createdAt.toDate().toLocaleString() : '';
    const who = f.isGuest ? 'a guest' : (f.fromName || f.uid || '');
    const isDone = (f.status || 'open') === 'done';
    const li = document.createElement('li');
    li.className = 'fb';
    if (f.screenshotUrl && /^https?:/.test(f.screenshotUrl)) {
      const a = document.createElement('a');
      a.href = f.screenshotUrl; a.target = '_blank'; a.rel = 'noopener';
      const img = document.createElement('img');
      img.src = f.screenshotUrl; img.alt = 'Screenshot';
      a.appendChild(img);
      li.appendChild(a);
    }
    const body = document.createElement('div');
    body.className = 'body';
    const tag = document.createElement('span');
    tag.className = `tag ${f.kind === 'bug' ? 'bug' : ''}`;
    tag.textContent = f.kind === 'bug' ? 'Bug' : 'Critique';
    const meta = document.createElement('span'); meta.className = 'meta'; meta.textContent = `${who} · ${when}`;
    const text = document.createElement('div'); text.className = 'text'; text.textContent = f.text || '';
    const where = document.createElement('div'); where.className = 'meta'; where.textContent = `${f.route || ''} · ${f.platform || ''}${isDone ? ' · done' : ''}`;
    const btn = document.createElement('button');
    btn.className = 'quiet tiny';
    btn.textContent = isDone ? 'Reopen' : 'Mark done';
    btn.addEventListener('click', async () => {
      btn.disabled = true;
      try {
        await updateDoc(doc(db, 'feedback', d.id), { status: isDone ? 'open' : 'done', statusAt: serverTimestamp() });
      } catch (error) {
        window.alert(describe(error));
        btn.disabled = false;
      }
    });
    body.append(tag, meta, text, where, btn);
    li.appendChild(body);
    list.appendChild(li);
  }
}

let unsubscribeReports = null;
let reportDocs = [];

const REASONS = { spam: 'Spam or scam', harassment: 'Harassment or hate', inappropriate: 'Inappropriate content', fake: 'Fake shop or counterfeit', other: 'Something else' };

function renderReports() {
  const list = $('reports');
  const showClosed = $('showClosedReports').checked;
  const shown = reportDocs.filter((d) => showClosed || (d.data().status || 'open') === 'open');
  list.innerHTML = '';
  if (shown.length === 0) {
    const open = reportDocs.filter((d) => (d.data().status || 'open') === 'open').length;
    list.innerHTML = `<li class="meta">${reportDocs.length === 0 ? 'Nothing reported yet.' : `Nothing open. ${reportDocs.length - open} closed.`}</li>`;
    return;
  }
  for (const d of shown) {
    const r = d.data();
    const when = r.createdAt?.toDate ? r.createdAt.toDate().toLocaleString() : '';
    const status = r.status || 'open';
    const subject = r.subjectName ? `${r.subjectName} (${r.subjectHandle || ''})` : (r.subjectHandle || r.subjectUid);
    const li = document.createElement('li');
    const head = document.createElement('div');
    const tag = document.createElement('span'); tag.className = `tag ${r.reason === 'spam' || r.reason === 'harassment' || r.reason === 'fake' ? 'bug' : ''}`; tag.textContent = REASONS[r.reason] || r.reason || '';
    const st = document.createElement('span'); st.className = 'tag'; st.textContent = status === 'open' ? 'open' : status + (r.subjectBanned && status !== 'banned' ? ' · banned' : '');
    const who = document.createElement('strong'); who.textContent = `${r.kind === 'post' ? 'A post by ' : ''}${subject}`;
    head.append(tag, st, who);
    const meta = document.createElement('div'); meta.className = 'meta'; meta.textContent = `reported by ${r.reporterName || r.reporterUid || ''} · ${when}`;
    const text = document.createElement('div'); text.className = 'text'; text.textContent = r.text || '';
    const actions = document.createElement('div');
    const mk = (label, cls, fn) => { const b = document.createElement('button'); b.className = `${cls} tiny`; b.textContent = label; b.style.marginRight = '6px'; b.addEventListener('click', async () => { b.disabled = true; try { await fn(); } catch (e) { window.alert(describe(e)); b.disabled = false; } }); return b; };
    if (status === 'open') actions.appendChild(mk('Resolve', 'quiet', () => updateDoc(doc(db, 'reports', d.id), { status: 'resolved', resolvedAt: serverTimestamp(), resolvedBy: auth.currentUser?.uid ?? null })));
    if (!r.subjectBanned) {
      actions.appendChild(mk(`Ban ${r.subjectHandle || 'this member'}`, 'primary', async () => {
        if (!window.confirm(`Ban ${subject}?\n\nTheir sign-in is disabled, their posts are removed, and every open report about them is closed.`)) return;
        await httpsCallable(functions, 'adminBanUser')({ uid: r.subjectUid, reportId: d.id, reason: REASONS[r.reason] || r.reason || '' });
      }));
    } else {
      actions.appendChild(mk('Unban', 'quiet', async () => { await httpsCallable(functions, 'adminUnbanUser')({ uid: r.subjectUid }); }));
    }
    li.append(head, meta, text, actions);
    list.appendChild(li);
  }
}

function watchReports() {
  unsubscribeReports?.();
  const q = query(collection(db, 'reports'), orderBy('createdAt', 'desc'), limit(200));
  unsubscribeReports = onSnapshot(q, (snap) => { reportDocs = snap.docs; renderReports(); },
    (error) => { $('reports').innerHTML = `<li class="meta">${describe(error)}</li>`; });
}

function watchFeedback() {
  unsubscribeFeedback?.();
  const q = query(collection(db, 'feedback'), orderBy('createdAt', 'desc'), limit(200));
  unsubscribeFeedback = onSnapshot(q, (snap) => { feedbackDocs = snap.docs; renderFeedback(); },
    (error) => { $('feedback').innerHTML = `<li class="meta">${describe(error)}</li>`; });
}

function describe(error) {
  const code = error?.code || '';
  const message = error?.message || String(error);
  if (code.includes('permission-denied')) return 'Admins only: this account has no admin claim.';
  if (code.includes('deadline-exceeded')) return 'That took longer than the call allows. Press the button again: the pull carries on from where it stopped.';
  if (code.includes('invalid-argument')) return message.replace(/^.*?: /, '');
  if (code.includes('wrong-password') || code.includes('invalid-credential')) return 'Wrong email or password.';
  if (code.includes('user-not-found')) return 'No account with that email.';
  if (code.includes('unauthorized-domain')) return 'This website address is not on the Firebase Authentication authorized-domains list yet (README, step 3).';
  return message;
}

function watchRecent() {
  unsubscribeRecent?.();
  const q = query(collection(db, 'announcements'), orderBy('createdAt', 'desc'), limit(20));
  unsubscribeRecent = onSnapshot(q, (snap) => {
    const list = $('recent');
    list.innerHTML = '';
    if (snap.empty) { list.innerHTML = '<li class="meta">Nothing sent yet.</li>'; return; }
    for (const doc of snap.docs) {
      const a = doc.data();
      const when = a.createdAt?.toDate ? a.createdAt.toDate().toLocaleString() : '';
      const li = document.createElement('li');
      li.innerHTML = `<div><strong></strong></div><div></div><div class="meta"></div>`;
      li.querySelector('strong').textContent = a.title || '';
      li.children[1].textContent = a.body || '';
      li.querySelector('.meta').textContent = `${a.audience || 'all'} · ${when}${a.messageId ? ' · sent' : ' · not sent'}`;
      list.appendChild(li);
    }
  }, (error) => { $('recent').innerHTML = `<li class="meta">${describe(error)}</li>`; });
}

async function refreshGate(user) {
  if (!user) {
    show('signin', true); show('notadmin', false); show('send', false); show('recentCard', false); show('feedbackCard', false); show('reportsCard', false); show('signout', false);
    show('promoCard', false); show('promoListCard', false); show('dirCard', false); show('vendorCard', false);
    $('who').textContent = '';
    unsubscribeRecent?.(); unsubscribeRecent = null;
    unsubscribeFeedback?.(); unsubscribeFeedback = null;
    unsubscribeReports?.(); unsubscribeReports = null;
    unsubscribePromos?.(); unsubscribePromos = null;
    return;
  }
  const token = await user.getIdTokenResult(true);
  const isAdmin = token.claims.admin === true;
  $('who').textContent = user.email || '';
  show('signout', true);
  show('signin', false);
  show('notadmin', !isAdmin);
  show('send', isAdmin);
  show('recentCard', isAdmin);
  show('feedbackCard', isAdmin);
  show('reportsCard', isAdmin);
  show('promoCard', isAdmin);
  show('promoListCard', isAdmin);
  show('dirCard', isAdmin);
  show('vendorCard', isAdmin);
  if (isAdmin) { watchRecent(); watchFeedback(); watchReports(); watchPromos(); }
}
$('showDone').addEventListener('change', renderFeedback);
$('showClosedReports').addEventListener('change', renderReports);

onAuthStateChanged(auth, (user) => { refreshGate(user).catch((e) => notice('signinNotice', describe(e), false)); });

$('signinBtn').addEventListener('click', async () => {
  notice('signinNotice', '', true);
  $('signinBtn').disabled = true;
  try {
    await signInWithEmailAndPassword(auth, $('email').value.trim(), $('password').value);
  } catch (error) {
    notice('signinNotice', describe(error), false);
  } finally {
    $('signinBtn').disabled = false;
  }
});
$('password').addEventListener('keydown', (e) => { if (e.key === 'Enter') $('signinBtn').click(); });
$('signout').addEventListener('click', () => signOut(auth));

function revalidate() {
  const title = $('title').value.trim();
  const body = $('body').value.trim();
  $('titleLeft').textContent = String(60 - title.length);
  $('bodyLeft').textContent = String(180 - body.length);
  $('sendBtn').disabled = !(title && body && title.length <= 60 && body.length <= 180);
  // An announcement has no picture preview, so this line is the only place
  // it says what will be tappable before it goes out to every phone.
  renderNamedPreview($('namedPreview'), title, body);
}
$('title').addEventListener('input', revalidate);
$('body').addEventListener('input', revalidate);

$('sendBtn').addEventListener('click', async () => {
  const title = $('title').value.trim();
  const body = $('body').value.trim();
  const audience = $('audience').value;
  const route = $('route').value;
  const who = $('audience').selectedOptions[0].textContent.toLowerCase();
  if (!window.confirm(`Send to ${who}?\n\n${title}\n${body}`)) return;
  $('sendBtn').disabled = true;
  notice('sendNotice', 'Sending…', true);
  try {
    const send = httpsCallable(functions, 'adminSendAnnouncement');
    await send({ title, body, audience, route });
    notice('sendNotice', `Sent to ${who}.`, true);
    $('title').value = ''; $('body').value = '';
    revalidate();
  } catch (error) {
    notice('sendNotice', describe(error), false);
    revalidate();
  }
});
revalidate();

// --------------------------------------------- Stage 17: adverts and popups
//
// One form for both, because Grace asked for adverts and then asked for
// announcements "exactly like" them. An advert writes a promo document and
// nothing else. An announcement goes through adminSendAnnouncement, which
// still pushes and still writes the bell row, and now carries the photo and
// the button through to the same popup.
//
// Photos are uploaded straight to Storage under promos/ from here, which the
// Storage rules allow for an admin-claim token only. The callable is given
// the resulting https URLs and checks them again.

const PROMO_TITLE_MAX = 60;
const PROMO_CAPTION_MAX = 180;
const PROMO_PHOTOS_MAX = 4;

/** Uploaded photos, in the order they will appear. */
let promoPhotos = [];
let promoUploading = 0;
let unsubscribePromos = null;

function renderPromoThumbs() {
  const list = $('pThumbs');
  list.innerHTML = '';
  for (const [i, photo] of promoPhotos.entries()) {
    const li = document.createElement('li');
    const img = document.createElement('img');
    img.src = photo.url;
    img.alt = `Photo ${i + 1}`;
    if (photo.pending) img.className = 'pending';
    const rm = document.createElement('button');
    rm.className = 'rm';
    rm.type = 'button';
    rm.title = 'Remove this photo';
    rm.textContent = '×';
    rm.addEventListener('click', () => {
      promoPhotos.splice(i, 1);
      renderPromoThumbs();
      renderPromoPreview();
    });
    li.append(img, rm);
    list.appendChild(li);
  }
}

// ---------------------------------------------------------------- @ and #
//
// The phone picks out @handles and #hashtags in an announcement or an
// advert and makes them tappable (Grace, 2026-09-24). These two patterns
// are a copy of the ones in functions/src/mentions.ts and, in Dart, in
// lib/models/notification.dart. Three copies is two too many, but the
// alternative is a build step on a static page, and a preview that
// disagreed with the phone would be worse than no preview.
//
// A hoisted function, not a `const`. This page has no build step and no
// module graph: it is one long script, and things at the top level run in
// the order they are written. `revalidate()` is called while the form is
// being set up, long before this line, and a `const` is not initialised
// until its own line runs. So reading it from up there threw
// "Cannot access 'NAMED_PATTERN' before initialization", which aborted the
// whole script and silently unhooked every listener declared after it:
// the advert tools, the directory tools, reports, feedback. A function
// declaration is hoisted whole, so the order stops mattering (Grace found
// it, 2026-09-24).
//
// A fresh regex each call, too, so nothing shares `lastIndex`.
function namedPattern() {
  return /#\w+|(?<![\w.])@[A-Za-z0-9_.]+/g;
}

function escapeHtml(text) {
  return text.replace(/[&<>"']/g, (ch) => (
    { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[ch]
  ));
}

/** The copy as the phone will draw it: tokens picked out, everything else plain. */
function namedHtml(text) {
  let out = '';
  let cursor = 0;
  for (const match of text.matchAll(namedPattern())) {
    out += escapeHtml(text.slice(cursor, match.index));
    out += `<span class="named">${escapeHtml(match[0])}</span>`;
    cursor = match.index + match[0].length;
  }
  return out + escapeHtml(text.slice(cursor));
}

/** The distinct tokens in some copy, in order, for the "will be tappable" line. */
function namedTokens(...texts) {
  const seen = new Set();
  const out = [];
  for (const match of texts.join('\n').matchAll(namedPattern())) {
    const key = match[0].toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    out.push(match[0]);
  }
  return out;
}

/** Lists what a piece of copy will make tappable, or hides itself. */
function renderNamedPreview(el, ...texts) {
  const tokens = namedTokens(...texts);
  el.hidden = tokens.length === 0;
  if (tokens.length === 0) { el.innerHTML = ''; return; }
  el.innerHTML =
    'Tappable on the phone: ' +
    tokens.map((t) => `<span class="named">${escapeHtml(t)}</span>`).join('');
}

function renderPromoPreview() {
  const kind = $('pKind').value;
  const title = $('pTitle').value.trim();
  const caption = $('pCaption').value.trim();
  const ctaLabel = $('pCtaLabel').value.trim();
  const photo = promoPhotos.find((p) => !p.pending);

  $('pPreviewFrom').textContent = kind === 'announcement' ? 'FROM LITTLE BLUE MARKET' : 'SPONSORED';
  // innerHTML, not textContent, so @handles and #hashtags show in the
  // preview the way the phone will draw them. Everything that is not a
  // token goes through escapeHtml first.
  const titleEl = $('pPreviewTitle');
  if (title) { titleEl.innerHTML = namedHtml(title); } else { titleEl.textContent = 'Your title here'; }
  titleEl.className = title ? 'promo-title' : 'promo-title promo-empty';
  const captionEl = $('pPreviewCaption');
  if (caption) { captionEl.innerHTML = namedHtml(caption); } else { captionEl.textContent = 'Your caption here.'; }
  captionEl.className = caption ? 'promo-caption' : 'promo-caption promo-empty';
  const cta = $('pPreviewCta');
  cta.textContent = ctaLabel;
  cta.hidden = !ctaLabel;
  const img = $('pPreviewImg');
  if (photo) { img.src = photo.url; img.hidden = false; } else { img.removeAttribute('src'); img.hidden = true; }
  // The dots the phone draws when there is more than one photo: people
  // swipe there, so the preview should say so rather than imply the first
  // picture is all anyone sees.
  const ready = promoPhotos.filter((entry) => !entry.pending);
  const dots = $('pPreviewDots');
  dots.innerHTML = '';
  dots.hidden = ready.length < 2;
  for (let i = 0; i < ready.length; i++) {
    const dot = document.createElement('i');
    if (i === 0) dot.className = 'on';
    dots.appendChild(dot);
  }

  $('pTitleLeft').textContent = String(PROMO_TITLE_MAX - title.length);
  $('pCaptionLeft').textContent = String(PROMO_CAPTION_MAX - caption.length);

  const ctaUrl = $('pCtaUrl').value.trim();
  const buttonHalfDone = Boolean(ctaLabel) !== Boolean(ctaUrl);
  $('pPostBtn').disabled = !(title && caption) || buttonHalfDone || promoUploading > 0;
  $('pPostBtn').textContent = promoUploading > 0 ? 'Waiting for the photo…' : 'Post it';
}

/** A `datetime-local` value is local time with no zone; send it as one. */
function promoWhen(id) {
  const raw = $(id).value;
  if (!raw) return undefined;
  const ms = Date.parse(raw);
  return Number.isFinite(ms) ? new Date(ms).toISOString() : undefined;
}

// What shape a picture has to be, and what to say when it is not.
//
// The popup hands the picture the whole top of the card, so a portrait
// fills it and a landscape leaves bands of white above and below. 4:5 is
// the target (1080 x 1350, what Instagram calls portrait); 3:4 to 1:1 is
// close enough to look deliberate. Refused rather than warned about,
// because Grace asked for an error and because a wrong-shaped advert is
// not obvious until it is live on everybody's phone.
const PHOTO_BEST = { w: 1080, h: 1350 };
const PHOTO_MIN_RATIO = 0.75; // 3:4, taller
const PHOTO_MAX_RATIO = 1.0; //  1:1, square
const PHOTO_MIN_SIDE = 600;

/** The pixel size of a chosen file, without uploading it. */
function readPhotoSize(file) {
  return new Promise((resolve, reject) => {
    const url = URL.createObjectURL(file);
    const img = new Image();
    img.onload = () => {
      URL.revokeObjectURL(url);
      resolve({ width: img.naturalWidth, height: img.naturalHeight });
    };
    img.onerror = () => {
      URL.revokeObjectURL(url);
      reject(new Error(`${file.name} is not an image this browser can read.`));
    };
    img.src = url;
  });
}

/** Null when the picture is fine, otherwise what is wrong with it. */
function photoComplaint(file, size) {
  const { width, height } = size;
  if (!width || !height) return `${file.name} has no size this browser can read.`;
  const shape = `${width} x ${height}`;
  if (Math.min(width, height) < PHOTO_MIN_SIDE) {
    return `${file.name} is ${shape}, which is too small: the shortest side needs ${PHOTO_MIN_SIDE} pixels or it looks soft on a phone. Best is ${PHOTO_BEST.w} x ${PHOTO_BEST.h}.`;
  }
  const ratio = width / height;
  if (ratio < PHOTO_MIN_RATIO) {
    return `${file.name} is ${shape}, which is taller and thinner than the popup can show without cutting the sides off. Best is ${PHOTO_BEST.w} x ${PHOTO_BEST.h} (4:5).`;
  }
  if (ratio > PHOTO_MAX_RATIO) {
    return `${file.name} is ${shape}, which is a landscape picture. The popup stands the picture up, so this would sit in a band with white above and below it. Crop it to ${PHOTO_BEST.w} x ${PHOTO_BEST.h} (4:5, standing up) or at least to a square.`;
  }
  return null;
}

$('pPhoto').addEventListener('change', async (event) => {
  const files = [...(event.target.files ?? [])];
  $('pPhoto').value = '';
  if (files.length === 0) return;
  const room = PROMO_PHOTOS_MAX - promoPhotos.length;
  if (room <= 0) {
    notice('pNotice', `At most ${PROMO_PHOTOS_MAX} photos.`, false);
    return;
  }
  notice('pNotice', '', true);
  for (const file of files.slice(0, room)) {
    // The shape, before anything is uploaded: a refusal should cost
    // nothing and should name the file and the size it actually is.
    try {
      const complaint = photoComplaint(file, await readPhotoSize(file));
      if (complaint) {
        notice('pNotice', complaint, false);
        continue;
      }
    } catch (error) {
      notice('pNotice', error.message, false);
      continue;
    }
    // Shown straight away from the local file, then swapped for the real URL
    // when the upload lands, so a slow connection still feels like something
    // happened on the click.
    const entry = { url: URL.createObjectURL(file), pending: true };
    promoPhotos.push(entry);
    promoUploading++;
    renderPromoThumbs();
    renderPromoPreview();
    try {
      const safe = file.name.replace(/[^a-zA-Z0-9._-]/g, '_').slice(-60);
      const path = `promos/${Date.now()}-${Math.random().toString(36).slice(2, 8)}-${safe}`;
      const fileRef = storageRef(storage, path);
      await uploadBytes(fileRef, file, { contentType: file.type });
      entry.url = await getDownloadURL(fileRef);
      entry.pending = false;
    } catch (error) {
      promoPhotos = promoPhotos.filter((p) => p !== entry);
      notice('pNotice', describe(error), false);
    } finally {
      promoUploading--;
      renderPromoThumbs();
      renderPromoPreview();
    }
  }
});

for (const id of ['pKind', 'pTitle', 'pCaption', 'pCtaLabel', 'pCtaUrl']) {
  $(id).addEventListener('input', renderPromoPreview);
  $(id).addEventListener('change', renderPromoPreview);
}

$('pPostBtn').addEventListener('click', async () => {
  const kind = $('pKind').value;
  const title = $('pTitle').value.trim();
  const caption = $('pCaption').value.trim();
  const audience = $('pAudience').value;
  const who = $('pAudience').selectedOptions[0].textContent.toLowerCase();
  const ctaLabel = $('pCtaLabel').value.trim();
  const ctaUrl = $('pCtaUrl').value.trim();
  const imageUrls = promoPhotos.filter((p) => !p.pending).map((p) => p.url);
  const what = kind === 'announcement'
    ? `Announce to ${who}?\n\nThis pushes to their phones, shows under their bell, and fades in as a popup.`
    : `Post this advert to ${who}?\n\nIt fades in as a popup. No push, no bell.`;
  if (!window.confirm(`${what}\n\n${title}\n${caption}`)) return;

  $('pPostBtn').disabled = true;
  notice('pNotice', 'Posting…', true);
  try {
    if (kind === 'announcement') {
      // The announcement path: push, bell, and the popup in one call.
      await httpsCallable(functions, 'adminSendAnnouncement')({
        title, body: caption, audience, route: '/you/notifications', imageUrls, ctaLabel, ctaUrl,
      });
    } else {
      await httpsCallable(functions, 'adminPromoSave')({
        kind, title, caption, audience, imageUrls, ctaLabel, ctaUrl,
        startsAt: promoWhen('pStarts'), endsAt: promoWhen('pEnds'),
      });
    }
    notice('pNotice', kind === 'announcement' ? `Announced to ${who}.` : `Advert is live for ${who}.`, true);
    $('pTitle').value = ''; $('pCaption').value = '';
    $('pCtaLabel').value = ''; $('pCtaUrl').value = '';
    $('pStarts').value = ''; $('pEnds').value = '';
    promoPhotos = [];
    renderPromoThumbs();
  } catch (error) {
    notice('pNotice', describe(error), false);
  } finally {
    renderPromoPreview();
  }
});

function watchPromos() {
  unsubscribePromos?.();
  const q = query(collection(db, 'promos'), orderBy('createdAt', 'desc'), limit(50));
  unsubscribePromos = onSnapshot(q, (snap) => {
    const list = $('promos');
    list.innerHTML = '';
    if (snap.empty) { list.innerHTML = '<li class="meta">Nothing posted yet.</li>'; return; }
    for (const d of snap.docs) {
      const p = d.data();
      const when = p.createdAt?.toDate ? p.createdAt.toDate().toLocaleString() : '';
      const active = p.active !== false;
      const li = document.createElement('li');
      li.className = 'fb';
      if (Array.isArray(p.imageUrls) && p.imageUrls[0]) {
        const img = document.createElement('img');
        img.src = p.imageUrls[0];
        img.alt = '';
        img.style.height = '54px';
        img.style.width = '72px';
        li.appendChild(img);
      }
      const body = document.createElement('div');
      body.className = 'body';
      const kindTag = document.createElement('span');
      kindTag.className = 'tag';
      kindTag.textContent = p.kind === 'announcement' ? 'Announcement' : 'Advert';
      const stateTag = document.createElement('span');
      stateTag.className = `tag ${active ? '' : 'bug'}`;
      stateTag.textContent = active ? 'live' : 'paused';
      const head = document.createElement('div');
      const strong = document.createElement('strong');
      strong.textContent = p.title || '';
      head.append(kindTag, stateTag, strong);
      const text = document.createElement('div');
      text.className = 'text';
      text.textContent = p.caption || '';
      const meta = document.createElement('div');
      meta.className = 'meta';
      const runs = [
        p.startsAt?.toDate ? `from ${p.startsAt.toDate().toLocaleDateString()}` : '',
        p.endsAt?.toDate ? `until ${p.endsAt.toDate().toLocaleDateString()}` : '',
      ].filter(Boolean).join(' ');
      meta.textContent = [
        p.audience || 'all',
        when,
        `${p.impressions ?? 0} seen`,
        `${p.clicks ?? 0} tapped`,
        p.ctaLabel ? `button: ${p.ctaLabel} -> ${p.ctaUrl || ''}` : 'no button',
        runs,
      ].filter(Boolean).join(' · ');

      const actions = document.createElement('div');
      const mk = (label, cls, fn) => {
        const b = document.createElement('button');
        b.className = `${cls} tiny`;
        b.textContent = label;
        b.style.marginRight = '6px';
        b.addEventListener('click', async () => {
          b.disabled = true;
          try { await fn(); } catch (e) { window.alert(describe(e)); b.disabled = false; }
        });
        return b;
      };
      actions.appendChild(mk(active ? 'Pause' : 'Resume', 'quiet', () =>
        httpsCallable(functions, 'adminPromoSetActive')({ id: d.id, active: !active })));
      actions.appendChild(mk('Delete', 'quiet', async () => {
        if (!window.confirm(`Delete "${p.title || 'this one'}" for good?\n\nPause takes it out of the app without deleting it.`)) return;
        await httpsCallable(functions, 'adminPromoDelete')({ id: d.id });
      }));

      body.append(head, text, meta, actions);
      li.appendChild(body);
      list.appendChild(li);
    }
  }, (error) => { $('promos').innerHTML = `<li class="meta">${describe(error)}</li>`; });
}

// Draw the preview and the counters once, before anything is typed.
renderPromoPreview();

// ------------------------------------------- Stage 17: pull the whole directory
//
// The pull is chunked: the function walks listings for a few minutes, then
// hands back a cursor. The first production run tried to do the lot in one
// call and was killed at the function's nine-minute ceiling, so this keeps
// calling until it reports done.
//
// Everything it does is written into a running log on the page. Grace pressed
// this and saw nothing but the red word "deadline-exceeded", with no way to
// tell whether anything had happened, which is no way to run a backfill.
// Copy for Claude copies the whole log, the way the app's bug button does.

/** Bumped by hand when this file changes, so a stale tab is obvious. */
const ADMIN_BUILD = '2026-09-14f';

const DIR_CALL_TIMEOUT_MS = 560_000;
const DIR_MAX_CALLS = 60;

const dirLogLines = [];

function dirLog(text, bad) {
  const stamp = new Date().toLocaleTimeString();
  dirLogLines.push(`[${stamp}] ${text}`);
  const el = $('dirLog');
  const line = document.createElement('div');
  if (bad) line.className = 'bad';
  line.textContent = `[${stamp}] ${text}`;
  el.appendChild(line);
  el.scrollTop = el.scrollHeight;
  $('dirCopy').hidden = false;
}

/** Everything about a failure, not just its code. */
function dirLogError(error) {
  const code = error?.code ? String(error.code) : '(no code)';
  const message = error?.message ? String(error.message) : String(error);
  dirLog(`FAILED  code=${code}`, true);
  dirLog(`        ${message}`, true);
  const details = error?.details;
  if (details !== undefined && details !== null) {
    try {
      dirLog(`        details=${JSON.stringify(details)}`, true);
    } catch {
      dirLog(`        details=${String(details)}`, true);
    }
  }
  if (code.includes('deadline-exceeded')) {
    dirLog('        This call ran out of time. Press the button again:', true);
    dirLog('        the pull carries on from where it stopped.', true);
  }
  if (code.includes('unauthenticated') || code.includes('permission-denied')) {
    dirLog('        Sign out and in again; the account needs the admin claim.', true);
  }
}

$('dirBuild').textContent = `page build ${ADMIN_BUILD}`;

$('dirCopy').addEventListener('click', async () => {
  const text = [
    `Little Blue Market admin console · directory pull`,
    `page build ${ADMIN_BUILD} · ${new Date().toISOString()}`,
    '',
    ...dirLogLines,
  ].join('\n');
  try {
    await navigator.clipboard.writeText(text);
    $('dirCopy').textContent = 'Copied';
    setTimeout(() => { $('dirCopy').textContent = 'Copy for Claude'; }, 2000);
  } catch {
    // A browser that refuses the clipboard still lets her select the text.
    window.prompt('Copy this and send it to Claude:', text);
  }
});

// ------------------------------------------------------ approving a vendor
//
// Almost no vendor reaches this card: someone who sells through Shipturtle
// confirms the email on their vendor account in the app and the shop
// connects itself. This is for the ones the automatic check refuses on
// purpose, because they need a judgement rather than a rule: two shop names,
// an email on two Shipturtle companies, a name somebody else holds.
//
// It replaced mailing out claim codes, which meant a developer running a
// script for every exception (Grace, 2026-09-24).

let vendorFacts = null;

function factRow(label, value, kind) {
  const tr = document.createElement('tr');
  const th = document.createElement('th');
  th.textContent = label;
  const td = document.createElement('td');
  if (kind) { td.className = kind; }
  td.textContent = value;
  tr.append(th, td);
  return tr;
}

function renderVendorFacts(s) {
  const body = $('venFactsBody');
  body.innerHTML = '';
  body.appendChild(factRow('App account', s.uid ? 'yes' : 'no, they have not signed up', s.uid ? 'yes' : 'no'));
  if (s.uid) {
    body.appendChild(factRow('Email confirmed', s.emailVerified ? 'yes' : 'not yet', s.emailVerified ? 'yes' : 'no'));
    body.appendChild(factRow('Already selling', s.isSeller ? `yes, as "${s.currentVendorName ?? 'unknown'}"` : 'no'));
  }
  body.appendChild(factRow(
    'On the Shipturtle list',
    s.companyIds.length === 0 ? 'no' : `yes (${s.companyIds.length} compan${s.companyIds.length === 1 ? 'y' : 'ies'})`,
    s.companyIds.length ? 'yes' : 'no',
  ));
  body.appendChild(factRow(
    'Shop names Shipturtle has',
    s.vendorNames.length ? s.vendorNames.join(', ') : 'none yet',
  ));
  const held = Object.entries(s.heldBy);
  if (held.length) {
    body.appendChild(factRow('Already claimed by somebody', held.map(([n, u]) => `${n} → ${u}`).join(', '), 'no'));
  }
  body.appendChild(factRow(
    'The automatic check',
    s.autoDecision === 'grant' ? 'would connect this shop on its own' : `will not, because ${s.autoReason}`,
  ));

  show('venFacts', true);
  const picker = $('venName');
  picker.innerHTML = '';
  for (const name of s.vendorNames) {
    const option = document.createElement('option');
    option.value = name;
    option.textContent = name;
    picker.appendChild(option);
  }
  // The approve half appears only when there is something to approve and
  // nothing in the way. `blocker` says which, in words.
  show('venApprove', s.canApprove && s.vendorNames.length > 0);
  if (s.blocker) notice('venNotice', s.blocker, false);
  else if (s.autoDecision === 'grant') {
    notice('venNotice', 'Nothing to do here: tell them to tap Connect my shop in the app, or wait for the two-hourly sweep.', true);
  } else {
    notice('venNotice', 'Pick the shop that is really theirs, then Approve.', true);
  }
}

$('venLookBtn').addEventListener('click', async () => {
  const email = $('venEmail').value.trim();
  if (!email) { notice('venNotice', 'Type their email first.', false); return; }
  $('venLookBtn').disabled = true;
  show('venFacts', false);
  notice('venNotice', 'Looking…', true);
  try {
    const call = httpsCallable(functions, 'adminVendorStatus', { timeout: 120_000 });
    const { data } = await call({ email });
    vendorFacts = data;
    renderVendorFacts(data);
  } catch (error) {
    vendorFacts = null;
    notice('venNotice', describe(error), false);
  } finally {
    $('venLookBtn').disabled = false;
  }
});

$('venApproveBtn').addEventListener('click', async () => {
  if (!vendorFacts) return;
  const vendorName = $('venName').value;
  const email = vendorFacts.email;
  if (!window.confirm(
    `Connect "${vendorName}" to ${email}?\n\n` +
    'Every product carrying that shop name moves to their profile, and the ' +
    'sales it has taken are credited to them.',
  )) return;
  $('venApproveBtn').disabled = true;
  notice('venNotice', 'Approving…', true);
  try {
    const call = httpsCallable(functions, 'adminApproveVendor', { timeout: 120_000 });
    const { data } = await call({ email, vendorName });
    notice('venNotice', `Done. ${email} now sells as "${data.vendorName}".`, true);
    show('venApprove', false);
  } catch (error) {
    notice('venNotice', describe(error), false);
  } finally {
    $('venApproveBtn').disabled = false;
  }
});

// Taking a directory back off an account that was wrongly given it. Two
// buttons on purpose: the first counts and writes nothing, so the number is
// seen before anything is deleted.
async function releaseDirectory(dryRun) {
  const uid = $('relUid').value.trim();
  if (!uid) {
    notice('relNotice', 'Paste the app account id first.', false);
    return;
  }
  if (!dryRun) {
    const ok = window.confirm(
      `Release every directory listing attributed to ${uid}?\n\n` +
      'The listings go back to unclaimed and the directory posts made for ' +
      'them are deleted. Their own posts are left alone. This cannot be ' +
      'undone, though the next directory pull re-mirrors the listings.',
    );
    if (!ok) return;
  }
  $('relCheckBtn').disabled = true;
  $('relRunBtn').disabled = true;
  notice('relNotice', dryRun ? 'Counting…' : 'Releasing…', true);
  try {
    const call = httpsCallable(functions, 'adminReleaseDirectory', { timeout: DIR_CALL_TIMEOUT_MS });
    const { data } = await call({ uid, dryRun });
    notice(
      'relNotice',
      dryRun
        ? `${data.listings} listings and ${data.posts} directory posts are attributed to that account. Nothing was changed.`
        : `Released ${data.listings} listings and deleted ${data.posts} directory posts.`,
      true,
    );
  } catch (error) {
    notice('relNotice', describe(error), false);
  } finally {
    $('relCheckBtn').disabled = false;
    $('relRunBtn').disabled = false;
  }
}
$('relCheckBtn').addEventListener('click', () => releaseDirectory(true));
$('relRunBtn').addEventListener('click', () => releaseDirectory(false));

$('dirSyncBtn').addEventListener('click', async () => {
  if (!window.confirm('Pull every published listing from littlebluecart.com now?\n\nThis can take several minutes the first time. Leave this page open; the log below shows what it is doing.')) return;
  $('dirSyncBtn').disabled = true;
  $('dirSyncBtn').textContent = 'Working…';
  notice('dirNotice', '', true);
  dirLog(`Starting. page build ${ADMIN_BUILD}`);
  dirLog(`Signed in as ${auth.currentUser?.email ?? '(nobody)'}`);
  dirLog('Calling adminSyncDirectory. The first call also crawls the list of');
  dirLog('every published listing, so it is the slowest one.');

  const pull = httpsCallable(functions, 'adminSyncDirectory', { timeout: DIR_CALL_TIMEOUT_MS });
  const startedAt = Date.now();
  try {
    let cursor = null;
    let result = null;
    for (let call = 1; call <= DIR_MAX_CALLS; call++) {
      const at = Date.now();
      dirLog(`Call ${call}${cursor ? ` (resuming at listing ${cursor})` : ''}…`);
      const answer = await pull(cursor ? { cursor } : {});
      result = answer.data ?? {};
      const secs = Math.round((Date.now() - at) / 1000);
      dirLog(
        `Call ${call} answered in ${secs}s: ${result.processedNow ?? 0} listings this call, ` +
        `${result.processed ?? 0} of ${result.total ?? 0} in total, done=${result.done === true}`,
      );
      if (result.done) break;
      cursor = result.nextCursor;
      notice('dirNotice', `Working: ${result.processed ?? 0} of ${result.total ?? 0} listings copied so far…`, true);
      if (!cursor) {
        dirLog('The function stopped without saying where to carry on from.', true);
        break;
      }
    }
    const total = Math.round((Date.now() - startedAt) / 1000);
    if (!result) {
      dirLog('No answer at all.', true);
      notice('dirNotice', 'The website did not answer. The log below has the detail.', false);
    } else if (!result.done) {
      dirLog(`Stopped after ${total}s with ${result.processed ?? 0} of ${result.total ?? 0} done.`, true);
      notice('dirNotice', `Stopped after ${result.processed ?? 0} of ${result.total ?? 0} listings. Press the button again to carry on.`, false);
    } else {
      const parts = [
        `${result.listings ?? 0} published listings`,
        `${result.categories ?? 0} categories`,
        `${result.claimed ?? 0} already claimed by an app account`,
      ];
      if (result.removed) parts.push(`${result.removed} no longer on the site, removed`);
      dirLog(`Finished in ${total}s. ${parts.join(', ')}.`);
      notice('dirNotice', `Done: ${parts.join(', ')}.`, true);
    }
  } catch (error) {
    dirLogError(error);
    notice('dirNotice', describe(error) + ' The log below has the full detail; Copy for Claude sends it to me.', false);
  } finally {
    $('dirSyncBtn').disabled = false;
    $('dirSyncBtn').textContent = 'Pull the directory now';
  }
});
