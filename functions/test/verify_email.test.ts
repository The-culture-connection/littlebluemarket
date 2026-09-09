import { strict as assert } from 'node:assert';
import { test } from 'node:test';

import {
  RESEND_GAP_MS,
  VERIFY_SUBJECT,
  escapeHtml,
  mailSettings,
  publicWebUrl,
  rebrandActionLink,
  renderVerificationEmail,
  resendTooSoon,
  throttleDocPath,
} from '../src/verify_email.ts';

const LINK =
  'https://little-blue-610e5.firebaseapp.com/__/auth/action?mode=verifyEmail&oobCode=ABC123&apiKey=k&lang=en&continueUrl=https%3A%2F%2Flittle-blue-610e5.web.app%2Fverified';

// ----------------------------------------------------------------- settings

test('branded mail is off until a host and a real password exist', () => {
  assert.equal(mailSettings({}), null);
  assert.equal(mailSettings({ host: 'smtp.gmail.com' }), null);
  assert.equal(mailSettings({ host: 'smtp.gmail.com', pass: 'unset', user: 'a@b.c' }), null);
  assert.equal(mailSettings({ host: '', pass: 'secret', user: 'a@b.c' }), null);
  // No login and no From line: nowhere to send from.
  assert.equal(mailSettings({ host: 'smtp.gmail.com', pass: 'secret' }), null);
});

test('the login falls back to the From address, and the From line to the login', () => {
  const fromOnly = mailSettings({
    host: 'smtp.gmail.com',
    pass: 'secret',
    from: 'Little Blue Market <hello@littlebluecart.com>',
  });
  assert.deepEqual(fromOnly, {
    host: 'smtp.gmail.com',
    port: 465,
    user: 'hello@littlebluecart.com',
    pass: 'secret',
    from: 'Little Blue Market <hello@littlebluecart.com>',
  });

  const userOnly = mailSettings({ host: 'smtp.gmail.com', pass: 'secret', user: 'grace@x.com', port: '587' });
  assert.equal(userOnly?.port, 587);
  assert.equal(userOnly?.from, 'Little Blue Market <grace@x.com>');
});

test('a nonsense port becomes 465', () => {
  const s = mailSettings({ host: 'h', pass: 'p', user: 'u@x.com', port: 'lots' });
  assert.equal(s?.port, 465);
});

test('the public web url defaults to the project hosting site', () => {
  assert.equal(publicWebUrl('https://littlebluecart.shop/'), 'https://littlebluecart.shop');
  assert.match(publicWebUrl(''), /^https:\/\/.+\.web\.app$/);
});

// --------------------------------------------------------------------- link

test('a Firebase action link is pointed at our page, query intact', () => {
  const out = rebrandActionLink(LINK, 'https://little-blue-610e5.web.app/');
  assert.equal(
    out,
    'https://little-blue-610e5.web.app/auth/action?mode=verifyEmail&oobCode=ABC123&apiKey=k&lang=en&continueUrl=https%3A%2F%2Flittle-blue-610e5.web.app%2Fverified',
  );
});

test('a link that is not the stock handler is left alone', () => {
  const custom = 'https://littlebluecart.shop/confirm?oobCode=ABC';
  assert.equal(rebrandActionLink(custom, 'https://x.web.app'), custom);
});

// ----------------------------------------------------------------- throttle

test('the second send inside the gap is refused, the first never is', () => {
  const now = 1_000_000;
  assert.equal(resendTooSoon(undefined, now), false);
  assert.equal(resendTooSoon(now - RESEND_GAP_MS + 1, now), true);
  assert.equal(resendTooSoon(now - RESEND_GAP_MS, now), false);
});

test('the throttle document is under _internal, which clients cannot read', () => {
  assert.equal(throttleDocPath('u1'), '_internal/verificationMail/byUid/u1');
});

// ------------------------------------------------------------------ message

test('the message carries the link, the name, the address and the cart', () => {
  const mail = renderVerificationEmail({
    displayName: 'Grace',
    email: 'grace@example.com',
    link: 'https://x.web.app/auth/action?mode=verifyEmail&oobCode=ABC',
    logoUrl: 'https://x.web.app/email/cart.png',
  });
  assert.equal(mail.subject, VERIFY_SUBJECT);
  assert.ok(mail.html.includes('Hi Grace,'));
  assert.ok(mail.html.includes('grace@example.com'));
  assert.ok(mail.html.includes('src="https://x.web.app/email/cart.png"'));
  // & in an href is written &amp;, which browsers and mail clients read back as &.
  assert.ok(mail.html.includes('href="https://x.web.app/auth/action?mode=verifyEmail&amp;oobCode=ABC"'));
  assert.ok(!mail.html.includes('{{'), 'no placeholder survives');
  // The plain-text twin has the raw link.
  assert.ok(mail.text.includes('https://x.web.app/auth/action?mode=verifyEmail&oobCode=ABC'));
  // The brand colours are in the mail, not a stylesheet the client would drop.
  assert.ok(mail.html.includes('#70A0D0'));
  assert.ok(mail.html.includes('#5F6A82'));
});

test('a missing name reads as "there"', () => {
  const mail = renderVerificationEmail({
    displayName: null,
    email: 'a@b.c',
    link: 'https://x/l',
    logoUrl: 'https://x/c.png',
  });
  assert.ok(mail.html.includes('Hi there,'));
  assert.ok(mail.text.startsWith('Hi there,'));
});

test('a display name cannot inject markup', () => {
  const mail = renderVerificationEmail({
    displayName: '<img src=x onerror=alert(1)>',
    email: 'a@b.c',
    link: 'https://x/l',
    logoUrl: 'https://x/c.png',
  });
  assert.ok(!mail.html.includes('<img src=x'));
  assert.ok(mail.html.includes('&lt;img src=x onerror=alert(1)&gt;'));
});

test('escapeHtml covers the five characters that matter', () => {
  assert.equal(escapeHtml(`<a href="x" title='y'>&</a>`), '&lt;a href=&quot;x&quot; title=&#39;y&#39;&gt;&amp;&lt;/a&gt;');
});
