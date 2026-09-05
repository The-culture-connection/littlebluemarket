import { strict as assert } from 'node:assert';
import { test } from 'node:test';

import { decodeJwtClaims, runHealthCheck } from '../src/diagnostics.ts';

test('one failing probe never hides the others', async () => {
  const report = await runHealthCheck([
    { name: 'a', run: async () => ({ summary: 'fine' }) },
    {
      name: 'b',
      fix: 'do the thing',
      run: async () => {
        throw new Error('broken');
      },
    },
    { name: 'c', run: async () => ({ summary: 'also fine', data: { n: 1 } }) },
  ]);

  assert.equal(report.checks.length, 3);
  assert.deepEqual(
    report.checks.map((c) => [c.name, c.ok]),
    [
      ['a', true],
      ['b', false],
      ['c', true],
    ],
  );
  const b = report.checks[1]!;
  assert.equal(b.summary, 'broken');
  assert.equal(b.fix, 'do the thing');
  assert.deepEqual(report.checks[2]!.data, { n: 1 });
  assert.ok(report.at.length > 0);
});

test('a probe that throws a non-Error still reports a summary', async () => {
  const report = await runHealthCheck([
    {
      name: 'weird',
      run: async () => {
        throw 'a string';
      },
    },
  ]);
  assert.equal(report.checks[0]!.ok, false);
  assert.equal(report.checks[0]!.summary, 'a string');
});

test('the JWT decoder reads claims and never returns its input', () => {
  const claims = { sub: '871756', scopes: ['order'], exp: 1_900_000_000 };
  const encode = (o: unknown) =>
    Buffer.from(JSON.stringify(o)).toString('base64url');
  const token = `${encode({ alg: 'RS256' })}.${encode(claims)}.signature`;

  const decoded = decodeJwtClaims(token);
  assert.deepEqual(decoded, claims);
  assert.ok(!JSON.stringify(decoded).includes('signature'));
});

test('the JWT decoder tolerates garbage', () => {
  assert.equal(decodeJwtClaims(''), null);
  assert.equal(decodeJwtClaims('not-a-jwt'), null);
  assert.equal(decodeJwtClaims('a.b.c'), null);
  assert.equal(decodeJwtClaims('a.!!!.c'), null);
});
