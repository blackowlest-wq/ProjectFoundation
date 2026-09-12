import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';
import { analyzeSuppressionDirectives, runFrontendLint } from '../../eslint-rules/index.mjs';

const fixture = (name: string): string => readFileSync(
  resolve(process.cwd(), 'test/lint/fixtures', name),
  'utf8',
);

const messages = (name: string): string[] => analyzeSuppressionDirectives(fixture(name), `frontend/src/fixture/${name}`).map(
  (diagnostic: { message: string }) => diagnostic.message,
);

const lintVirtual = (path: string, content: string) => runFrontendLint({
  cwd: process.cwd(),
  args: [path],
  virtualFiles: [{ path, content }],
});

describe('PF-SUPPRESS-001 raw suppression policy', () => {
  it('TC-PFL-052 requires explicit rule IDs', () => {
    expect(messages('TC-PFL-052-no-rule-id.ts')).toEqual(['explicit ESLint rule ID is required']);
  });

  it('TC-PFL-053 rejects wildcard rule IDs', () => {
    expect(messages('TC-PFL-053-wildcard.ts')).toEqual(['wildcard ESLint rule ID is prohibited']);
  });

  it('TC-PFL-054 requires an immediate physical preceding reason', () => {
    expect(messages('TC-PFL-054-no-immediate-reason.ts')).toEqual(['immediate preceding Why not is required']);
  });

  it('TC-PFL-055 rejects an empty reason', () => {
    expect(messages('TC-PFL-055-empty-reason.ts')).toEqual(['Why not reason must be non-empty']);
  });

  it('TC-PFL-056 rejects a non-immediate reason', () => {
    expect(messages('TC-PFL-056-non-immediate-reason.ts')).toEqual(['Why not must be immediately preceding']);
  });

  it('TC-PFL-057 accepts an explicit rule with a non-empty immediate reason', () => {
    expect(messages('TC-PFL-057-valid-reason.ts')).toEqual([]);
  });

  it('TC-PFL-110 reaches the public A path for a block suppression directive', async () => {
    // The old line-only scanner skipped this block comment and incorrectly
    // returned a clean result instead of the required reason diagnostic.
    const path = 'src/orders/block-suppression.ts';
    const result = await lintVirtual(path, [
      'const orderCount = 1;',
      '/* eslint-disable no-unused-vars */',
      'export { orderCount };',
      '',
    ].join('\n'));

    expect(result.exitCode).toBe(1);
    expect(result.stdout).toContain(
      'PF-SUPPRESS-001|Error|frontend/src/orders/block-suppression.ts:2:1|immediate preceding Why not is required',
    );
    expect(result.stderr).toBe('');
  }, 30_000);

  it('TC-PFL-111 ignores eslint-disable text inside strings and templates in the public A path', async () => {
    // The old line regex matched the // text inside this string and reported
    // a false suppression violation; AST comment tokens must exclude literals.
    const path = 'src/orders/suppression-text.ts';
    const result = await lintVirtual(path, [
      'const lineText = "// eslint-disable-next-line no-unused-vars";',
      'const templateText = `/* eslint-disable no-unused-vars */`;',
      'export { lineText, templateText };',
      '',
    ].join('\n'));

    expect(result.exitCode).toBe(0);
    expect(result.stdout).toBe('');
    expect(result.stderr).toBe('');
  }, 30_000);

  it('TC-PFL-112 keeps an immediate Why not contract for valid block suppression through public A', async () => {
    const path = 'src/orders/valid-block-suppression.ts';
    const result = await lintVirtual(path, [
      '// Why not: the dependency list is intentionally fixed for the initial render',
      '/* eslint-disable-next-line @typescript-eslint/no-unused-vars */',
      'const unusedOrderCount = 1;',
      '',
    ].join('\n'));

    expect(result.exitCode).toBe(0);
    expect(result.stdout).toBe('');
    expect(result.stderr).toBe('');
  }, 30_000);
});
