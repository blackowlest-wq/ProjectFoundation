import { describe, expect, it } from 'vitest';
import { runFrontendLint } from '../../eslint-rules/index.mjs';

const frontendRoot = process.cwd();

type VirtualFile = { path: string; content: string };

async function lintVirtual(file: VirtualFile, args = [file.path]) {
  return runFrontendLint({ cwd: frontendRoot, args, virtualFiles: [file] });
}

describe('A frontend lint Node API integration seam', () => {
  it('uses the configured ESLint rules for virtual text without flagging comments or strings', async () => {
    const result = await lintVirtual({
      path: 'src/orders/comments-and-strings.ts',
      content: "// fetch('/api/orders')\nconst source = \"fetch('/api/orders')\";\nexport { source };\n",
    });

    expect(result.exitCode).toBe(0);
    expect(result.stdout).toBe('');
    expect(result.stderr).toBe('');
  }, 30_000);

  it('uses the AST custom rule for multiline fetch and import syntax', async () => {
    const fetchResult = await lintVirtual({
      path: 'src/orders/multiline-fetch.ts',
      content: "fetch(\n  '/api/orders',\n);\n",
    });
    const importResult = await lintVirtual({
      path: 'src/dailyReport/multiline-import.ts',
      content: "import {\n  MonthlySummaryPage,\n} from '../monthlySummary/MonthlySummaryPage';\n",
    });

    expect(fetchResult.exitCode).toBe(1);
    expect(fetchResult.stdout).toContain('PF-FE-001|Error|frontend/src/orders/multiline-fetch.ts:1:1|direct global fetch is prohibited');
    expect(importResult.exitCode).toBe(1);
    expect(importResult.stdout).toContain('PF-FE-002|Error|frontend/src/dailyReport/multiline-import.ts:1:1|feature module cannot import another feature module');
  }, 30_000);

  it('keeps the recommended and React Hooks rules in the public A path', async () => {
    const result = await lintVirtual({
      path: 'src/orders/existing-eslint-rules.ts',
      content: [
        'const unusedValue = 1;',
        'function useLocal() { return null; }',
        'useLocal();',
        'export {};',
        '',
      ].join('\n'),
    });

    expect(result.exitCode).toBe(1);
    expect(result.stdout).toContain("'unusedValue' is assigned a value but never used");
    expect(result.stdout).toContain('React Hook "useLocal" cannot be called at the top level');
    expect(result.stderr).toBe('');
  }, 30_000);

  it('maps a virtual parser failure to exit 2', async () => {
    const result = await lintVirtual({
      path: 'src/orders/parse-error.ts',
      content: 'const = ;\n',
    });

    expect(result.exitCode).toBe(2);
    expect(result.stdout).toBe('');
    expect(result.stderr).toBe('ESLint parse failed\n');
  }, 30_000);
});
