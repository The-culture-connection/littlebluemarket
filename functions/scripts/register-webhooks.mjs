#!/usr/bin/env node
//
// Registers the Shopify webhooks this backend needs, idempotently.
//
// Doing this by hand is fine once and error-prone every time after, and a
// subscription that quietly stops existing looks exactly like "nothing is
// selling" — the catalog mirror freezes, revenue stops attributing, and no
// error is raised anywhere. So it is a script, and it is safe to re-run on
// every deploy: it reads what exists first and creates only what is missing.
//
//   npm run webhooks:dev             # register anything missing
//   npm run webhooks:check           # list only; exit 1 if a topic is missing
//   node scripts/register-webhooks.mjs --project dev --url https://…/shopifyWebhook
//
// `--project` takes an alias from .firebaserc or a project id. `--url`
// defaults to the deployed shopifyWebhook URL for that project. The client
// secret is taken from the SHOPIFY_CLIENT_SECRET environment variable, or, if
// unset, read into memory from Secret Manager through the Firebase CLI. It is
// never read from a file and never printed.

import {
  WEBHOOK_TOPICS,
  adminGraphQL,
  arg,
  defaultWebhookUrl,
  hasFlag,
  listWebhookSubscriptions,
  resolveProject,
  shopifyContext,
} from './lib/shopify-admin.mjs';

const CREATE = `
  mutation Create($topic: WebhookSubscriptionTopic!, $url: URL!) {
    webhookSubscriptionCreate(
      topic: $topic
      webhookSubscription: { callbackUrl: $url, format: JSON }
    ) {
      webhookSubscription { id }
      userErrors { field message }
    }
  }
`;

async function main() {
  const projectId = resolveProject(arg('project', 'dev'));
  const url = arg('url', defaultWebhookUrl(projectId));
  const checkOnly = hasFlag('check');

  const ctx = await shopifyContext(projectId, { allowSecretAccess: true });
  const { atUrl, missing, all } = await listWebhookSubscriptions(ctx, url);

  console.log(`Store ${ctx.domain} · webhooks pointed at\n  ${url}\n`);
  for (const topic of WEBHOOK_TOPICS) {
    console.log(`  ${atUrl.has(topic) ? 'present ' : 'MISSING '}  ${topic}`);
  }
  const elsewhere = all.filter((n) => n.endpoint?.callbackUrl && n.endpoint.callbackUrl !== url);
  if (elsewhere.length) {
    console.log(`\n  (${elsewhere.length} other subscription(s) point elsewhere — e.g. Shipturtle's own; left alone)`);
  }

  if (checkOnly) {
    if (missing.length) {
      console.log(`\n${missing.length} missing. Fix: npm run webhooks:dev`);
      process.exit(1);
    }
    console.log('\nAll six present.');
    return;
  }

  let created = 0;
  let failures = 0;
  for (const topic of missing) {
    const data = await adminGraphQL(ctx, CREATE, { topic, url });
    const errors = data.webhookSubscriptionCreate.userErrors;
    if (errors.length) {
      const why = errors.map((e) => e.message).join('; ');
      console.log(`  FAILED   ${topic} — ${why}`);
      if (/protected customer data/i.test(why)) {
        console.log('           (Orders and fulfilments carry customer names and addresses. Shopify Dev Dashboard -> the app -> Configuration (or API access) -> Protected customer data access -> Request access, choose the reason (app functionality) and save; then re-run npm run webhooks:dev.)');
      } else if (/specified topic/i.test(why)) {
        console.log('           (Shopify says this when the app lacks the scope for the topic. Run npm run doctor: the "shopify scopes" line names what to add in the Shopify Dev Dashboard.)');
      }
      failures += 1;
    } else {
      console.log(`  created  ${topic}`);
      created += 1;
    }
  }

  console.log(
    `\n${WEBHOOK_TOPICS.length} topics, ${atUrl.size} already present, ` +
      `${created} created, ${failures} failed`,
  );
  if (failures) process.exit(1);
}

main().catch((error) => {
  console.error(`\nregister-webhooks failed: ${error.message ?? error}`);
  console.error('Paste this whole output to Claude.');
  process.exit(1);
});
