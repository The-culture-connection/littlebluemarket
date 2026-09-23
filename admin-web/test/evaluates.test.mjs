import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';

/**
 * The admin page runs `public/app.js` top to bottom, once, in the browser.
 * There is no build step and no bundler, so nothing catches the one mistake
 * this kind of file is prone to: reading a `const` from a line that runs
 * before the `const` does.
 *
 * On 2026-09-24 that happened. `revalidate()` runs while the announcement
 * form is set up; it reached a pattern declared sixty lines lower down and
 * threw "Cannot access 'NAMED_PATTERN' before initialization". A throw
 * during evaluation abandons the rest of the script, so **every listener
 * below that line was silently never attached** — the advert tools, the
 * directory tools, reports, feedback. The page looked fine and half its
 * buttons did nothing. `node -c` does not catch it, because the syntax is
 * perfectly good.
 *
 * So: evaluate the whole thing here, with the browser stubbed out, and fail
 * if it throws. This asserts the one property that matters and nothing
 * about what the page looks like.
 */

const here = dirname(fileURLToPath(import.meta.url));
const source = readFileSync(join(here, '..', 'public', 'app.js'), 'utf8');

/** Answers to anything, callable, and never the reason a test fails. */
function anything(name = 'stub') {
  const fn = function () { return anything(name); };
  return new Proxy(fn, {
    get(_target, prop) {
      if (prop === Symbol.toPrimitive) return () => '';
      if (prop === 'then') return undefined; // not a thenable, so `await` is safe
      if (prop === 'length') return 0;
      if (prop === 'value') return '';
      if (prop === 'textContent' || prop === 'innerHTML') return '';
      if (prop === 'selectedOptions') return [anything()];
      if (prop === 'classList') return anything();
      return anything(String(prop));
    },
    set() { return true; },
    apply() { return anything(name); },
    construct() { return anything(name); },
  });
}

test('app.js runs to the end, so every listener is attached', async () => {
  // The firebase imports are the only real dependency; swap them for stubs
  // and keep everything else exactly as the browser sees it.
  const body = source
    .replace(/^import[\s\S]*?from\s*'[^']*';\s*$/gm, '')
    .replace(/^export\s+/gm, '');

  const names = [...source.matchAll(/^import\s*\{([^}]*)\}/gm)]
    .flatMap((m) => m[1].split(','))
    .map((n) => n.trim().split(/\s+as\s+/).pop())
    .filter(Boolean);
  assert.ok(names.length > 0, 'the page imports something from firebase');

  const stubs = Object.fromEntries(names.map((n) => [n, anything(n)]));
  const globals = {
    document: anything('document'),
    window: anything('window'),
    location: anything('location'),
    localStorage: anything('localStorage'),
    navigator: anything('navigator'),
    fetch: anything('fetch'),
    console: { log() {}, warn() {}, error() {} },
    setTimeout() { return 0; },
    clearTimeout() {},
    setInterval() { return 0; },
    clearInterval() {},
    URL,
    Date,
    Math,
    JSON,
    String,
    Number,
    Boolean,
    Array,
    Object,
    Set,
    Map,
    Promise,
    RegExp,
    Error,
  };

  const keys = [...Object.keys(stubs), ...Object.keys(globals)];
  const values = [...Object.values(stubs), ...Object.values(globals)];
  // eslint-disable-next-line no-new-func
  const run = new Function(...keys, `"use strict";\n${body}`);
  // A throw here is the bug this test exists for; the message names the line.
  run(...values);
});
