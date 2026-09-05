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
/** What the backend needs; Shopify's write_x implies read_x. */
const REQUIRED_SCOPES = [
  'read_products', 'write_products', 'read_inventory', 'write_inventory', 'write_publications',
  'read_customers', 'read_orders', 'read_fulfillments', 'write_fulfillments',
];
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
          if (passworded) warn('storefront password', 'the store is password-protected, so the checkout tab shows a password page first', 'dev store admin -> Online Store -> Preferences -> Password protection -> untick "Restrict access" -> Save (or type the password shown there once in the checkout tab)');
          const granted = await grantedScopes(ctx);
          const missingScopes = REQUIRED_SCOPES.filter((s) => !hasScope(granted, s));
          if (missingScopes.length) {
            fail('shopify scopes', `the app is missing ${missingScopes.length} scope(s): ${missingScopes.join(', ')}${granted.length ? ` (has: ${granted.join(', ')})` : ' (it has NONE)'}`,
              'Shopify Dev Dashboard -> Apps -> the app -> Configuration -> Access scopes: add them, save/release, then reinstall the app on the dev store. Without them Shopify refuses every webhook topic and every product read.');
          } else {
            pass('shopify scopes', `all ${REQUIRED_SCOPES.length} required scopes granted`);
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

  // 13. android emulator -------------------------------------------------------------
  const devices = run('flutter', ['devices', '--machine']).out;
  if (/emulator-\d+/.test(devices)) pass('android', `emulator booted (${devices.match(/emulator-\d+/)[0]})`);
  else {
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
