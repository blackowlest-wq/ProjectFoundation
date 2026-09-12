import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';
import { analyzeSuppressionDirectives, runFrontendLint } from '../../eslint-rules/index.mjs';

const frontendRoot = process.cwd();

async function assertActualSourceIsClean(relativePath: string) {
  const absolutePath = resolve(frontendRoot, relativePath);
  const source = readFileSync(absolutePath, 'utf8');
  expect(source).toMatch(/eslint-disable-next-line\s+react-hooks\/exhaustive-deps/);
  expect(source).toMatch(/\/\/\s*Why not:\s*\S/);
  expect(analyzeSuppressionDirectives(source, relativePath)).toEqual([]);

  const result = await runFrontendLint({ cwd: frontendRoot, args: [relativePath] });
  expect(result.exitCode).toBe(0);
  expect(result.stdout).toBe('');
  expect(result.stderr).toBe('');
}

describe('A suppression baseline integration seam', () => {
  it('TC-PFL-080 reads the actual MonthlySummaryPage source', async () => {
    await assertActualSourceIsClean('src/monthlySummary/MonthlySummaryPage.tsx');
  }, 30_000);

  it('TC-PFL-081 reads the actual DailyReportPendingApprovalList source', async () => {
    await assertActualSourceIsClean('src/dailyReport/DailyReportPendingApprovalList.tsx');
  }, 30_000);
});
