// Turns a public Shopify products.json download (p1.json, p2.json, ...) plus
// an optional collections.json ({productId: [handle]}) into the records the
// catalogue mirror would write, using the mirror's own catalogDocFor.
//   node --experimental-strip-types tool/search_eval/build_catalog.ts <dir>
import fs from 'node:fs';
import { catalogDocFor } from '../../functions/src/catalog.ts';
const dir = process.argv[2];
const cols = fs.existsSync(`${dir}/collections.json`) ? JSON.parse(fs.readFileSync(`${dir}/collections.json`, 'utf8')) : {};
const out: unknown[] = [];
for (const f of fs.readdirSync(dir).filter((f) => /^p\d+\.json$/.test(f))) {
  for (const p of JSON.parse(fs.readFileSync(`${dir}/${f}`, 'utf8')).products) {
    p.status = 'active';
    const { doc } = catalogDocFor(p, { uid: `v:${p.vendor}` }, cols[p.id] ?? []);
    out.push({ id: String(p.id), title: doc.title, description: doc.description, type: doc.type, typeSlug: doc.typeSlug,
      tags: doc.tags, collectionHandles: doc.collectionHandles, searchWords: doc.searchWords, titleWords: doc.titleWords,
      titleLower: doc.titleLower, priceCents: doc.priceCents, sellerId: doc.sellerId });
  }
}
fs.writeFileSync(`${dir}/eval-catalog.json`, JSON.stringify(out));
const types: Record<string, number> = {};
for (const d of out as any[]) types[d.type] = (types[d.type] ?? 0) + 1;
console.log('products', out.length, 'zero price', (out as any[]).filter((d) => !d.priceCents).length);
console.log(Object.entries(types).sort((a, b) => b[1] - a[1]).slice(0, 60).map(([k, v]) => `${k}:${v}`).join(' | '));
