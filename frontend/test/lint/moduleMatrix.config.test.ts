import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { ESLint, RuleTester } from 'eslint';
import tseslint from 'typescript-eslint';
import { describe, expect, it } from 'vitest';
import { moduleMatrix, runFrontendLint } from '../../eslint-rules/index.mjs';

const fixture = (name: string): string => readFileSync(
  resolve(process.cwd(), 'test/lint/fixtures', name),
  'utf8',
);

const lintVirtual = (path: string, content: string) => runFrontendLint({
  cwd: process.cwd(),
  args: [path],
  virtualFiles: [{ path, content }],
});

const ruleTester = new RuleTester({
  languageOptions: {
    parser: tseslint.parser,
    parserOptions: { ecmaVersion: 2022, sourceType: 'module' },
  },
});

describe('PF-FE-002 module matrix', () => {
  it('TC-PFL-038 rejects shared to feature imports', () => {
    ruleTester.run('TC-PFL-038', moduleMatrix, {
      valid: [],
      invalid: [{
        code: fixture('TC-PFL-038-shared-feature.ts'),
        filename: 'frontend/src/shared/fixture.ts',
        errors: [{ message: 'shared module cannot import feature module' }],
      }],
    });
  });

  it('TC-PFL-039 rejects feature to app imports', () => {
    ruleTester.run('TC-PFL-039', moduleMatrix, {
      valid: [],
      invalid: [{
        code: fixture('TC-PFL-039-feature-app.ts'),
        filename: 'frontend/src/dailyReport/fixture.ts',
        errors: [{ message: 'feature module cannot import app module' }],
      }],
    });
  });

  it('TC-PFL-040 rejects feature to feature imports', () => {
    ruleTester.run('TC-PFL-040', moduleMatrix, {
      valid: [],
      invalid: [{
        code: fixture('TC-PFL-040-feature-feature.ts'),
        filename: 'frontend/src/dailyReport/fixture.ts',
        errors: [{ message: 'feature module cannot import another feature module' }],
      }],
    });
  });

  it('TC-PFL-041 allows app to feature integration', () => {
    ruleTester.run('TC-PFL-041', moduleMatrix, {
      valid: [{
        code: fixture('TC-PFL-041-app-feature.ts'),
        filename: 'frontend/src/app/fixture.ts',
      }],
      invalid: [],
    });
  });

  it('TC-PFL-042 allows type-only auth types', () => {
    ruleTester.run('TC-PFL-042', moduleMatrix, {
      valid: [{
        code: fixture('TC-PFL-042-type-only-auth.ts'),
        filename: 'frontend/src/dailyReport/fixture.ts',
      }],
      invalid: [],
    });
  });

  it('TC-PFL-043 rejects runtime auth types', () => {
    ruleTester.run('TC-PFL-043', moduleMatrix, {
      valid: [],
      invalid: [{
        code: fixture('TC-PFL-043-runtime-auth.ts'),
        filename: 'frontend/src/dailyReport/fixture.ts',
        errors: [{ message: 'feature may import auth/types only as type-only' }],
      }],
    });
  });

  it('TC-PFL-045 detects a multiline import through the AST', () => {
    ruleTester.run('TC-PFL-045', moduleMatrix, {
      valid: [],
      invalid: [{
        code: "import {\n  MonthlySummaryPage,\n} from '../monthlySummary/MonthlySummaryPage';",
        filename: 'frontend/src/dailyReport/fixture.ts',
        errors: [{ message: 'feature module cannot import another feature module' }],
      }],
    });
  });

  it('TC-PFL-044 covers the actual lcov Node target through Node API', async () => {
    const eslint = new ESLint({ cwd: process.cwd() });
    const target = resolve(process.cwd(), 'scripts/lcov-to-html.mjs');
    expect(await eslint.isPathIgnored(target)).toBe(false);
    const config = await eslint.calculateConfigForFile(target);
    expect(config?.languageOptions?.globals).toMatchObject({ process: 'readonly' });
    const results = await eslint.lintFiles([target]);
    expect(results.map((result) => result.filePath)).toContain(target);
  });

  it('TC-PFL-072 covers the actual lcov regression through Node API', async () => {
    const eslint = new ESLint({ cwd: process.cwd() });
    const target = resolve(process.cwd(), 'scripts/lcov-to-html.mjs');
    expect(await eslint.isPathIgnored(target)).toBe(false);
    const config = await eslint.calculateConfigForFile(target);
    expect(config?.languageOptions?.globals).toMatchObject({ process: 'readonly' });
    const results = await eslint.lintFiles([target]);
    expect(results.map((result) => result.filePath)).toContain(target);
  });

  it('TC-PFL-082 verifies the post-migration lcov target', async () => {
    const eslint = new ESLint({ cwd: process.cwd() });
    const target = resolve(process.cwd(), 'scripts/lcov-to-html.mjs');
    expect(await eslint.isPathIgnored(target)).toBe(false);
    expect(await eslint.calculateConfigForFile(target)).toBeTruthy();
  });

  it('TC-PFL-083 globally ignores invalid fixtures while linting ordinary tests, rules, and scripts', async () => {
    const eslint = new ESLint({ cwd: process.cwd() });
    const invalidFixture = resolve(process.cwd(), 'test/lint/fixtures/TC-PFL-015-invalid-config.mjs');
    const lcovTarget = resolve(process.cwd(), 'scripts/lcov-to-html.mjs');
    expect(await eslint.isPathIgnored(invalidFixture)).toBe(true);

    const results = await eslint.lintFiles([
      'test/lint/frontendLint.cli.test.ts',
      'eslint-rules/index.mjs',
      'eslint-rules/index.d.mts',
      'scripts/frontend-lint.mjs',
      'scripts/lcov-to-html.mjs',
    ]);
    expect(results.every((result) => result.messages.length === 0)).toBe(true);
    expect(results.map((result) => result.filePath)).toEqual(expect.arrayContaining([
      resolve(process.cwd(), 'test/lint/frontendLint.cli.test.ts'),
      resolve(process.cwd(), 'eslint-rules/index.mjs'),
      resolve(process.cwd(), 'eslint-rules/index.d.mts'),
      resolve(process.cwd(), 'scripts/frontend-lint.mjs'),
      lcovTarget,
    ]));
  });

  it('TC-PFL-113 reaches public A for the forbidden shared to auth edge, including type-only exports', async () => {
    // The old matrix only handled ImportDeclaration and omitted this edge,
    // so the public lint result incorrectly reported no violation.
    const path = 'src/shared/authBridge.ts';
    const result = await lintVirtual(path, [
      'export type { CurrentUser } from \'../auth/types\';',
      '',
    ].join('\n'));

    expect(result.exitCode).toBe(1);
    expect(result.stdout).toContain(
      'PF-FE-002|Error|frontend/src/shared/authBridge.ts:1:1|shared module cannot import auth module',
    );
    expect(result.stderr).toBe('');
  }, 30_000);

  it('TC-PFL-114 reaches public A for the forbidden auth to app edge', async () => {
    // The old matrix had no auth-to-app branch, so this export crossed the
    // boundary without a diagnostic.
    const path = 'src/auth/appBridge.ts';
    const result = await lintVirtual(path, [
      'export { App } from \'../app/App\';',
      '',
    ].join('\n'));

    expect(result.exitCode).toBe(1);
    expect(result.stdout).toContain(
      'PF-FE-002|Error|frontend/src/auth/appBridge.ts:1:1|auth module cannot import app module',
    );
    expect(result.stderr).toBe('');
  }, 30_000);

  it('TC-PFL-115 detects an export-named-from dependency through public A', async () => {
    // The old ImportDeclaration-only visitor never inspected this re-export.
    const path = 'src/dailyReport/monthlyBridge.ts';
    const result = await lintVirtual(path, [
      'export { MonthlySummaryPage } from \'../monthlySummary/MonthlySummaryPage\';',
      '',
    ].join('\n'));
    const typeOnlyAuthResult = await lintVirtual('src/dailyReport/authTypes.ts', [
      'export type { CurrentUser } from \'../auth/types\';',
      '',
    ].join('\n'));

    expect(result.exitCode).toBe(1);
    expect(result.stdout).toContain(
      'PF-FE-002|Error|frontend/src/dailyReport/monthlyBridge.ts:1:1|feature module cannot import another feature module',
    );
    expect(result.stderr).toBe('');
    expect(typeOnlyAuthResult.exitCode).toBe(0);
    expect(typeOnlyAuthResult.stdout).toBe('');
    expect(typeOnlyAuthResult.stderr).toBe('');
  }, 30_000);

  it('TC-PFL-116 detects an export-all-from dependency through public A', async () => {
    // The old ImportDeclaration-only visitor also skipped export-all edges.
    const path = 'src/shared/dailyReportBridge.ts';
    const result = await lintVirtual(path, [
      'export * from \'../dailyReport/types\';',
      '',
    ].join('\n'));

    expect(result.exitCode).toBe(1);
    expect(result.stdout).toContain(
      'PF-FE-002|Error|frontend/src/shared/dailyReportBridge.ts:1:1|shared module cannot import feature module',
    );
    expect(result.stderr).toBe('');
  }, 30_000);

  it('TC-PFL-117 detects a static dynamic-import dependency through public A', async () => {
    // The old visitor had no ImportExpression handler, so this feature-to-app
    // edge was invisible even though it is a runtime dependency.
    const path = 'src/dailyReport/lazyApp.ts';
    const result = await lintVirtual(path, [
      'export const loadApp = () => import(\'../app/App\');',
      '',
    ].join('\n'));

    expect(result.exitCode).toBe(1);
    expect(result.stdout).toContain(
      'PF-FE-002|Error|frontend/src/dailyReport/lazyApp.ts:1:1|feature module cannot import app module',
    );
    expect(result.stderr).toBe('');
  }, 30_000);
});
