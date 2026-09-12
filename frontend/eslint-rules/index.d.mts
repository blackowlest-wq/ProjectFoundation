import type { Rule } from 'eslint';

export type FrontendVirtualFile = {
  path: string;
  content: string;
};

export type FrontendLintOptions = {
  cwd?: string;
  args?: readonly string[];
  virtualFiles?: readonly FrontendVirtualFile[];
};

export type FrontendDiagnostic = {
  policyId: string;
  engineRuleId: string;
  severity: 'Error' | 'Warning';
  path: string;
  line: number | null;
  column: number | null;
  rule: string | null;
  message: string;
  code: string | null;
};

export type FrontendLintResult = {
  exitCode: 0 | 1 | 2;
  stdout: string;
  stderr: string;
};

export const noDirectTransportAccess: Rule.RuleModule;
export const moduleMatrix: Rule.RuleModule;
export function analyzeSuppressionDirectives(
  sourceText: string,
  filePath?: string,
): FrontendDiagnostic[];
export function runFrontendLint(options?: FrontendLintOptions): Promise<FrontendLintResult>;
declare const plugin: { rules: Record<string, Rule.RuleModule> };
export default plugin;
