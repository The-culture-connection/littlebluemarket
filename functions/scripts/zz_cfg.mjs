import { firebaseApiKey, identityDelete, identitySignUp, resolveProject } from './lib/shopify-admin.mjs';
const projectId = resolveProject('prod');
const apiKey = firebaseApiKey();
const a = await identitySignUp(apiKey, { email: `t${Date.now()}@example.com`, password: `T-${Date.now()}!` });
const url = `https://us-central1-${projectId}.cloudfunctions.net/appConfig`;
const r = await fetch(url, { method: 'POST', headers: { Authorization: `Bearer ${a.idToken}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ data: {} }) });
const body = await r.json();
console.log('what a phone on production is now told:');
for (const [k, val] of Object.entries(body.result ?? body)) {
  console.log('  ' + k.padEnd(28) + (val === '' ? '(empty: that surface stays hidden)' : val));
}
await identityDelete(apiKey, a.idToken);