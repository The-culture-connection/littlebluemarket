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
    show('promoCard', false); show('promoListCard', false);
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

function renderPromoPreview() {
  const kind = $('pKind').value;
  const title = $('pTitle').value.trim();
  const caption = $('pCaption').value.trim();
  const ctaLabel = $('pCtaLabel').value.trim();
  const photo = promoPhotos.find((p) => !p.pending);

  $('pPreviewFrom').textContent = kind === 'announcement' ? 'FROM LITTLE BLUE MARKET' : 'SPONSORED';
  const titleEl = $('pPreviewTitle');
  titleEl.textContent = title || 'Your title here';
  titleEl.className = title ? 'promo-title' : 'promo-title promo-empty';
  const captionEl = $('pPreviewCaption');
  captionEl.textContent = caption || 'Your caption here.';
  captionEl.className = caption ? 'promo-caption' : 'promo-caption promo-empty';
  const cta = $('pPreviewCta');
  cta.textContent = ctaLabel;
  cta.hidden = !ctaLabel;
  const img = $('pPreviewImg');
  if (photo) { img.src = photo.url; img.hidden = false; } else { img.removeAttribute('src'); img.hidden = true; }

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
