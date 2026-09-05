import * as crypto from 'node:crypto';

import { getFirestore } from 'firebase-admin/firestore';
import { GoogleAuth } from 'google-auth-library';

import {
  SHIPTURTLE_API_KEY,
  SHIPTURTLE_BASE_URL,
  SHOPIFY_CLIENT_ID,
  SHOPIFY_STORE_DOMAIN,
} from './config.ts';
import { adminGraphQL } from './shopify/token.ts';
import { storefrontGraphQL } from './shopify/storefront.ts';

/**
 * The backend health check.
 *
 * Answers, from inside the deployed functions, the questions the doctor
 * script can only guess at from a laptop: can *this* runtime mint an Admin
 * token, does the Storefront token work, which webhook topics point at us,
 * are the deployed rules the ones in the repo, is the Shipturtle key present.
 * Each probe runs in its own try/catch, so one failure never hides the rest,
 * and each failing row carries the fix.
 *
 * Reports booleans, counts and hashes. Never a secret.
 */

export interface Check {
  name: string;
  ok: boolean;
  summary: string;
  fix?: string;
  data?: Record<string, unknown>;
}

export interface HealthReport {
  project: string;
  at: string;
  checks: Check[];
}

export interface Probe {
  name: string;
  run: () => Promise<{ summary: string; data?: Record<string, unknown> }>;
  fix?: string;
}

export const WEBHOOK_TOPICS = [
  'PRODUCTS_CREATE',
  'PRODUCTS_UPDATE',
  'PRODUCTS_DELETE',
  'ORDERS_PAID',
  'FULFILLMENTS_CREATE',
  'FULFILLMENTS_UPDATE',
];

export function projectId(): string {
  if (process.env.GCLOUD_PROJECT) return process.env.GCLOUD_PROJECT;
  try {
    return JSON.parse(process.env.FIREBASE_CONFIG ?? '{}').projectId ?? '?';
  } catch {
    return '?';
  }
}

export async function runHealthCheck(probes: Probe[]): Promise<HealthReport> {
  const checks: Check[] = [];
  for (const probe of probes) {
    try {
      const result = await probe.run();
      checks.push({ name: probe.name, ok: true, summary: result.summary, data: result.data });
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      checks.push({ name: probe.name, ok: false, summary: message, fix: probe.fix });
    }
  }
  return { project: projectId(), at: new Date().toISOString(), checks };
}

/**
 * The claims of a JWT, without verifying it. Used only to say what a stored
 * Shipturtle token *claims* to be (scopes, expiry) — never to trust it, and
 * never to echo it.
 */
export function decodeJwtClaims(token: string): Record<string, unknown> | null {
  const parts = token.split('.');
  if (parts.length !== 3 || !parts[1]) return null;
  try {
    const json = Buffer.from(parts[1].replace(/-/g, '+').replace(/_/g, '/'), 'base64').toString('utf8');
    const parsed = JSON.parse(json);
    return parsed && typeof parsed === 'object' ? parsed : null;
  } catch {
    return null;
  }
}

function secret(read: () => string): string {
  try {
    return read();
  } catch {
    return '';
  }
}

export function defaultProbes(): Probe[] {
  return [
    {
      name: 'storeDomain',
      fix: 'set SHOPIFY_STORE_DOMAIN in functions/.env.<project-id> and redeploy',
      run: async () => {
        const domain = SHOPIFY_STORE_DOMAIN.value();
        if (!domain) throw new Error('SHOPIFY_STORE_DOMAIN is empty');
        if (!domain.endsWith('.myshopify.com')) throw new Error(`"${domain}" should end in .myshopify.com`);
        return { summary: domain };
      },
    },
    {
      name: 'clientId',
      fix: 'set SHOPIFY_CLIENT_ID in functions/.env.<project-id> and redeploy',
      run: async () => {
        const id = SHOPIFY_CLIENT_ID.value();
        if (!id) throw new Error('SHOPIFY_CLIENT_ID is empty');
        return { summary: `${id.slice(0, 8)}…` };
      },
    },
    {
      name: 'adminToken',
      fix: 'reinstall the app on the store, then firebase functions:secrets:set SHOPIFY_CLIENT_SECRET --project dev',
      run: async () => {
        const data = await adminGraphQL<{
          shop: { name: string; myshopifyDomain: string; plan: { displayName: string } | null };
          currentAppInstallation: { accessScopes: Array<{ handle: string }> } | null;
        }>('{ shop { name myshopifyDomain plan { displayName } } currentAppInstallation { accessScopes { handle } } }');
        const scopes = (data.currentAppInstallation?.accessScopes ?? []).map((s) => s.handle);
        return {
          summary: `shop "${data.shop.name}" (${data.shop.myshopifyDomain}) · ${scopes.length} scope(s)`,
          data: { scopes },
        };
      },
    },
    {
      name: 'shopifyScopes',
      fix: 'Shopify Dev Dashboard -> the app -> Configuration -> Access scopes; add the missing ones, release, reinstall on the store',
      run: async () => {
        const required = [
          'read_products', 'write_products', 'read_inventory', 'write_inventory', 'write_publications',
          'read_customers', 'read_orders', 'read_fulfillments', 'write_fulfillments',
        ];
        const data = await adminGraphQL<{
          currentAppInstallation: { accessScopes: Array<{ handle: string }> } | null;
        }>('{ currentAppInstallation { accessScopes { handle } } }');
        const granted = (data.currentAppInstallation?.accessScopes ?? []).map((s) => s.handle);
        const has = (s: string) => granted.includes(s) || granted.includes(s.replace(/^read_/, 'write_'));
        const missing = required.filter((s) => !has(s));
        if (missing.length) throw new Error(`missing ${missing.join(', ')}${granted.length ? '' : ' (the app has no scopes at all)'}`);
        return { summary: `all ${required.length} required scopes granted` };
      },
    },
    {
      name: 'storefrontToken',
      fix: 'firebase functions:secrets:set SHOPIFY_STOREFRONT_PRIVATE_TOKEN --project dev',
      run: async () => {
        const data = await storefrontGraphQL<{ shop: { name: string } }>('{ shop { name } }');
        return { summary: `answers · shop "${data.shop.name}"` };
      },
    },
    {
      name: 'webhooks',
      fix: 'cd functions; npm run webhooks:dev',
      run: async () => {
        const data = await adminGraphQL<{
          webhookSubscriptions: {
            nodes: Array<{ topic: string; endpoint: { callbackUrl?: string } | null }>;
          };
        }>('{ webhookSubscriptions(first: 100) { nodes { topic endpoint { ... on WebhookHttpEndpoint { callbackUrl } } } } }');
        const ours = data.webhookSubscriptions.nodes.filter((n) =>
          (n.endpoint?.callbackUrl ?? '').includes('shopifyWebhook'),
        );
        const topics = new Set(ours.map((n) => n.topic));
        const missing = WEBHOOK_TOPICS.filter((t) => !topics.has(t));
        if (missing.length) throw new Error(`${topics.size}/6 registered; missing ${missing.join(', ')}`);
        return { summary: 'all 6 topics registered', data: { topics: [...topics] } };
      },
    },
    {
      name: 'shipturtleKey',
      fix: 'firebase functions:secrets:set SHIPTURTLE_API_KEY --project dev',
      run: async () => {
        const key = secret(() => SHIPTURTLE_API_KEY.value());
        if (!key) throw new Error('SHIPTURTLE_API_KEY is empty (Shipturtle features are off)');
        const claims = decodeJwtClaims(key);
        if (!claims) return { summary: `present (${key.length} chars, not a JWT) · base ${SHIPTURTLE_BASE_URL.value()}` };
        const exp = typeof claims.exp === 'number' ? new Date(claims.exp * 1000) : null;
        const expired = exp !== null && exp.getTime() < Date.now();
        const scopes = Array.isArray(claims.scopes) ? claims.scopes.join(',') : '?';
        if (expired) throw new Error(`the stored token expired on ${exp?.toISOString()}`);
        return {
          summary: `present · scopes [${scopes}] · expires ${exp?.toISOString() ?? '?'} · base ${SHIPTURTLE_BASE_URL.value()}`,
          data: { scopes: claims.scopes, exp: exp?.toISOString() },
        };
      },
    },
    {
      name: 'authProviders',
      fix: `https://console.firebase.google.com/project/${projectId()}/authentication/providers -> enable Email/Password and Anonymous`,
      run: async () => {
        const auth = new GoogleAuth({ scopes: ['https://www.googleapis.com/auth/cloud-platform'] });
        const client = await auth.getClient();
        const url = `https://identitytoolkit.googleapis.com/admin/v2/projects/${projectId()}/config`;
        const response = await client.request<{
          signIn?: { email?: { enabled?: boolean; passwordRequired?: boolean }; anonymous?: { enabled?: boolean } };
        }>({ url });
        const email = response.data.signIn?.email?.enabled === true;
        const anon = response.data.signIn?.anonymous?.enabled === true;
        if (!email || !anon) throw new Error(`Email/Password ${email ? 'ON' : 'OFF'} · Anonymous ${anon ? 'ON' : 'OFF'}`);
        return { summary: 'Email/Password ON · Anonymous ON' };
      },
    },
    {
      name: 'rulesSha',
      fix: 'firebase deploy --only firestore:rules --project dev',
      run: async () => {
        const auth = new GoogleAuth({ scopes: ['https://www.googleapis.com/auth/cloud-platform'] });
        const client = await auth.getClient();
        const base = `https://firebaserules.googleapis.com/v1/projects/${projectId()}`;
        const release = await client.request<{ rulesetName?: string }>({ url: `${base}/releases/cloud.firestore` });
        const rulesetName = release.data.rulesetName;
        if (!rulesetName) throw new Error('no cloud.firestore release found');
        const ruleset = await client.request<{ source?: { files?: Array<{ content?: string }> } }>({
          url: `https://firebaserules.googleapis.com/v1/${rulesetName}`,
        });
        const content = (ruleset.data.source?.files?.[0]?.content ?? '').replace(/\r\n/g, '\n');
        const sha = crypto.createHash('sha256').update(content).digest('hex');
        const real = content.includes('money is never client-writable');
        if (!real) throw new Error(`deployed rules are not the repo rules (sha ${sha.slice(0, 12)})`);
        return { summary: `deployed rules sha ${sha.slice(0, 12)} (the repo's file)`, data: { sha } };
      },
    },
    {
      name: 'counts',
      run: async () => {
        const db = getFirestore();
        const [catalog, sellers, vendorNames] = await Promise.all(
          ['catalog', 'sellers', 'vendorNames'].map((c) => db.collection(c).count().get()),
        );
        const n = (s: { data(): { count: number } }) => s.data().count;
        return {
          summary: `catalog ${n(catalog!)} · sellers ${n(sellers!)} · vendorNames ${n(vendorNames!)}`,
          data: { catalog: n(catalog!), sellers: n(sellers!), vendorNames: n(vendorNames!) },
        };
      },
    },
  ];
}
