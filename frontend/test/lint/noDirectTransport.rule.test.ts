import { spawn } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { RuleTester } from 'eslint';
import tseslint from 'typescript-eslint';
import { describe, expect, it } from 'vitest';
import { noDirectTransportAccess, runFrontendLint } from '../../eslint-rules/index.mjs';

const fixture = (name: string): string => readFileSync(
  resolve(process.cwd(), 'test/lint/fixtures', name),
  'utf8',
);

const parserOptions = {
  ecmaVersion: 2022,
  sourceType: 'module' as const,
};

type ChildResult = { status: number | null; stdout: string; stderr: string };

const CHILD_PROCESS_TIMEOUT_MS = 20_000;
const CHILD_PROCESS_KILL_GRACE_MS = 1_000;

function runChild(args: string[]): Promise<ChildResult> {
  return new Promise((resolveResult, reject) => {
    const child = spawn(process.execPath, args, {
      cwd: process.cwd(),
      env: { ...process.env },
    });
    let stdout = '';
    let stderr = '';
    let settled = false;
    let timedOut = false;
    const timerHandles: {
      timeout?: ReturnType<typeof setTimeout>;
      kill?: ReturnType<typeof setTimeout>;
    } = {};
    const timeoutError = new Error(
      `Child process timed out after ${CHILD_PROCESS_TIMEOUT_MS}ms`,
    );

    const clearTimers = (): void => {
      if (timerHandles.timeout !== undefined) {
        clearTimeout(timerHandles.timeout);
        timerHandles.timeout = undefined;
      }
      if (timerHandles.kill !== undefined) {
        clearTimeout(timerHandles.kill);
        timerHandles.kill = undefined;
      }
    };

    const rejectOnce = (error: Error): void => {
      if (settled) return;
      settled = true;
      clearTimers();
      reject(error);
    };

    const resolveOnce = (status: number | null): void => {
      if (settled) return;
      settled = true;
      clearTimers();
      resolveResult({ status, stdout, stderr });
    };

    child.stdout.on('data', (chunk: Buffer) => { stdout += chunk.toString(); });
    child.stderr.on('data', (chunk: Buffer) => { stderr += chunk.toString(); });
    child.once('error', (error) => {
      if (!timedOut) rejectOnce(error);
    });
    child.once('close', (status) => {
      if (timedOut) {
        rejectOnce(timeoutError);
        return;
      }
      resolveOnce(status);
    });

    timerHandles.timeout = setTimeout(() => {
      timedOut = true;
      if (child.exitCode === null && child.signalCode === null) {
        child.kill('SIGTERM');
      }
      timerHandles.kill = setTimeout(() => {
        if (child.exitCode === null && child.signalCode === null) {
          child.kill('SIGKILL');
        }
        rejectOnce(timeoutError);
      }, CHILD_PROCESS_KILL_GRACE_MS);
    }, CHILD_PROCESS_TIMEOUT_MS);
  });
}

const lintVirtual = (path: string, content: string) => runFrontendLint({
  cwd: process.cwd(),
  args: [path],
  virtualFiles: [{ path, content }],
});

const ruleTester = new RuleTester({
  languageOptions: {
    parser: tseslint.parser,
    parserOptions,
  },
});

describe('PF-FE-001 no direct transport access', () => {
  it('TC-PFL-011 detects the fixed valid-rule diagnostic', () => {
    ruleTester.run('TC-PFL-011', noDirectTransportAccess, {
      valid: [],
      invalid: [{
        code: fixture('TC-PFL-011-valid-rule.ts'),
        filename: 'frontend/src/orders/orderApi.ts',
        errors: [{ message: 'direct global fetch is prohibited', line: 1, column: 1 }],
      }],
    });
  });

  it('TC-PFL-012 observes an intentional RuleTester assertion mismatch in a child process', async () => {
    const ruleUrl = pathToFileURL(resolve(process.cwd(), 'eslint-rules/index.mjs')).href;
    const fixturePath = resolve(process.cwd(), 'test/lint/fixtures/TC-PFL-012-red-mismatch.ts');
    const redHarness = `
import { readFileSync } from 'node:fs';
import { RuleTester } from 'eslint';
import tseslint from 'typescript-eslint';
import { noDirectTransportAccess } from ${JSON.stringify(ruleUrl)};

const expected = 'direct global fetch is prohibited (intentional RED mismatch)';
const actual = 'direct global fetch is prohibited';
try {
  new RuleTester({
    languageOptions: {
      parser: tseslint.parser,
      parserOptions: { ecmaVersion: 2022, sourceType: 'module' },
    },
  }).run('TC-PFL-012', noDirectTransportAccess, {
    valid: [],
    invalid: [{
      code: readFileSync(${JSON.stringify(fixturePath)}, 'utf8'),
      filename: 'frontend/src/orders/orderApi.ts',
      errors: [{ message: expected, line: 1, column: 1 }],
    }],
  });
  process.exit(0);
} catch (error) {
  process.stderr.write('RED mismatch\\n');
  process.stderr.write('expected: ' + expected + '\\n');
  process.stderr.write('actual: ' + actual + '\\n');
  process.stderr.write(String(error?.message ?? error) + '\\n');
  process.exit(1);
}
`;
    const result = await runChild(['--input-type=module', '-e', redHarness]);
    expect(result.status).toBe(1);
    expect(result.stderr).toContain('RED mismatch');
    expect(result.stderr).toContain('expected: direct global fetch is prohibited (intentional RED mismatch)');
    expect(result.stderr).toContain('actual: direct global fetch is prohibited');
    expect(result.stderr).toContain('direct global fetch is prohibited');
  }, 30_000);

  it('TC-PFL-026 rejects a global fetch outside apiClient', () => {
    ruleTester.run('TC-PFL-026', noDirectTransportAccess, {
      valid: [],
      invalid: [{
        code: fixture('TC-PFL-026-direct-fetch.ts'),
        filename: 'frontend/src/orders/orderApi.ts',
        errors: [{ message: 'direct global fetch is prohibited', line: 1, column: 1 }],
      }],
    });
  });

  it('TC-PFL-027 rejects document.cookie reads', () => {
    ruleTester.run('TC-PFL-027', noDirectTransportAccess, {
      valid: [],
      invalid: [{
        code: fixture('TC-PFL-027-cookie-read.ts'),
        filename: 'frontend/src/auth/session.ts',
        errors: [{ message: 'document.cookie read is prohibited outside apiClient', line: 1, column: 1 }],
      }],
    });
  });

  it('TC-PFL-028 rejects document.cookie writes', () => {
    ruleTester.run('TC-PFL-028', noDirectTransportAccess, {
      valid: [],
      invalid: [{
        code: fixture('TC-PFL-028-cookie-write.ts'),
        filename: 'frontend/src/auth/session.ts',
        errors: [{ message: 'document.cookie write is prohibited outside apiClient', line: 1, column: 1 }],
      }],
    });
  });

  it('TC-PFL-029 rejects CSRF token reads', () => {
    ruleTester.run('TC-PFL-029', noDirectTransportAccess, {
      valid: [],
      invalid: [{
        code: fixture('TC-PFL-029-csrf-read.ts'),
        filename: 'frontend/src/orders/orderApi.ts',
        errors: [{ message: 'CSRF token read is prohibited outside apiClient', line: 1, column: 1 }],
      }],
    });
  });

  it('TC-PFL-030 rejects CSRF header construction', () => {
    ruleTester.run('TC-PFL-030', noDirectTransportAccess, {
      valid: [],
      invalid: [{
        code: fixture('TC-PFL-030-csrf-header.ts'),
        filename: 'frontend/src/orders/orderApi.ts',
        errors: [{ message: 'CSRF header construction is prohibited outside apiClient', line: 1, column: 1 }],
      }],
    });
  });

  it('TC-PFL-031 allows a shadowed local fetch', () => {
    ruleTester.run('TC-PFL-031', noDirectTransportAccess, {
      valid: [{
        code: fixture('TC-PFL-031-shadowed-fetch.ts'),
        filename: 'frontend/src/orders/orderApi.ts',
      }],
      invalid: [],
    });
  });

  it('TC-PFL-032 allows the shared apiClient boundary', () => {
    ruleTester.run('TC-PFL-032', noDirectTransportAccess, {
      valid: [{
        code: fixture('TC-PFL-032-api-client.ts'),
        filename: 'frontend/src/shared/apiClient.ts',
      }],
      invalid: [],
    });
  });

  it('TC-PFL-033 allows transport use in test and E2E scopes', () => {
    ruleTester.run('TC-PFL-033', noDirectTransportAccess, {
      valid: [{
        code: fixture('TC-PFL-033-test-fetch.ts'),
        filename: 'frontend/e2e/example.spec.ts',
      }],
      invalid: [],
    });
  });

  it('TC-PFL-034 ignores fetch text in comments and strings', () => {
    ruleTester.run('TC-PFL-034', noDirectTransportAccess, {
      valid: [{
        code: "// fetch('/api/orders')\nconst source = \"fetch('/api/orders')\";\nexport { source };",
        filename: 'frontend/src/orders/orderApi.ts',
      }],
      invalid: [],
    });
  });

  it('TC-PFL-035 detects a multiline global fetch call through the AST', () => {
    ruleTester.run('TC-PFL-035', noDirectTransportAccess, {
      valid: [],
      invalid: [{
        code: "fetch(\n  '/api/orders',\n);",
        filename: 'frontend/src/orders/orderApi.ts',
        errors: [{ message: 'direct global fetch is prohibited', line: 1, column: 1 }],
      }],
    });
  });

  it('TC-PFL-118 reaches public A for qualified transport globals while excluding shadowed locals', async () => {
    // The old rule only recognized bare fetch/document references.  Qualified
    // browser globals must use the same policy, without treating local names
    // as browser globals.
    const path = 'src/orders/qualified-transport.ts';
    const result = await lintVirtual(path, [
      "window.fetch('/window');",
      "globalThis.fetch('/globalThis');",
      "self.fetch('/self');",
      'window.document.cookie;',
      "export const csrfToken = globalThis.document.cookie;",
      "globalThis.document.cookie = 'session=value';",
      'function useLocalObjects() {',
      "  const window = { fetch: () => undefined };",
      "  const document = { cookie: 'local' };",
      "  window.fetch('/local');",
      '  document.cookie;',
      '}',
      'useLocalObjects();',
      '',
    ].join('\n'));

    expect(result.exitCode).toBe(1);
    expect(result.stdout.match(/direct global fetch is prohibited/g)).toHaveLength(3);
    expect(result.stdout).toContain('document.cookie read is prohibited outside apiClient');
    expect(result.stdout).toContain('CSRF token read is prohibited outside apiClient');
    expect(result.stdout).toContain('document.cookie write is prohibited outside apiClient');
    expect(result.stdout).not.toContain('qualified-transport.ts:10:3');
    expect(result.stderr).toBe('');
  }, 30_000);

  it('TC-PFL-119 reaches public A for const fetch aliases and preserves the apiClient exception', async () => {
    // The old rule missed calls through const aliases, while the existing
    // apiClient boundary must continue to permit all transport primitives.
    const aliasPath = 'src/orders/fetch-alias.ts';
    const aliasResult = await lintVirtual(aliasPath, [
      'export function callBareAlias() {',
      '  const f = fetch;',
      "  return f('/bare-alias');",
      '}',
      'export function callGlobalThisAlias() {',
      '  const f = globalThis.fetch;',
      "  return f('/global-this-alias');",
      '}',
      'export function callWindowAlias() {',
      '  const f = window.fetch;',
      "  return f('/window-alias');",
      '}',
      'export function useLocal(fetch: (input: string) => unknown) {',
      '  const f = fetch;',
      "  return f('/local-alias');",
      '}',
      '',
    ].join('\n'));
    const apiClientResult = await lintVirtual('src/shared/apiClient.ts', [
      "export function request() {",
      "  window.fetch('/allowed-window');",
      "  globalThis.fetch('/allowed-globalThis');",
      "  self.fetch('/allowed-self');",
      '  const token = window.document.cookie;',
      "  globalThis.document.cookie = 'session=value';",
      '  return token;',
      '}',
      '',
    ].join('\n'));

    expect(aliasResult.exitCode).toBe(1);
    expect(aliasResult.stdout.match(/direct global fetch is prohibited/g)).toHaveLength(3);
    expect(aliasResult.stdout).not.toContain('local-alias');
    expect(aliasResult.stderr).toBe('');
    expect(apiClientResult.exitCode).toBe(0);
    expect(apiClientResult.stdout).toBe('');
    expect(apiClientResult.stderr).toBe('');
  }, 30_000);
});
