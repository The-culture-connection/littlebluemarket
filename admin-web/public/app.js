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

const config = window.LBM_FIREBASE_CONFIG;
if (!config || !config.apiKey) {
  document.body.innerHTML = '<main><section class="card"><h2>Not configured</h2><p class="hint">public/firebase-config.js is missing its values. See admin-web/README.md.</p></section></main>';
  throw new Error('firebase-config.js missing');
}
const app = initializeApp(config);
const auth = getAuth(app);
const functions = getFunctions(app, config.functionsRegion || 'us-central1');
const db = getFirestore(app);

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
    show('signin', true); show('notadmin', false); show('send', false); show('recentCard', false); show('feedbackCard', false); show('signout', false);
    $('who').textContent = '';
    unsubscribeRecent?.(); unsubscribeRecent = null;
    unsubscribeFeedback?.(); unsubscribeFeedback = null;
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
  if (isAdmin) { watchRecent(); watchFeedback(); }
}
$('showDone').addEventListener('change', renderFeedback);

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
