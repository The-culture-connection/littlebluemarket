import { getAuth } from 'firebase-admin/auth';
import { FieldValue, getFirestore, Timestamp } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions';
import { HttpsError } from 'firebase-functions/v2/https';
import nodemailer from 'nodemailer';

import {
  MAIL_FROM,
  PUBLIC_WEB_URL,
  SMTP_HOST,
  SMTP_PASS,
  SMTP_PORT,
  SMTP_USER,
} from './config.ts';
import { projectId } from './diagnostics.ts';

/**
 * The branded "confirm your email" mail (Stage 16).
 *
 * Firebase Auth can send a verification mail itself, but only its own: plain
 * text, from a Google address, in a style nothing else of ours shares. So the
 * app asks this module instead. The link still comes from Firebase (the Admin
 * SDK mints it; the code inside is what proves the address), the HTML is ours
 * and lands in the same welcome blue as the app's onboarding screens, and the
 * page the link opens (`hosting/auth/action.html`) is ours too.
 *
 * Everything that can be tested without a network is a pure function below;
 * `sendVerificationEmailFor` is the one piece that touches Auth, Firestore
 * and the mail server.
 */

// ------------------------------------------------------------- the settings

export interface MailSettings {
  host: string;
  port: number;
  user: string;
  pass: string;
  from: string;
}

/**
 * `SMTP_PASS` is created as `unset` before anyone has a real password, so the
 * deploy and the doctor can go on: that value means "not configured", exactly
 * like an empty one.
 */
export const UNSET_SECRET = 'unset';

/**
 * Turns the raw params into settings, or null when branded mail is not set
 * up yet. Host and password are required; the login defaults to the From
 * address; the From line defaults to the login.
 */
export function mailSettings(raw: {
  host?: string;
  port?: string;
  user?: string;
  pass?: string;
  from?: string;
}): MailSettings | null {
  const host = (raw.host ?? '').trim();
  const pass = (raw.pass ?? '').trim();
  if (!host || !pass || pass === UNSET_SECRET) return null;

  const from = (raw.from ?? '').trim();
  const user = (raw.user ?? '').trim() || addressOf(from);
  if (!user) return null;

  const port = Number.parseInt((raw.port ?? '').trim() || '465', 10);
  return {
    host,
    port: Number.isFinite(port) && port > 0 ? port : 465,
    user,
    pass,
    from: from || `Little Blue Market <${user}>`,
  };
}

/** `Name <addr>` becomes `addr`; a bare address comes back as it is. */
function addressOf(from: string): string {
  const angled = /<([^>]+)>/.exec(from);
  return (angled?.[1] ?? from).trim();
}

/** Where the confirmation page and the cart image live. */
export function publicWebUrl(configured = PUBLIC_WEB_URL.value()): string {
  const url = (configured ?? '').trim().replace(/\/+$/, '');
  return url || `https://${projectId()}.web.app`;
}

// ----------------------------------------------------------------- the link

/**
 * Firebase mints links that open its own handler page
 * (`https://<project>.firebaseapp.com/__/auth/action?mode=...&oobCode=...`).
 * The code in the query is what matters; the page only has to hand it back
 * to Firebase. So the link is pointed at our page instead, query intact,
 * and the plain Google page is never seen. A link that does not look like
 * that (a custom action URL set in the console, say) is left alone.
 */
export function rebrandActionLink(link: string, webUrl: string): string {
  const match = /^https?:\/\/[^/?#]+\/__\/auth\/action\?(.*)$/s.exec(link);
  if (!match) return link;
  return `${webUrl.replace(/\/+$/, '')}/auth/action?${match[1]}`;
}

// -------------------------------------------------------------- the throttle

/** The app's own resend button waits 30 s; the server holds the same line. */
export const RESEND_GAP_MS = 30_000;

export function resendTooSoon(
  lastSentAtMs: number | undefined,
  nowMs: number,
  gapMs = RESEND_GAP_MS,
): boolean {
  if (lastSentAtMs === undefined) return false;
  return nowMs - lastSentAtMs < gapMs;
}

// -------------------------------------------------------------- the message

export interface VerificationMailVars {
  /** The account's display name; a missing one reads as "there". */
  displayName?: string | null;
  email: string;
  link: string;
  logoUrl: string;
}

export interface RenderedMail {
  subject: string;
  html: string;
  text: string;
}

export const VERIFY_SUBJECT = 'Confirm your email for Little Blue Market';

/** Every value goes through this on its way into the HTML. */
export function escapeHtml(value: string): string {
  return value
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

/**
 * The template. Tables and inline styles on purpose: mail clients ignore
 * most of a stylesheet. The colours are the app's tokens: the welcome blue
 * `#70A0D0`, ink `#152E52` / `#31507B`, the onboarding slate button
 * `#5F6A82` with `#F3F8FE` text. The type falls back from Fraunces and
 * Nunito to what the client has, since bundled fonts do not travel by mail.
 */
const TEMPLATE = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="x-apple-disable-message-reformatting">
<title>{{subject}}</title>
<!--[if mso]><style>table,td{font-family:Georgia,serif}</style><![endif]-->
</head>
<body style="margin:0;padding:0;background:#70A0D0;">
<div style="display:none;max-height:0;overflow:hidden;opacity:0;color:transparent;">One tap confirms {{email}} for Little Blue Market.</div>
<table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="background:#70A0D0;">
  <tr>
    <td align="center" style="padding:36px 16px 28px;">
      <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="max-width:480px;">
        <tr>
          <td align="center" style="padding:0 0 18px;">
            <img src="{{logoUrl}}" width="84" height="84" alt="Little Blue Market" style="display:block;width:84px;height:84px;border:0;">
          </td>
        </tr>
        <tr>
          <td style="background:#FFFFFF;border-radius:22px;padding:34px 30px 30px;">
            <h1 style="margin:0 0 10px;font-family:Fraunces,Georgia,'Times New Roman',serif;font-size:27px;line-height:1.15;font-weight:700;color:#152E52;text-align:center;">Confirm your email</h1>
            <p style="margin:0 0 22px;font-family:Nunito,'Helvetica Neue',Helvetica,Arial,sans-serif;font-size:15px;line-height:1.55;color:#31507B;text-align:center;">Hi {{displayName}}, one tap and your Little Blue Market profile is confirmed. That is what lets your shop orders, and your shop if you sell, be linked to it.</p>
            <table role="presentation" cellspacing="0" cellpadding="0" border="0" align="center" style="margin:0 auto 24px;">
              <tr>
                <td align="center" style="background:#5F6A82;border-radius:999px;">
                  <a href="{{link}}" style="display:inline-block;padding:14px 30px;font-family:Nunito,'Helvetica Neue',Helvetica,Arial,sans-serif;font-size:15px;font-weight:800;line-height:1;color:#F3F8FE;text-decoration:none;border-radius:999px;">Confirm my email</a>
                </td>
              </tr>
            </table>
            <p style="margin:0 0 6px;font-family:Nunito,'Helvetica Neue',Helvetica,Arial,sans-serif;font-size:12.5px;line-height:1.5;color:#6B87AD;text-align:center;">If the button does not open, copy this into your browser:</p>
            <p style="margin:0 0 24px;font-family:Nunito,'Helvetica Neue',Helvetica,Arial,sans-serif;font-size:12px;line-height:1.5;text-align:center;word-break:break-all;"><a href="{{link}}" style="color:#2A5992;text-decoration:underline;">{{link}}</a></p>
            <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0">
              <tr><td style="border-top:1px solid #DCE9F7;font-size:0;line-height:0;">&nbsp;</td></tr>
            </table>
            <p style="margin:16px 0 0;font-family:Nunito,'Helvetica Neue',Helvetica,Arial,sans-serif;font-size:12.5px;line-height:1.5;color:#6B87AD;text-align:center;">This link works for a day. You are getting it because {{email}} was used to create a profile in the Little Blue Market app. If that was not you, ignore this and nothing happens.</p>
          </td>
        </tr>
        <tr>
          <td align="center" style="padding:18px 8px 0;font-family:Nunito,'Helvetica Neue',Helvetica,Arial,sans-serif;font-size:12px;line-height:1.5;color:#F3F8FE;">
            Little Blue Market &middot; <a href="https://littlebluecart.com" style="color:#F3F8FE;text-decoration:underline;">littlebluecart.com</a>
          </td>
        </tr>
      </table>
    </td>
  </tr>
</table>
</body>
</html>
`;

/** Fills the template. Every `{{name}}` is escaped; an unknown one is emptied. */
export function renderVerificationEmail(vars: VerificationMailVars): RenderedMail {
  const displayName = (vars.displayName ?? '').trim() || 'there';
  const values: Record<string, string> = {
    subject: VERIFY_SUBJECT,
    displayName,
    email: vars.email,
    link: vars.link,
    logoUrl: vars.logoUrl,
  };
  const html = TEMPLATE.replace(/{{(\w+)}}/g, (_, key: string) =>
    escapeHtml(values[key] ?? ''),
  );
  const text = [
    `Hi ${displayName},`,
    '',
    'One tap and your Little Blue Market profile is confirmed. That is what',
    'lets your shop orders, and your shop if you sell, be linked to it.',
    '',
    `Confirm my email: ${vars.link}`,
    '',
    `This link works for a day. You are getting it because ${vars.email} was`,
    'used to create a profile in the Little Blue Market app. If that was not',
    'you, ignore this and nothing happens.',
    '',
    'Little Blue Market - https://littlebluecart.com',
  ].join('\n');
  return { subject: VERIFY_SUBJECT, html, text };
}

// ---------------------------------------------------------------- delivery

/** Sends one message over SMTP. Replaceable: nothing else knows about nodemailer. */
export async function sendMail(
  settings: MailSettings,
  message: { to: string } & RenderedMail,
): Promise<void> {
  const transport = nodemailer.createTransport({
    host: settings.host,
    port: settings.port,
    secure: settings.port === 465,
    auth: { user: settings.user, pass: settings.pass },
    connectionTimeout: 15_000,
    greetingTimeout: 15_000,
    socketTimeout: 30_000,
  });
  await transport.sendMail({
    from: settings.from,
    to: message.to,
    subject: message.subject,
    html: message.html,
    text: message.text,
  });
}

/** Where the last send for an account is remembered (clients cannot read `_internal`). */
export function throttleDocPath(uid: string): string {
  return `_internal/verificationMail/byUid/${uid}`;
}

/**
 * The callable's body. Mints the link for the caller's own address, renders
 * the mail and sends it. The address always comes from the account, never
 * from the request, so nobody can have a confirmation for a stranger's
 * address sent anywhere.
 *
 * Throws `failed-precondition` (details.reason `mail-not-configured`) while
 * SMTP is not set up and `unavailable` (`mail-failed`) when the mail server
 * refuses; the app treats both as "use Firebase's own mail instead".
 * `resource-exhausted` is the 30-second throttle.
 */
export async function sendVerificationEmailFor(
  uid: string,
  deps: {
    now?: () => number;
    send?: typeof sendMail;
  } = {},
): Promise<{ ok: true; alreadyVerified?: boolean }> {
  const now = deps.now ?? Date.now;
  const send = deps.send ?? sendMail;

  const user = await getAuth().getUser(uid);
  const email = user.email?.trim().toLowerCase();
  if (!email) {
    throw new HttpsError('failed-precondition', 'This account has no email address.');
  }
  if (user.emailVerified) return { ok: true, alreadyVerified: true };

  const settings = mailSettings({
    host: SMTP_HOST.value(),
    port: SMTP_PORT.value(),
    user: SMTP_USER.value(),
    pass: SMTP_PASS.value(),
    from: MAIL_FROM.value(),
  });
  if (!settings) {
    throw new HttpsError(
      'failed-precondition',
      'The branded confirmation email is not set up on this project yet ' +
        '(SMTP_HOST in functions/.env and the SMTP_PASS secret). ' +
        "Firebase's plain email is sent instead.",
      { reason: 'mail-not-configured' },
    );
  }

  const db = getFirestore();
  const ref = db.doc(throttleDocPath(uid));
  const last = (await ref.get()).get('sentAt') as Timestamp | undefined;
  if (resendTooSoon(last?.toMillis(), now())) {
    throw new HttpsError(
      'resource-exhausted',
      'One went out a moment ago. Give it a minute, and check Spam.',
    );
  }

  const webUrl = publicWebUrl();
  const minted = await getAuth().generateEmailVerificationLink(email, {
    url: `${webUrl}/verified`,
    handleCodeInApp: false,
  });
  const link = rebrandActionLink(minted, webUrl);
  const mail = renderVerificationEmail({
    displayName: user.displayName,
    email,
    link,
    logoUrl: `${webUrl}/email/cart.png`,
  });

  try {
    await send(settings, { to: email, ...mail });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    logger.error('Verification email failed', { uid, host: settings.host, message });
    throw new HttpsError(
      'unavailable',
      `The mail server (${settings.host}) refused the message: ${message}. ` +
        'Check SMTP_HOST, SMTP_PORT, SMTP_USER and the SMTP_PASS secret; npm run doctor says which.',
      { reason: 'mail-failed' },
    );
  }

  await ref.set(
    { sentAt: FieldValue.serverTimestamp(), count: FieldValue.increment(1), email },
    { merge: true },
  );
  logger.info('Verification email sent', { uid, host: settings.host });
  return { ok: true };
}
