import { describe, expect, test } from 'vitest';
import config from '../vite.config';

type CoverageConfig = {
  clean?: boolean;
  include?: string[];
  reporter?: string[];
  reportsDirectory?: string;
  reportOnFailure?: boolean;
  thresholds?: { branches?: number; functions?: number; lines?: number; statements?: number };
};

const coverage = (config.test as { coverage?: CoverageConfig } | undefined)?.coverage;

describe('coverage quality gate configuration', () => {
  test('requires global 85 percent coverage and reviewable reports', () => {
    expect(coverage).toMatchObject({
      clean: true,
      include: ['src/**/*.{ts,tsx}'],
      reporter: ['text', 'text-summary', 'html', 'json-summary', 'lcov'],
      reportsDirectory: 'coverage',
      reportOnFailure: true,
      thresholds: { branches: 85, functions: 85, lines: 85, statements: 85 },
    });
  });
});
