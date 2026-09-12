import { spawn } from 'node:child_process';
import { mkdtemp, mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { describe, expect, it } from 'vitest';

const frontendRoot = process.cwd();
const cliPath = resolve(frontendRoot, 'scripts/frontend-lint.mjs');
const lcovScriptPath = resolve(frontendRoot, 'scripts/lcov-to-html.mjs');
const projectRulesUrl = pathToFileURL(resolve(frontendRoot, 'eslint-rules/index.mjs')).href;

type ChildResult = { status: number | null; stdout: string; stderr: string };

function runChild(args: string[], cwd: string): Promise<ChildResult> {
  return new Promise((resolveResult, reject) => {
    const child = spawn(process.execPath, args, {
      cwd,
      env: { ...process.env },
    });
    let stdout = '';
    let stderr = '';
    child.stdout.on('data', (chunk: Buffer) => { stdout += chunk.toString(); });
    child.stderr.on('data', (chunk: Buffer) => { stderr += chunk.toString(); });
    child.on('error', reject);
    child.on('close', (status) => resolveResult({ status, stdout, stderr }));
  });
}

async function createFixture(source: string, configSource = validFixtureConfig()) {
  const fixtureParent = await mkdtemp(join(frontendRoot, '.frontend-lint-fixture-'));
  const fixtureRoot = join(fixtureParent, 'frontend');
  await mkdir(join(fixtureRoot, 'src/orders'), { recursive: true });
  await mkdir(join(fixtureRoot, 'scripts'), { recursive: true });
  await writeFile(join(fixtureRoot, 'eslint.config.mjs'), configSource, 'utf8');
  await writeFile(join(fixtureRoot, 'src/orders/orderApi.ts'), source, 'utf8');
  await writeFile(join(fixtureRoot, 'scripts/lcov-to-html.mjs'), await readFile(lcovScriptPath), 'utf8');
  return { fixtureParent, fixtureRoot };
}

function validFixtureConfig(): string {
  return `
import eslint from '@eslint/js';
import reactHooks from 'eslint-plugin-react-hooks';
import tseslint from 'typescript-eslint';
import projectLint from ${JSON.stringify(projectRulesUrl)};

export default tseslint.config(
  {
    ignores: ['dist/**', 'coverage/**', 'playwright-report/**', 'test-results/**', 'test/lint/fixtures/**'],
  },
  eslint.configs.recommended,
  ...tseslint.configs.recommended,
  {
    files: ['**/*.{ts,tsx}'],
    plugins: { 'react-hooks': reactHooks, frontend: projectLint },
    languageOptions: { globals: { process: 'readonly', console: 'readonly' } },
    rules: {
      'no-undef': 'off',
      'react-hooks/rules-of-hooks': 'error',
      'react-hooks/exhaustive-deps': 'error',
      'frontend/no-direct-transport-access': 'error',
      'frontend/module-matrix': 'error',
    },
  },
  { files: ['**/*.mjs'], languageOptions: { globals: { process: 'readonly', console: 'readonly' } } },
);
`;
}

const directFetchSignature = 'PF-FE-001|Error|frontend/src/orders/orderApi.ts:1:1|direct global fetch is prohibited';

describe('A frontend lint CLI', () => {
  it('TC-PFL-013 returns a clean, silent result', async () => {
    const fixture = await createFixture('export const orderCount = 0;\n');
    try {
      const result = await runChild([cliPath], fixture.fixtureRoot);
      expect(result.status).toBe(0);
      expect(result.stdout).toBe('');
      expect(result.stderr).toBe('');
    } finally {
      await rm(fixture.fixtureParent, { recursive: true, force: true });
    }
  }, 30_000);

  it('TC-PFL-014 emits the fixed violation signature', async () => {
    const fixture = await createFixture("fetch('/api/orders');\n");
    try {
      const result = await runChild([cliPath], fixture.fixtureRoot);
      expect(result.status).toBe(1);
      expect(result.stdout.trim()).toBe(directFetchSignature);
      expect(result.stderr).toBe('');
    } finally {
      await rm(fixture.fixtureParent, { recursive: true, force: true });
    }
  }, 30_000);

  it('TC-PFL-015 maps configuration failures to exit 2 without a stack trace', async () => {
    const fixture = await createFixture('export const orderCount = 0;\n', `
export default [{
  rules: { 'no-undef': 'error' }
];
const SECRET = 'SECRET_TC_PFL_015';
`);
    try {
      const result = await runChild([cliPath, '--config', 'eslint.config.mjs'], fixture.fixtureRoot);
      expect(result.status).toBe(2);
      expect(result.stdout).toBe('');
      expect(result.stderr).toContain('ESLint configuration parse failed');
      expect(result.stderr).not.toContain('SECRET_TC_PFL_015');
    } finally {
      await rm(fixture.fixtureParent, { recursive: true, force: true });
    }
  }, 30_000);

  it('TC-PFL-070 observes an intentional RED signature mismatch in a child process', async () => {
    const fixture = await createFixture("fetch('/api/orders');\n");
    const mismatchedSignature = `${directFetchSignature} (intentional RED mismatch)`;
    const redHarness = `
import { spawnSync } from 'node:child_process';
const result = spawnSync(process.execPath, [${JSON.stringify(cliPath)}], { encoding: 'utf8' });
const actual = result.stdout.trim();
const expected = ${JSON.stringify(mismatchedSignature)};
if (result.status !== 1) {
  throw new Error('lint child did not report the intended violation');
}
if (actual === expected) {
  process.exit(0);
}
process.stderr.write('RED mismatch\\n');
process.stderr.write('expected: ' + expected + '\\n');
process.stderr.write('actual: ' + actual + '\\n');
process.exit(1);
`;
    try {
      const result = await runChild(['--input-type=module', '-e', redHarness], fixture.fixtureRoot);
      expect(result.status).toBe(1);
      expect(result.stderr).toContain('RED mismatch');
      expect(result.stderr).toContain(`expected: ${mismatchedSignature}`);
      expect(result.stderr).toContain(`actual: ${directFetchSignature}`);
    } finally {
      await rm(fixture.fixtureParent, { recursive: true, force: true });
    }
  }, 30_000);

  it('TC-PFL-071 has exactly one discovery sentinel', () => {
    expect('TC-PFL-DISCOVERY-SENTINEL').toBe('TC-PFL-DISCOVERY-SENTINEL');
  });
});
