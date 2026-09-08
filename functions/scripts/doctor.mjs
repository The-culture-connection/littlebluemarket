#!/usr/bin/env node
//
// The preflight. One line per check, PASS / FAIL / WARN / MANUAL / SKIP, and on
// FAIL the exact command or click that fixes it. Run it at the start of every
// session and after every deploy:
//
//   npm run doctor            # against the dev project
//   npm run doctor:emu        # local emulators: skips the cloud checks
//
// Exits non-zero only when something FAILs. Never prints a secret: the two
// values it needs in memory (the Shopify client secret and the Storefront
// token) are read through `firebase functions:secrets:access` and discarded.

import { existsSync, readFileSync } from 'node:fs';
import { createConnection } from 'node:net';
import { join } from 'node:path';

import {
  REPO_DIR,
  FUNCTIONS_DIR,
  arg,
  hasFlag,
  callFunction,
  countCollection,
  defaultWebhookUrl,
  deployedFunctions,
  exportedFunctions,
  firebaseApiKey,
  firebaseCli,
  identityDelete,
  identitySignUp,
  listWebhookSubscriptions,
  loadParams,
  mintAdminToken,
  adminGraphQL,
  resolveProject,
  secretExists,
  secretValue,
  shellRun,
  storefrontGraphQL,
} from './lib/shopify-admin.mjs';

const PRODUCTION_DOMAIN = 'little-blue-cart-dev.myshopify.com';
/** The live WordPress directory. Dev must talk to its Cloudways staging copy, never to this. */
const PRODUCTION_WP_HOST = 'littlebluecart.com';

/**
 * One WordPress REST call. `authorization` is a Basic header built in memory
 * from a value read out of Secret Manager; it never reaches a message or the
 * console. Returns the JSON and the `X-WP-Total` header.
 */
async function wpFetchJson(url, authorization) {
  const headers = { accept: 'application/json' };
  if (authorization) headers.authorization = authorization;
  const res = await fetch(url, { headers, redirect: 'follow' });
  const text = await res.text();
  if (!res.ok) {
    let hint = text.slice(0, 120);
    if (text.trimStart().startsWith('<')) hint = '(an HTML page: a password box or a firewall)';
    else {
      try {
        const j = JSON.parse(text);
        if (j && (j.code || j.message)) hint = `${j.code ?? ''} ${j.message ?? ''}`.trim();
      } catch { /* not JSON */ }
    }
    throw new Error(`HTTP ${res.status} ${hint}`);
  }
  try {
    const total = Number.parseInt(res.headers.get('x-wp-total') ?? '', 10);
    return { json: JSON.parse(text), total: Number.isFinite(total) ? total : null };
  } catch {
    throw new Error(`HTTP ${res.status} but the body is not JSON (${text.slice(0, 80)})`);
  }
}
async function wpJson(url) {
  return (await wpFetchJson(url)).json;
}
function basicAuth(user, secret) {
  return `Basic ${Buffer.from(`${user}:${secret}`, 'utf8').toString('base64')}`;
}
/** What the backend needs; Shopify's write_x implies read_x. */
const REQUIRED_SCOPES = [
  'read_products', 'write_products', 'read_inventory', 'write_inventory', 'write_publications',
  'read_customers', 'read_orders', 'read_fulfillments', 'write_fulfillments',
];
/** Wanted, not required: without these one feature degrades and says so. */
const OPTIONAL_SCOPES = {
  // Stage 5: the opening stock on a seller's new product needs the shop location.
  read_locations: "a seller's new product is created without its opening stock",
  // Stage 8: a seller marking an order shipped creates the fulfilment on the store.
  read_merchant_managed_fulfillment_orders: 'a seller\'s "mark shipped" is recorded in the app only, not on the store',
  write_merchant_managed_fulfillment_orders: 'a seller\'s "mark shipped" is recorded in the app only, not on the store',
};
function hasScope(granted, scope) {
  return granted.includes(scope) || granted.includes(scope.replace(/^read_/, 'write_'));
}
async function grantedScopes(ctx) {
  const data = await adminGraphQL(ctx, '{ currentAppInstallation { accessScopes { handle } } }');
  return (data.currentAppInstallation?.accessScopes ?? []).map((s) => s.handle);
}

const EMULATOR_PORTS = { firestore: 8080, auth: 9099, functions: 5001, storage: 9199, ui: 4000 };

const results = [];
function record(status, name, summary, fix) {
  results.push({ status, name, summary, fix });
  const line = `${status.padEnd(6)} ${name.padEnd(18)} ${summary}`;
  console.log(line);
  if (fix && (status === 'FAIL' || status === 'WARN' || status === 'MANUAL')) {
    console.log(`       fix -> ${fix}`);
  }
}
const pass = (n, s) => record('PASS', n, s);
const fail = (n, s, fix) => record('FAIL', n, s, fix);
const warn = (n, s, fix) => record('WARN', n, s, fix);
const manual = (n, s, fix) => record('MANUAL', n, s, fix);
const skip = (n, s) => record('SKIP', n, s);

function run(cmd, args) {
  const r = shellRun(cmd, args);
  return { ok: r.ok, out: `${r.stdout}${r.stderr}`.trim() };
}

function version(cmd, args, re) {
  const { ok, out } = run(cmd, args);
  if (!ok) return null;
  const m = out.match(re);
  return m ? m[1] : out.split('\n')[0];
}

function portOpen(port, host = '127.0.0.1') {
  return new Promise((resolve) => {
    const socket = createConnection({ port, host });
    const done = (v) => {
      socket.destroy();
      resolve(v);
    };
    socket.setTimeout(700, () => done(false));
    socket.once('connect', () => done(true));
    socket.once('error', () => done(false));
  });
}

async function main() {
  const alias = arg('project', 'dev');
  const projectId = resolveProject(alias);
  const emulators = hasFlag('emulators');
  const stamp = new Date().toISOString().replace('T', ' ').slice(0, 19);
  console.log(`LBM doctor · project ${projectId} (alias ${alias}) · ${stamp}${emulators ? ' · emulator mode' : ''}\n`);

  // 1. tools ------------------------------------------------------------
  const flutter = version('flutter', ['--version'], /Flutter (\S+)/);
  const firebase = version('firebase', ['--version'], /(\d+\.\d+\.\d+)/);
  const node = process.versions.node;
  const adb = version('adb', ['version'], /version (\S+)/);
  const missing = [
    !flutter && 'flutter (https://docs.flutter.dev/get-started/install/windows)',
    !firebase && 'firebase (npm i -g firebase-tools)',
  ].filter(Boolean);
  if (missing.length) fail('tools', `missing: ${missing.join(', ')}`, 'install the tools listed, then reopen the terminal');
  else pass('tools', `flutter ${flutter} · firebase ${firebase} · node ${node}${adb ? ` · adb ${adb}` : ' · adb not on PATH (flutter devices is used instead)'}`);
  if (Number(node.split('.')[0]) < 22) fail('node', `node ${node} is older than the functions runtime (22)`, 'install Node 22 or newer');
  if (firebase && Number(firebase.split('.')[0]) < 14) warn('firebase-cli', `firebase-tools ${firebase} is old`, 'npm i -g firebase-tools');

  // 2. execution policy -------------------------------------------------
  if (process.platform === 'win32') {
    const { out } = run('powershell', ['-NoProfile', '-Command', 'Get-ExecutionPolicy -Scope CurrentUser']);
    if (/Restricted/i.test(out)) fail('powershell', 'execution policy is Restricted; the scripts\\*.ps1 launchers cannot run', 'Set-ExecutionPolicy -Scope CurrentUser RemoteSigned');
    else pass('powershell', `execution policy ${out || 'Undefined (inherits, fine)'}`);
  }

  // 3. .firebaserc --------------------------------------------------------
  const rc = join(REPO_DIR, '.firebaserc');
  if (!existsSync(rc)) {
    fail('.firebaserc', 'missing, so --project dev resolves to a literal project called "dev"', 'firebase use --add   (alias dev -> little-blue-610e5)');
  } else {
    const projects = JSON.parse(readFileSync(rc, 'utf8')).projects ?? {};
    const active = run('firebase', ['use']).out.split('\n').pop()?.trim();
    if (!projects.dev) fail('.firebaserc', `no "dev" alias (has: ${Object.keys(projects).join(', ') || 'none'})`, 'add "dev": "little-blue-610e5" to .firebaserc');
    else if (active && !active.includes(projects.dev)) warn('.firebaserc', `dev -> ${projects.dev}, but the active project is "${active}"`, 'firebase use dev');
    else pass('.firebaserc', `dev -> ${projects.dev}`);
  }

  // 4. env params ---------------------------------------------------------
  const params = loadParams(projectId);
  const envRel = `functions/.env.${projectId}`;
  if (!params._envFileExists) {
    fail('env params', `${envRel} does not exist`, `create it with SHOPIFY_STORE_DOMAIN, SHOPIFY_CLIENT_ID, SHOPIFY_API_VERSION (see Planning/checkpoints.md Stage 0.4)`);
  } else {
    const empty = ['SHOPIFY_STORE_DOMAIN', 'SHOPIFY_CLIENT_ID'].filter((k) => !params[k]);
    if (empty.length) fail('env params', `${empty.join(', ')} empty in ${envRel}`, `open ${envRel} and set ${empty.join(' and ')}`);
    else if (!params.SHOPIFY_STORE_DOMAIN.endsWith('.myshopify.com')) fail('env params', `SHOPIFY_STORE_DOMAIN "${params.SHOPIFY_STORE_DOMAIN}" should end in .myshopify.com (no https://, no slash)`, `fix the line in ${envRel}`);
    else if (params.SHOPIFY_STORE_DOMAIN === PRODUCTION_DOMAIN) warn('env params', `SHOPIFY_STORE_DOMAIN is the PRODUCTION store (${PRODUCTION_DOMAIN})`, 'dev must point at little-blue-market-devtestingshop.myshopify.com');
    else pass('env params', `${params.SHOPIFY_STORE_DOMAIN} · API ${params.SHOPIFY_API_VERSION ?? '(default)'} · client id set`);
  }

  // 4b. wordpress: the directory's staging copy ---------------------------------
  const wpBase = String(params.WP_BASE_URL ?? '').trim().replace(/\/+$/, '');
  let wpHost = '';
  let wpPublicOk = false;
  try {
    wpHost = wpBase ? new URL(wpBase).host : '';
  } catch {
    wpHost = '';
  }
  if (!wpBase) {
    warn('wordpress', `WP_BASE_URL empty in ${envRel}: directory features off`, 'CP-D0: make the Cloudways staging copy of littlebluecart.com and put its https URL in WP_BASE_URL (Planning/checkpoints.md, Stage 10)');
  } else if (!/^https:\/\//.test(wpBase) || !wpHost) {
    fail('wordpress', `WP_BASE_URL "${wpBase}" must be an https:// URL`, `fix the line in ${envRel}`);
  } else if ((wpHost === PRODUCTION_WP_HOST || wpHost.endsWith(`.${PRODUCTION_WP_HOST}`)) && new URL(wpBase).pathname.replace(/\/+$/, '') === '' && String(params.WP_LIVE_OK ?? '').trim().toLowerCase() !== 'yes') {
    fail('wordpress', `WP_BASE_URL is the LIVE site (${wpHost})`, 'either point at a staging copy, or, if reading the live site is what you want (the app never writes to WordPress), add WP_LIVE_OK=yes to ' + envRel);
  } else {
    const liveByChoice = (wpHost === PRODUCTION_WP_HOST || wpHost.endsWith(`.${PRODUCTION_WP_HOST}`)) && new URL(wpBase).pathname.replace(/\/+$/, '') === '';
    if (liveByChoice) warn('wordpress (live)', 'dev is reading the LIVE littlebluecart.com (WP_LIVE_OK=yes): read-only, but test users, orders and listings you create there are real', 'use existing accounts to test where you can, and delete any test user, order or listing you add on the live site when the checkpoint passes');
    // A WP Staging copy gates visitors behind a login; the app password gets
    // through, so the public checks fall back to it and say so.
    const stagingUser = String(params.WP_APP_USER ?? '').trim();
    const stagingPassword = stagingUser ? (process.env.WP_APP_PASSWORD || secretValue('WP_APP_PASSWORD', projectId)) : '';
    const fallbackAuth = stagingUser && stagingPassword ? basicAuth(stagingUser, stagingPassword) : null;
    let usedFallback = false;
    const read = async (url) => {
      try {
        return await wpJson(url);
      } catch (error) {
        if (fallbackAuth && /HTTP 40[13]/.test(String(error.message))) {
          usedFallback = true;
          return (await wpFetchJson(url, fallbackAuth)).json;
        }
        throw error;
      }
    };
    try {
      const index = await read(`${wpBase}/wp-json/`);
      const namespaces = Array.isArray(index.namespaces) ? index.namespaces : [];
      const missingNs = ['wp/v2', 'wc/v3'].filter((ns) => !namespaces.includes(ns));
      const listings = await read(`${wpBase}/wp-json/wp/v2/vendors_dir_ltg?per_page=1`);
      const one = Array.isArray(listings) && listings.length === 1;
      if (missingNs.length) fail('wordpress', `${wpHost} answers but has no ${missingNs.join(', ')} (WooCommerce off, or the REST API is filtered)`, 'on the staging site: Plugins -> WooCommerce active; a security plugin may be hiding the REST API');
      else if (!one) fail('wordpress', `${wpHost} answers but /wp/v2/vendors_dir_ltg returned no listing (Directories Pro off, or the listing type is not in the REST API)`, 'on the staging site: Plugins -> Directories Pro active, then re-run');
      else {
        const where = new URL(wpBase).pathname.replace(/\/+$/, '') ? `${wpHost}${new URL(wpBase).pathname.replace(/\/+$/, '')} (a copy in a folder under the live domain)` : wpHost;
        pass('wordpress', `staging reachable · ${index.name ?? wpHost} · ${where} · ${usedFallback ? 'visitors are gated, the app password gets through (fine for staging)' : 'listings public'}`);
        wpPublicOk = true;
      }
    } catch (error) {
      const m = String(error.message);
      fail('wordpress', `${wpHost}: ${m.slice(0, 160)}`, /401|403|password/i.test(m)
        ? (fallbackAuth ? 'the site gates visitors and the app password did not get through either: check WP_APP_USER and WP_APP_PASSWORD (CP-D1)' : 'the site gates visitors (a password wall or WP Staging\'s login): finish CP-D1 (WP_APP_USER + WP_APP_PASSWORD) and the doctor will use them here')
        : 'open the staging URL in a browser over https; if it loads, paste this line to Claude');
    }
  }

  if (emulators) {
    skip('secrets', 'emulator mode');
    skip('shopify', 'emulator mode');
    skip('functions', 'emulator mode');
    skip('webhooks', 'emulator mode');
    skip('auth providers', 'emulator mode');
    skip('backend health', 'emulator mode');
  } else {
    // 5. secrets exist ----------------------------------------------------
    const config = readFileSync(join(FUNCTIONS_DIR, 'src', 'config.ts'), 'utf8');
    const secretNames = [...config.matchAll(/defineSecret\(\s*'([A-Z0-9_]+)'/g)].map((m) => m[1]);
    const absent = secretNames.filter((n) => !secretExists(n, projectId));
    if (absent.length) fail('secrets', `missing in Secret Manager: ${absent.join(', ')}`, absent.map((n) => `firebase functions:secrets:set ${n} --project ${alias}`).join('  |  '));
    else pass('secrets', `all ${secretNames.length} exist (${secretNames.join(', ')})`);

    // 5b. wordpress credentials + woocommerce (Stage 10) ---------------------
    if (!wpPublicOk) {
      skip('wp credentials', 'needs the wordpress line above to pass');
      skip('woocommerce', 'needs the wordpress line above to pass');
    } else {
      const appUser = String(params.WP_APP_USER ?? '').trim();
      const appPassword = absent.includes('WP_APP_PASSWORD') ? '' : (process.env.WP_APP_PASSWORD || secretValue('WP_APP_PASSWORD', projectId));
      if (!appUser) {
        warn('wp credentials', `WP_APP_USER empty in ${envRel}: linking directory accounts is off`, 'CP-D1: put your WordPress administrator login in WP_APP_USER (the user the Application Password belongs to)');
      } else if (!appPassword) {
        skip('wp credentials', 'WP_APP_PASSWORD is not in Secret Manager yet (see the secrets line)');
      } else {
        try {
          const { json: me } = await wpFetchJson(`${wpBase}/wp-json/wp/v2/users/me?context=edit`, basicAuth(appUser, appPassword));
          const roles = Array.isArray(me.roles) ? me.roles : [];
          if (!roles.includes('administrator')) fail('wp credentials', `app password works but "${me.slug}" has roles [${roles.join(', ')}]`, 'looking members up by email needs an administrator: make the Application Password under your administrator user and set WP_APP_USER to that login');
          else pass('wp credentials', `app password works · user ${me.slug} · administrator`);
        } catch (error) {
          const m = String(error.message);
          fail('wp credentials', `${wpHost}: ${m.slice(0, 160)}`, /401/.test(m)
            ? `wrong Application Password or wrong WP_APP_USER, or Application Passwords is switched off by a security plugin: staging wp-admin -> Users -> ${appUser} -> Profile -> Application Passwords -> Add New, then npm run secrets:dev -- WP_APP_PASSWORD`
            : /403/.test(m) ? 'a firewall or security plugin strips the Authorization header on staging; allow /wp-json/ for it' : 'paste this line to Claude');
        }
      }
      const wcKey = absent.includes('WC_CONSUMER_KEY') ? '' : (process.env.WC_CONSUMER_KEY || secretValue('WC_CONSUMER_KEY', projectId));
      const wcSecret = absent.includes('WC_CONSUMER_SECRET') ? '' : (process.env.WC_CONSUMER_SECRET || secretValue('WC_CONSUMER_SECRET', projectId));
      if (!wcKey || !wcSecret) {
        skip('woocommerce', 'WC_CONSUMER_KEY / WC_CONSUMER_SECRET not in Secret Manager yet (see the secrets line)');
      } else {
        try {
          const { total } = await wpFetchJson(`${wpBase}/wp-json/wc/v3/orders?per_page=1`, basicAuth(wcKey, wcSecret));
          pass('woocommerce', `key works · ${total ?? '?'} orders`);
        } catch (error) {
          const m = String(error.message);
          fail('woocommerce', `${wpHost}: ${m.slice(0, 160)}`, /401|woocommerce_rest_cannot_view/.test(m)
            ? 'the key is not Read, or key and secret come from different pairs: staging WooCommerce -> Settings -> Advanced -> REST API -> Add key (Read), then npm run secrets:dev -- WC_CONSUMER_KEY and npm run secrets:dev -- WC_CONSUMER_SECRET'
            : 'paste this line to Claude');
        }
      }
    }

    // 6/7. shopify reachable -----------------------------------------------
    let ctx = null;
    if (params.SHOPIFY_STORE_DOMAIN && params.SHOPIFY_CLIENT_ID) {
      const clientSecret = process.env.SHOPIFY_CLIENT_SECRET || secretValue('SHOPIFY_CLIENT_SECRET', projectId);
      if (!clientSecret) {
        fail('shopify admin', 'could not read SHOPIFY_CLIENT_SECRET from Secret Manager', `firebase functions:secrets:set SHOPIFY_CLIENT_SECRET --project ${alias}`);
      } else {
        try {
          const token = await mintAdminToken({ domain: params.SHOPIFY_STORE_DOMAIN, clientId: params.SHOPIFY_CLIENT_ID, clientSecret });
          ctx = { domain: params.SHOPIFY_STORE_DOMAIN, version: params.SHOPIFY_API_VERSION ?? '2026-07', token };
          const shop = await adminGraphQL(ctx, '{ shop { name myshopifyDomain plan { displayName } } }');
          pass('shopify admin', `token mints · shop "${shop.shop.name}" (${shop.shop.myshopifyDomain}, ${shop.shop.plan?.displayName ?? 'plan ?'})`);
          const front = await fetch(`https://${params.SHOPIFY_STORE_DOMAIN}/`, { redirect: 'manual' }).catch(() => null);
          const passworded = front !== null && (front.status === 302 || front.status === 301) && /[/]password/.test(front.headers.get('location') ?? '');
          if (passworded) warn('storefront password', 'the store is password-protected, so the checkout tab shows a password page first', 'a development store usually cannot drop its password (Shopify: choose a plan). Workaround, once per phone: Online Store -> Preferences -> copy the password; in the app tap Open checkout, type it on the password page (it then shows the shop home, that is expected), close the tab, tap Open checkout again. Chrome remembers it from then on.');
          const granted = await grantedScopes(ctx);
          const missingScopes = REQUIRED_SCOPES.filter((s) => !hasScope(granted, s));
          if (missingScopes.length) {
            fail('shopify scopes', `the app is missing ${missingScopes.length} scope(s): ${missingScopes.join(', ')}${granted.length ? ` (has: ${granted.join(', ')})` : ' (it has NONE)'}`,
              'Shopify Dev Dashboard -> Apps -> the app -> Configuration -> Access scopes: add them, save/release, then reinstall the app on the dev store. Without them Shopify refuses every webhook topic and every product read.');
          } else {
            pass('shopify scopes', `all ${REQUIRED_SCOPES.length} required scopes granted`);
          }
          for (const [scope, effect] of Object.entries(OPTIONAL_SCOPES)) {
            if (hasScope(granted, scope)) continue;
            warn('shopify scopes', `optional scope ${scope} not granted: ${effect}`,
              `Shopify Dev Dashboard -> Apps -> the app -> Configuration -> Access scopes: add ${scope}, save/release, then reinstall the app on the dev store.`);
          }
        } catch (error) {
          fail('shopify admin', error.message, 'see the message above; then re-run the doctor');
        }
      }
      if (ctx) {
        try {
          await adminGraphQL(ctx, '{ customers(first: 1) { nodes { id email } } }');
          pass('customer data', 'the app may read customer emails (protected customer fields granted)');
        } catch (error) {
          if (/protected customer data|not approved to use/i.test(error.message)) {
            fail('customer data', 'Shopify refuses to show customer emails to the app', 'Dev Dashboard -> the app -> Configuration -> Protected customer data access -> "Protected customer fields": request Name, Email, Phone, Address (reason: app functionality), save. Linking sign-ins to store customers and attributing website orders need this.');
          } else {
            warn('customer data', error.message.slice(0, 140));
          }
        }
      }
      const storefrontToken = process.env.SHOPIFY_STOREFRONT_PRIVATE_TOKEN || secretValue('SHOPIFY_STOREFRONT_PRIVATE_TOKEN', projectId);
      if (!storefrontToken) {
        fail('shopify storefront', 'could not read SHOPIFY_STOREFRONT_PRIVATE_TOKEN from Secret Manager', `firebase functions:secrets:set SHOPIFY_STOREFRONT_PRIVATE_TOKEN --project ${alias}`);
      } else {
        try {
          const data = await storefrontGraphQL({ domain: params.SHOPIFY_STORE_DOMAIN, version: params.SHOPIFY_API_VERSION ?? '2026-07', token: storefrontToken }, '{ shop { name } }');
          pass('shopify storefront', `token answers · shop "${data.shop.name}"`);
        } catch (error) {
          fail('shopify storefront', error.message, 'see the message above');
        }
      }
    } else {
      skip('shopify admin', 'env params missing (see above)');
      skip('shopify storefront', 'env params missing (see above)');
    }

    // 8. functions deployed ------------------------------------------------
    const expected = exportedFunctions();
    const live = deployedFunctions(projectId);
    if (live === null) {
      fail('functions', 'firebase functions:list failed (not logged in, or no access to the project)', 'firebase login   then re-run');
    } else {
      const notDeployed = expected.filter((n) => !live.includes(n));
      if (notDeployed.length) fail('functions', `${live.length} deployed, ${notDeployed.length} missing: ${notDeployed.join(', ')}`, 'scripts\\deploy-dev.ps1');
      else pass('functions', `all ${expected.length} exported functions are deployed`);
    }

    // 9. webhooks ------------------------------------------------------------
    if (ctx) {
      try {
        const url = defaultWebhookUrl(projectId);
        const { atUrl, missing: missingTopics } = await listWebhookSubscriptions(ctx, url);
        if (missingTopics.length) fail('webhooks', `${atUrl.size}/6 topics registered at shopifyWebhook; missing ${missingTopics.join(', ')}`, missingTopics.every((t) => /^(ORDERS|FULFILLMENTS)_/.test(t))
            ? 'the order and fulfilment topics need Shopify "protected customer data" access: Dev Dashboard -> the app -> Configuration -> Protected customer data access -> Request access (reason: app functionality), save, then npm run webhooks:dev'
            : 'npm run webhooks:dev   (fails with "cannot create a webhook subscription" until the scopes line above is PASS)');
        else pass('webhooks', 'all 6 topics registered at the deployed shopifyWebhook');
      } catch (error) {
        fail('webhooks', error.message, 'npm run webhooks:check');
      }
    } else {
      skip('webhooks', 'needs the Shopify admin check above to pass');
    }

    // 10. auth providers --------------------------------------------------------
    const apiKey = firebaseApiKey();
    let probeToken = null;
    if (!apiKey) {
      fail('auth providers', 'lib/firebase_options.dart has no apiKey', 'flutterfire configure --project=' + projectId);
    } else {
      const anon = await identitySignUp(apiKey, {});
      const email = `lbm-doctor-${Date.now()}@example.com`;
      const pw = await identitySignUp(apiKey, { email, password: `Doctor-${Date.now()}!` });
      const problems = [];
      if (anon.error) problems.push(`Anonymous sign-in is ${anon.error === 'ADMIN_ONLY_OPERATION' ? 'OFF' : `failing (${anon.error})`}`);
      if (pw.error) problems.push(`Email/Password is ${pw.error === 'OPERATION_NOT_ALLOWED' ? 'OFF' : `failing (${pw.error})`}`);
      if (anon.idToken) await identityDelete(apiKey, anon.idToken);
      if (pw.idToken) probeToken = pw.idToken;
      if (problems.length) fail('auth providers', problems.join(' · '), `https://console.firebase.google.com/project/${projectId}/authentication/providers  -> enable Email/Password and Anonymous`);
      else pass('auth providers', 'Email/Password ON · Anonymous ON (checked with a throwaway account, deleted again)');
    }

    // 11. backend health --------------------------------------------------------
    if (live && live.includes('diagnosticsHealthCheck') && probeToken) {
      try {
        const report = await callFunction(projectId, 'diagnosticsHealthCheck', probeToken);
        for (const check of report.checks ?? []) {
          record(check.ok ? 'PASS' : 'FAIL', `  ${check.name}`, check.summary, check.fix);
        }
      } catch (error) {
        fail('backend health', error.message, /401|403/.test(error.message)
          ? 'the function refused the call. If the body below is HTML, Cloud Run IAM is blocking public invocation: in Google Cloud Console -> Cloud Run -> diagnosticsHealthCheck -> Security, allow unauthenticated invocations (Firebase callables check the Firebase token themselves). Otherwise: firebase functions:log --only diagnosticsHealthCheck --project ' + alias
          : 'firebase functions:log --only diagnosticsHealthCheck --project ' + alias);
      }
    } else if (!live || !live.includes('diagnosticsHealthCheck')) {
      skip('backend health', 'diagnosticsHealthCheck is not deployed yet (lands in Stage 1)');
    } else {
      skip('backend health', 'needs an Email/Password account to call the function');
    }

    // catalog count (informational) --------------------------------------------
    if (probeToken) {
      try {
        const n = await countCollection(projectId, probeToken, 'catalog');
        if (n === 0) warn('catalog', '0 documents in the catalog mirror', 'npm run touch-products   (after webhooks are registered)');
        else pass('catalog', `${n} product document(s) mirrored`);
      } catch (error) {
        warn('catalog', error.message.slice(0, 120));
      }
      await identityDelete(apiKey, probeToken);
    }

    manual('console', 'confirm the project is on the Blaze plan', `https://console.firebase.google.com/project/${projectId}/usage`);
  }

  // 12. emulator ports -----------------------------------------------------------
  const inUse = [];
  for (const [name, port] of Object.entries(EMULATOR_PORTS)) {
    if (await portOpen(port)) inUse.push(`${name}:${port}`);
  }
  if (emulators) {
    if (inUse.length < 4) fail('emulator ports', `only ${inUse.join(', ') || 'none'} answering`, 'scripts\\run-emulators.ps1  (starts firebase emulators:start)');
    else pass('emulator ports', `emulators answering on ${inUse.join(', ')}`);
  } else if (inUse.length) {
    warn('emulator ports', `something is listening on ${inUse.join(', ')}`, 'fine if you started the emulators on purpose; otherwise: netstat -ano | findstr :8080');
  } else {
    pass('emulator ports', 'free');
  }

  // 12b. push (Stage 12) ------------------------------------------------------------
  const manifestPath = join(REPO_DIR, 'android', 'app', 'src', 'main', 'AndroidManifest.xml');
  const manifest = existsSync(manifestPath) ? readFileSync(manifestPath, 'utf8') : '';
  const pushProblems = [
    !manifest.includes('android.permission.POST_NOTIFICATIONS') && 'POST_NOTIFICATIONS permission missing from AndroidManifest.xml',
    !manifest.includes('default_notification_channel_id') && 'default_notification_channel_id meta-data missing from AndroidManifest.xml',
    !existsSync(join(REPO_DIR, 'android', 'app', 'google-services.json')) && 'android/app/google-services.json missing',
    !existsSync(join(REPO_DIR, 'android', 'app', 'src', 'main', 'res', 'drawable', 'ic_stat_lbm.xml')) && 'res/drawable/ic_stat_lbm.xml missing',
  ].filter(Boolean);
  if (pushProblems.length) fail('push', pushProblems.join(' · '), 'these are in the repo (CP-N0); git status, then paste this line to Claude');
  else pass('push', 'manifest permission + channel + icon present · google-services.json present');
  const iosWired = existsSync(join(REPO_DIR, 'ios', 'Runner', 'Runner.entitlements'))
    && (existsSync(join(REPO_DIR, 'ios', 'Runner', 'Info.plist')) && readFileSync(join(REPO_DIR, 'ios', 'Runner', 'Info.plist'), 'utf8').includes('remote-notification'));
  if (!iosWired) fail('push (iPhone)', 'ios/Runner/Runner.entitlements or the remote-notification background mode is missing', 'these are in the repo (CP-N4); git status, then paste this line to Claude');
  else if (!existsSync(join(REPO_DIR, 'ios', 'Runner', 'GoogleService-Info.plist'))) {
    manual('push (iPhone)', 'entitlements wired · ios/Runner/GoogleService-Info.plist is not in the repo yet, so the iPhone build cannot talk to Firebase', 'on a Mac: flutterfire configure --project=' + projectId + ' --platforms=ios (commit the plist; it is public config), then the APNs key in the Firebase console (Planning/checkpoints.md CP-N4)');
  } else {
    pass('push (iPhone)', 'entitlements, background mode and GoogleService-Info.plist present (APNs key: Firebase console -> Cloud Messaging)');
  }

  // 13. android emulator -------------------------------------------------------------
  const devices = run('flutter', ['devices', '--machine']).out;
  if (/emulator-\d+/.test(devices)) {
    const serial = devices.match(/emulator-\d+/)[0];
    pass('android', `emulator booted (${serial})`);
    // Push needs Google Play services on the image; a plain AOSP image never
    // receives one and gives no error, which is the hardest failure to see.
    if (adb) {
      const gms = run('adb', ['-s', serial, 'shell', 'pm', 'list', 'packages', 'com.google.android.gms']).out;
      if (/com\.google\.android\.gms/.test(gms)) pass('android push', 'the emulator has Google Play services');
      else warn('android push', 'this emulator image has no Google Play services: notifications will never arrive on it', 'Android Studio -> Device Manager -> Create device -> pick a system image marked "Google Play" (Android 13 or newer), then run-live on that one');
    }
  } else {
    const qemu = run(process.platform === 'win32' ? 'tasklist' : 'ps', process.platform === 'win32' ? [] : ['-A']).out;
    if (/qemu-system/i.test(qemu)) warn('android', 'an emulator process is running but adb cannot see it', 'adb kill-server; adb start-server   (then re-run the doctor)');
    else warn('android', 'no Android emulator running', 'Android Studio -> Device Manager -> Play, or: flutter emulators --launch Pixel_3');
  }

  // summary -----------------------------------------------------------------------
  const count = (s) => results.filter((r) => r.status === s).length;
  console.log(`\n${count('FAIL')} FAIL, ${count('WARN')} WARN, ${count('MANUAL')} MANUAL, ${count('PASS')} PASS.`);
  if (count('FAIL')) {
    console.log('Paste this whole block to Claude if you cannot fix a FAIL line.');
    process.exit(1);
  }
  console.log('Ready. Next: scripts\\run-live.ps1');
}

main().catch((error) => {
  console.error(`\ndoctor crashed: ${error.stack ?? error}`);
  console.error('Paste this whole output to Claude.');
  process.exit(2);
});
