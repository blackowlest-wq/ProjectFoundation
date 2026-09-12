import { readFile } from 'node:fs/promises';
import { relative, resolve } from 'node:path';
import { ESLint, SourceCode } from 'eslint';
import tseslint from 'typescript-eslint';

const POLICIES = Object.freeze({
  transport: Object.freeze({
    policyId: 'PF-FE-001',
    engineRuleId: 'frontend/no-direct-transport-access',
  }),
  moduleMatrix: Object.freeze({
    policyId: 'PF-FE-002',
    engineRuleId: 'frontend/module-matrix-and-target-coverage',
  }),
  suppression: Object.freeze({
    policyId: 'PF-SUPPRESS-001',
    engineRuleId: 'frontend/suppression-reason',
  }),
});

const DEFAULT_LINT_TARGETS = Object.freeze([
  'src/**/*.{ts,tsx}',
  'test/**/*.{ts,tsx}',
  'e2e/**/*.{ts,tsx}',
  'eslint-rules/**/*.{mjs,mts}',
  'scripts/frontend-lint.mjs',
  'scripts/lcov-to-html.mjs',
  'vite.config.ts',
  'playwright*.config.ts',
]);

const TRANSPORT_MESSAGES = Object.freeze({
  directFetch: 'direct global fetch is prohibited',
  cookieRead: 'document.cookie read is prohibited outside apiClient',
  cookieWrite: 'document.cookie write is prohibited outside apiClient',
  csrfRead: 'CSRF token read is prohibited outside apiClient',
  csrfHeader: 'CSRF header construction is prohibited outside apiClient',
});

const MODULE_MESSAGES = Object.freeze({
  sharedFeature: 'shared module cannot import feature module',
  sharedApp: 'shared module cannot import app module',
  sharedAuth: 'shared module cannot import auth module',
  featureApp: 'feature module cannot import app module',
  featureFeature: 'feature module cannot import another feature module',
  featureAuth: 'feature may import auth/types only as type-only',
  authApp: 'auth module cannot import app module',
  authFeature: 'auth module cannot import feature module',
});

const SUPPRESSION_MESSAGES = Object.freeze({
  missingRule: 'explicit ESLint rule ID is required',
  wildcard: 'wildcard ESLint rule ID is prohibited',
  missingReason: 'immediate preceding Why not is required',
  emptyReason: 'Why not reason must be non-empty',
  nonImmediateReason: 'Why not must be immediately preceding',
});

/**
 * Normalise both RuleTester virtual names and Windows absolute names to one
 * separator convention.  The rule deliberately does not depend on the host
 * path module because RuleTester may provide a filename for another host.
 */
function normaliseFilename(filename) {
  return String(filename ?? '').replaceAll('\\', '/');
}

/** Return whether a path contains the requested repository-relative suffix. */
function hasPathSuffix(filename, suffix) {
  const normalised = normaliseFilename(filename);
  return normalised === suffix || normalised.endsWith(`/${suffix}`);
}

/** Return whether a filename belongs to production Frontend source. */
function isProductionSource(filename) {
  const normalised = normaliseFilename(filename);
  return /(?:^|\/)frontend\/src\/[^/]+(?:\/[^/]*)*\.(?:ts|tsx)$/.test(normalised);
}

/** Return whether a reference is locally declared rather than global. */
function isShadowedReference(sourceCode, node) {
  if (!sourceCode.getScope) {
    return false;
  }

  let scope = sourceCode.getScope(node);
  while (scope) {
    const variable = scope.set?.get(node.name);
    if (variable?.defs?.length) {
      return true;
    }
    scope = scope.upper;
  }
  return false;
}

/** Read an Identifier or string-literal property name from ESTree nodes. */
function propertyName(node) {
  if (!node) {
    return undefined;
  }
  if (node.type === 'Identifier') {
    return node.name;
  }
  if (node.type === 'Literal' && typeof node.value === 'string') {
    return node.value;
  }
  return undefined;
}

/** Return whether an identifier denotes an unshadowed browser global object. */
function isGlobalNamespaceIdentifier(node, sourceCode) {
  return node?.type === 'Identifier'
    && ['window', 'globalThis', 'self'].includes(node.name)
    && !isShadowedReference(sourceCode, node);
}

/** Return whether a member is a property on an unshadowed browser global object. */
function isGlobalNamespaceMember(node, name, sourceCode) {
  return node?.type === 'MemberExpression'
    && isGlobalNamespaceIdentifier(node.object, sourceCode)
    && propertyName(node.property) === name;
}

/** Resolve the lexical variable referenced by an identifier. */
function resolveVariable(sourceCode, node) {
  if (node?.type !== 'Identifier' || !sourceCode.getScope) {
    return undefined;
  }

  let scope = sourceCode.getScope(node);
  while (scope) {
    const variable = scope.set?.get(node.name);
    if (variable) {
      return variable;
    }
    scope = scope.upper;
  }
  return undefined;
}

/** Return whether a node is the global fetch reference or a qualified equivalent. */
function isGlobalFetchReference(node, sourceCode) {
  if (node?.type === 'Identifier') {
    return node.name === 'fetch' && !isShadowedReference(sourceCode, node);
  }
  return isGlobalNamespaceMember(node, 'fetch', sourceCode);
}

/** Return whether a node is the global document object or a qualified equivalent. */
function isGlobalDocumentReference(node, sourceCode) {
  if (node?.type === 'Identifier') {
    return node.name === 'document' && !isShadowedReference(sourceCode, node);
  }
  return isGlobalNamespaceMember(node, 'document', sourceCode);
}

/** Resolve a statically initialized const alias back to the global fetch reference. */
function isFetchReference(node, sourceCode, aliases, resolving = new Set()) {
  if (isGlobalFetchReference(node, sourceCode)) {
    return true;
  }
  if (node?.type !== 'Identifier') {
    return false;
  }

  const variable = resolveVariable(sourceCode, node);
  if (!variable || !aliases.has(variable) || resolving.has(variable)) {
    return false;
  }
  resolving.add(variable);
  return isFetchReference(aliases.get(variable), sourceCode, aliases, resolving);
}

/** Return whether a text value describes a CSRF/XSRF header or token. */
function isCsrfName(value) {
  return typeof value === 'string' && /csrf|xsrf/i.test(value);
}

/** Return whether a member expression is specifically document.cookie. */
function isDocumentCookie(node, sourceCode) {
  return node.type === 'MemberExpression'
    && isGlobalDocumentReference(node.object, sourceCode)
    && propertyName(node.property) === 'cookie';
}

/** Return whether the member is on the left side of a cookie write. */
function isWriteTarget(node) {
  const parent = node.parent;
  return (parent?.type === 'AssignmentExpression' && parent.left === node)
    || (parent?.type === 'AssignmentPattern' && parent.left === node)
    || (parent?.type === 'UpdateExpression' && parent.argument === node);
}

/** Return whether a cookie read is being assigned to a CSRF-named value. */
function isCsrfRead(node) {
  const parent = node.parent;
  if (parent?.type === 'VariableDeclarator' && parent.init === node) {
    return containsCsrfName(parent.id);
  }
  if (parent?.type === 'AssignmentExpression' && parent.right === node) {
    return containsCsrfName(parent.left);
  }
  return false;
}

/** Recursively inspect a destructuring target for a CSRF/XSRF name. */
function containsCsrfName(node) {
  if (!node) {
    return false;
  }
  if (node.type === 'Identifier') {
    return isCsrfName(node.name);
  }
  if (node.type === 'AssignmentPattern') {
    return containsCsrfName(node.left);
  }
  if (node.type === 'RestElement') {
    return containsCsrfName(node.argument);
  }
  if (node.type === 'ObjectPattern') {
    return node.properties.some((property) => containsCsrfName(property.value ?? property.argument));
  }
  if (node.type === 'ArrayPattern') {
    return node.elements.some((element) => containsCsrfName(element));
  }
  return false;
}

/** Return the top-level statement used as a stable diagnostic anchor. */
function statementAnchor(node, sourceCode) {
  let current = node;
  while (current.parent && current.parent.type !== 'Program') {
    current = current.parent;
  }
  return current ?? sourceCode.ast;
}

/** Resolve a relative import into a repository-style path. */
function resolveImportPath(importer, importValue) {
  const normalisedImporter = normaliseFilename(importer);
  const source = String(importValue ?? '').replaceAll('\\', '/');
  if (source.startsWith('.')) {
    const importerParts = normalisedImporter.split('/');
    importerParts.pop();
    for (const part of source.split('/')) {
      if (!part || part === '.') {
        continue;
      }
      if (part === '..') {
        importerParts.pop();
      } else {
        importerParts.push(part);
      }
    }
    return importerParts.join('/');
  }
  return source
    .replace(/^@\//, 'frontend/src/')
    .replace(/^~\//, 'frontend/src/');
}

/** Classify a repository path according to the Frontend module matrix. */
function classifyModule(filename) {
  const normalised = normaliseFilename(filename);
  const sourceMarker = normalised.lastIndexOf('/frontend/src/');
  const sourcePath = sourceMarker >= 0
    ? normalised.slice(sourceMarker + '/frontend/src/'.length)
    : normalised.startsWith('frontend/src/')
      ? normalised.slice('frontend/src/'.length)
      : undefined;
  if (!sourcePath) {
    return undefined;
  }

  // Files directly under src (for example the Vite entry point) are not a
  // module layer.  Only shared/app/auth directories and feature directories
  // participate in the dependency matrix.
  if (!sourcePath.includes('/')) {
    return undefined;
  }

  const [topLevel] = sourcePath.split('/');
  if (topLevel === 'shared') {
    return { kind: 'shared', name: 'shared' };
  }
  if (topLevel === 'app') {
    return { kind: 'app', name: 'app' };
  }
  if (topLevel === 'auth') {
    return { kind: 'auth', name: 'auth' };
  }
  return { kind: 'feature', name: topLevel };
}

/** Classify an import target, including the importer's relative directory. */
function classifyImportTarget(importer, importValue) {
  const source = String(importValue ?? '').replaceAll('\\', '/');
  const targetPath = resolveImportPath(importer, source);
  let target = classifyModule(targetPath);
  if (!target && (source.startsWith('.') || source.startsWith('@/') || source.startsWith('~/'))) {
    // RuleTester fixtures intentionally use virtual paths that are not backed
    // by a real directory.  Classify the first non-relative segment as the
    // module name so the matrix remains independent of the host filesystem.
    const [moduleName] = source.split('/').filter((part) => part && part !== '.' && part !== '..');
    if (moduleName === 'shared' || moduleName === 'app' || moduleName === 'auth') {
      target = { kind: moduleName, name: moduleName };
    } else if (moduleName) {
      target = { kind: 'feature', name: moduleName };
    }
  }
  if (!target) {
    return undefined;
  }
  return {
    ...target,
    isTypes: /(?:^|\/)types(?:\.[^/]*)?$/.test(normaliseFilename(targetPath)),
  };
}

/** Return whether every import specifier is type-only. */
function isTypeOnlyImport(node) {
  if (node.importKind === 'type') {
    return true;
  }
  return node.specifiers.length > 0
    && node.specifiers.every((specifier) => specifier.importKind === 'type');
}

/** Return whether an export edge contains only type exports. */
function isTypeOnlyExport(node) {
  if (node.exportKind === 'type') {
    return true;
  }
  return Array.isArray(node.specifiers)
    && node.specifiers.length > 0
    && node.specifiers.every((specifier) => specifier.exportKind === 'type');
}

/** Read a statically known string from an import/export source node. */
function staticDependencyValue(node) {
  if (node?.type === 'Literal' && typeof node.value === 'string') {
    return node.value;
  }
  if (node?.type === 'TemplateLiteral' && node.expressions.length === 0) {
    return node.quasis[0]?.value?.cooked ?? node.quasis[0]?.value?.raw;
  }
  return undefined;
}

/** Create the PF-FE-002 violation message for a matrix edge. */
function moduleViolation(from, to, typeOnly) {
  if (from.kind === 'shared' && to.kind === 'feature') {
    return MODULE_MESSAGES.sharedFeature;
  }
  if (from.kind === 'shared' && to.kind === 'app') {
    return MODULE_MESSAGES.sharedApp;
  }
  if (from.kind === 'shared' && to.kind === 'auth') {
    return MODULE_MESSAGES.sharedAuth;
  }
  if (from.kind === 'feature' && to.kind === 'app') {
    return MODULE_MESSAGES.featureApp;
  }
  if (from.kind === 'feature' && to.kind === 'feature' && from.name !== to.name) {
    return MODULE_MESSAGES.featureFeature;
  }
  if (from.kind === 'feature' && to.kind === 'auth' && !(typeOnly && to.isTypes)) {
    return MODULE_MESSAGES.featureAuth;
  }
  if (from.kind === 'auth' && to.kind === 'feature') {
    return MODULE_MESSAGES.authFeature;
  }
  if (from.kind === 'auth' && to.kind === 'app') {
    return MODULE_MESSAGES.authApp;
  }
  return undefined;
}

/** ESLint rule for the single Frontend transport boundary. */
export const noDirectTransportAccess = {
  meta: {
    type: 'problem',
    docs: { description: 'Keep transport and CSRF access in shared/apiClient.' },
    schema: [],
    messages: {
      directFetch: TRANSPORT_MESSAGES.directFetch,
      cookieRead: TRANSPORT_MESSAGES.cookieRead,
      cookieWrite: TRANSPORT_MESSAGES.cookieWrite,
      csrfRead: TRANSPORT_MESSAGES.csrfRead,
      csrfHeader: TRANSPORT_MESSAGES.csrfHeader,
    },
  },
  create(context) {
    const filename = context.filename ?? context.getFilename?.() ?? '<text>';
    if (!isProductionSource(filename) || hasPathSuffix(filename, 'frontend/src/shared/apiClient.ts')) {
      return {};
    }

    const sourceCode = context.sourceCode ?? context.getSourceCode();
    const fetchAliases = new Map();
    const fetchCalls = [];
    const report = (node, messageId) => context.report({
      node: statementAnchor(node, sourceCode),
      messageId,
    });

    return {
      VariableDeclarator(node) {
        if (node.parent?.type !== 'VariableDeclaration'
          || node.parent.kind !== 'const'
          || node.id.type !== 'Identifier'
          || !node.init) {
          return;
        }

        const [variable] = sourceCode.getDeclaredVariables?.(node) ?? [];
        if (variable) {
          fetchAliases.set(variable, node.init);
        }
      },
      CallExpression(node) {
        fetchCalls.push(node);

        if (node.callee.type === 'MemberExpression'
          && propertyName(node.callee.property) === 'set'
          && isCsrfName(propertyName(node.arguments[0]))) {
          report(node, 'csrfHeader');
        }
      },
      MemberExpression(node) {
        if (isDocumentCookie(node, sourceCode)) {
          if (isWriteTarget(node)) {
            report(node, 'cookieWrite');
          } else if (isCsrfRead(node)) {
            report(node, 'csrfRead');
          } else {
            report(node, 'cookieRead');
          }
          return;
        }

        if (isCsrfName(propertyName(node.property))
          && (isWriteTarget(node) || (node.parent?.type === 'CallExpression' && node.parent.callee === node))) {
          report(node, 'csrfHeader');
        }
      },
      Property(node) {
        if (isCsrfName(propertyName(node.key))) {
          report(node, 'csrfHeader');
        }
      },
      'Program:exit'() {
        for (const node of fetchCalls) {
          if (isFetchReference(node.callee, sourceCode, fetchAliases)) {
            report(node, 'directFetch');
          }
        }
      },
    };
  },
};

/** ESLint rule for the Frontend module dependency matrix. */
export const moduleMatrix = {
  meta: {
    type: 'problem',
    docs: { description: 'Enforce the Frontend module dependency matrix.' },
    schema: [],
    messages: {
      sharedFeature: MODULE_MESSAGES.sharedFeature,
      sharedApp: MODULE_MESSAGES.sharedApp,
      sharedAuth: MODULE_MESSAGES.sharedAuth,
      featureApp: MODULE_MESSAGES.featureApp,
      featureFeature: MODULE_MESSAGES.featureFeature,
      featureAuth: MODULE_MESSAGES.featureAuth,
      authApp: MODULE_MESSAGES.authApp,
      authFeature: MODULE_MESSAGES.authFeature,
    },
  },
  create(context) {
    const filename = context.filename ?? context.getFilename?.() ?? '<text>';
    const from = classifyModule(filename);
    if (!from || !isProductionSource(filename)) {
      return {};
    }

    const sourceCode = context.sourceCode ?? context.getSourceCode();
    const reportDependency = (node, sourceNode, typeOnly = false) => {
      const source = staticDependencyValue(sourceNode);
      if (source === undefined) {
        return;
      }
      const to = classifyImportTarget(filename, source);
      if (!to) {
        return;
      }
      const message = moduleViolation(from, to, typeOnly);
      if (!message) {
        return;
      }
      const messageId = Object.entries(MODULE_MESSAGES).find(([, value]) => value === message)?.[0];
      if (messageId) {
        context.report({ node: statementAnchor(node, sourceCode), messageId });
      }
    };

    return {
      ImportDeclaration(node) {
        reportDependency(node, node.source, isTypeOnlyImport(node));
      },
      ExportNamedDeclaration(node) {
        if (node.source) {
          reportDependency(node, node.source, isTypeOnlyExport(node));
        }
      },
      ExportAllDeclaration(node) {
        if (node.source) {
          reportDependency(node, node.source, isTypeOnlyExport(node));
        }
      },
      ImportExpression(node) {
        reportDependency(node, node.source);
      },
    };
  },
};

/** Parse the rule IDs from one raw ESLint disable directive. */
function parseRuleIds(rest) {
  const withoutDescription = rest.split(/\s+--\s+/, 1)[0].trim();
  if (!withoutDescription) {
    return [];
  }
  return withoutDescription
    .split(',')
    .map((ruleId) => ruleId.trim())
    .filter(Boolean);
}

/** Return a valid non-empty Why-not comment for one physical source line. */
function parseWhyNot(line) {
  const match = String(line ?? '').match(/^\s*\/\/\s*Why not:\s*(.*?)\s*$/);
  if (!match) {
    return undefined;
  }
  return match[1].trim();
}

/** Find the suppression reason failure for a directive's physical line. */
function suppressionReason(lines, directiveLine) {
  const directiveIndex = directiveLine - 1;
  const previousLine = lines[directiveIndex - 1];
  const previousReason = parseWhyNot(previousLine);
  if (previousReason !== undefined) {
    return previousReason.length > 0 ? undefined : SUPPRESSION_MESSAGES.emptyReason;
  }

  const hasEarlierReason = lines
    .slice(0, Math.max(0, directiveIndex - 1))
    .some((line) => {
      const reason = parseWhyNot(line);
      return reason !== undefined && reason.length > 0;
    });
  return hasEarlierReason
    ? SUPPRESSION_MESSAGES.nonImmediateReason
    : SUPPRESSION_MESSAGES.missingReason;
}

/** Parse ESLint suppression directives from an ESTree comment token. */
function parseSuppressionComment(comment) {
  const value = String(comment?.value ?? '');
  const match = value.match(/^\s*eslint-disable(?:-next-line|-line)?\b([\s\S]*)$/);
  if (!match) {
    return undefined;
  }

  const directiveOffset = value.indexOf(match[0].trimStart());
  const leadingText = directiveOffset >= 0 ? value.slice(0, directiveOffset) : '';
  const lineOffset = (leadingText.match(/\r?\n/g) ?? []).length;
  return {
    rest: match[1],
    line: (comment.loc?.start?.line ?? 1) + lineOffset,
  };
}

/** Use the configured TypeScript parser and ESLint SourceCode to get comments only. */
function sourceComments(sourceText, filePath) {
  try {
    const parsed = tseslint.parser.parseForESLint(String(sourceText ?? ''), {
      ecmaVersion: 'latest',
      sourceType: 'module',
      ...(filePath && filePath !== '<text>' ? { filePath: String(filePath) } : {}),
      loc: true,
      range: true,
      tokens: true,
      comment: true,
    });
    return new SourceCode(String(sourceText ?? ''), parsed.ast).getAllComments();
  } catch {
    // A parser failure is reported by the public lint path before this policy
    // runs.  Returning no comment tokens here keeps the analyzer from falling
    // back to a string regex that could report text inside a literal.
    return [];
  }
}

/**
 * Inspect raw source lines independently of ESLint's suppression processing.
 * This keeps an invalid directive from hiding the diagnostic that explains it.
 */
export function analyzeSuppressionDirectives(sourceText, filePath = '<text>') {
  const text = String(sourceText ?? '');
  const lines = text.split(/\r?\n/);
  const diagnostics = [];

  for (const comment of sourceComments(text, filePath)) {
    const directive = parseSuppressionComment(comment);
    if (!directive) {
      continue;
    }

    const ruleIds = parseRuleIds(directive.rest);
    let message;
    if (ruleIds.length === 0) {
      message = SUPPRESSION_MESSAGES.missingRule;
    } else if (ruleIds.includes('*')) {
      message = SUPPRESSION_MESSAGES.wildcard;
    } else {
      message = suppressionReason(lines, directive.line);
    }

    if (!message) {
      continue;
    }

    diagnostics.push({
      ...POLICIES.suppression,
      severity: 'Error',
      path: filePath,
      line: directive.line,
      column: 1,
      rule: POLICIES.suppression.engineRuleId,
      message,
      code: 'SUPPRESSION_REASON',
    });
  }

  return diagnostics;
}

/** Convert an absolute ESLint path into the repository-relative contract path. */
function repositoryPath(filePath, cwd) {
  const normalised = normaliseFilename(filePath);
  const frontendMarker = normalised.lastIndexOf('/frontend/');
  if (frontendMarker >= 0) {
    return normalised.slice(frontendMarker + 1);
  }

  const relativePath = normaliseFilename(relative(cwd, filePath));
  return relativePath.startsWith('../') ? relativePath : `frontend/${relativePath}`;
}

/** Map an ESLint rule ID to the public policy metadata. */
function policyForRule(ruleId) {
  if (ruleId?.endsWith('/no-direct-transport-access')) {
    return POLICIES.transport;
  }
  if (ruleId?.endsWith('/module-matrix')) {
    return POLICIES.moduleMatrix;
  }
  return undefined;
}

/** Convert an ESLint result message into the public diagnostic shape. */
function toDiagnostic(message, filePath, cwd) {
  const policy = policyForRule(message.ruleId);
  return {
    ...(policy ?? {
      policyId: 'ESLint',
      engineRuleId: message.ruleId ?? 'eslint',
    }),
    severity: message.severity === 1 ? 'Warning' : 'Error',
    path: repositoryPath(filePath, cwd),
    line: Number.isInteger(message.line) ? message.line : null,
    column: Number.isInteger(message.column) ? message.column : null,
    rule: message.ruleId ?? null,
    message: String(message.message ?? '').replace(/\r?\n/g, ' '),
    code: message.messageId ?? null,
  };
}

/** Compare nullable diagnostic positions according to the fixed A/B sort. */
function compareNullable(left, right) {
  if (left === right) {
    return 0;
  }
  if (left === null || left === undefined) {
    return 1;
  }
  if (right === null || right === undefined) {
    return -1;
  }
  return left < right ? -1 : 1;
}

/** Sort diagnostics deterministically before rendering bytes. */
function compareDiagnostics(left, right) {
  for (const [leftValue, rightValue] of [
    [left.policyId, right.policyId],
    [left.path, right.path],
  ]) {
    if (leftValue !== rightValue) {
      return leftValue < rightValue ? -1 : 1;
    }
  }
  const lineResult = compareNullable(left.line, right.line);
  if (lineResult !== 0) {
    return lineResult;
  }
  const columnResult = compareNullable(left.column, right.column);
  if (columnResult !== 0) {
    return columnResult;
  }
  if (left.message !== right.message) {
    return left.message < right.message ? -1 : 1;
  }
  return 0;
}

/** Render one diagnostic using the fixed A text signature. */
function toTextDiagnostic(diagnostic) {
  const line = diagnostic.line ?? '-';
  const column = diagnostic.column ?? '-';
  return `${diagnostic.policyId}|${diagnostic.severity}|${diagnostic.path}:${line}:${column}|${diagnostic.message}`;
}

/** Resolve a test-only virtual file without touching the repository tree. */
function normaliseVirtualFiles(cwd, virtualFiles) {
  if (!Array.isArray(virtualFiles)) {
    return [];
  }

  const files = new Map();
  for (const entry of virtualFiles) {
    if (!entry || typeof entry.path !== 'string' || entry.path.length === 0) {
      continue;
    }
    const filePath = resolve(cwd, entry.path);
    files.set(normaliseFilename(filePath), {
      filePath,
      sourceText: String(entry.content ?? ''),
    });
  }
  return [...files.values()].sort((left, right) => left.filePath.localeCompare(right.filePath));
}

/** Select virtual inputs with the same narrow path-pattern contract as A. */
function selectVirtualTargets(cwd, filePatterns, virtualFiles) {
  if (filePatterns.length === 0) {
    return virtualFiles;
  }

  return virtualFiles.filter(({ filePath }) => filePatterns.some((pattern) => {
    const value = String(pattern);
    const relativePath = normaliseFilename(relative(cwd, filePath));
    if (value.includes('?') || value.includes('*') || value.includes('[') || value.includes(']')) {
      const escaped = value.replace(/[.+^${}()|\\]/g, '\\$&').replace(/\*/g, '.*').replace(/\?/g, '.');
      return new RegExp(`^${escaped}$`, 'i').test(relativePath);
    }
    return normaliseFilename(resolve(cwd, value)) === normaliseFilename(filePath);
  }));
}

/** Render a sorted diagnostic set into the fixed stdout contract. */
function renderDiagnostics(diagnostics) {
  diagnostics.sort(compareDiagnostics);
  return diagnostics.length > 0
    ? `${diagnostics.map(toTextDiagnostic).join('\n')}\n`
    : '';
}

/** Parse the small CLI subset used by the public frontend lint wrapper. */
function parseLintArguments(args) {
  const filePatterns = [];
  let configFile;
  const values = Array.isArray(args) ? args : [];
  for (let index = 0; index < values.length; index += 1) {
    const argument = String(values[index]);
    if (argument === '--') {
      continue;
    }
    if (argument === '--config') {
      configFile = values[index + 1];
      index += 1;
      continue;
    }
    if (argument.startsWith('--config=')) {
      configFile = argument.slice('--config='.length);
      continue;
    }
    if (argument === '--ext' || argument === '--ignore-pattern') {
      index += 1;
      continue;
    }
    if (argument.startsWith('-')) {
      continue;
    }
    filePatterns.push(argument);
  }
  return { filePatterns, configFile };
}

/** Return a fixed, redacted runtime error without exposing config or secrets. */
function runtimeFailure(error, configFile) {
  const errorName = String(error?.name ?? '');
  const errorMessage = String(error?.message ?? '');
  const isConfigFailure = Boolean(configFile)
    || /config|configuration|parsing|parse/i.test(`${errorName} ${errorMessage}`);
  return {
    exitCode: 2,
    stdout: '',
    stderr: `${isConfigFailure ? 'ESLint configuration parse failed' : 'ESLint runtime failed'}\n`,
  };
}

/** Convert ESLint results and the raw suppression policy into A diagnostics. */
async function diagnosticsFromResults(results, cwd, virtualSources = new Map()) {
  const diagnostics = [];
  for (const result of results) {
    if (result.messages.some((message) => message.fatal)) {
      return { parseFailed: true, diagnostics: [] };
    }

    for (const message of result.messages) {
      diagnostics.push(toDiagnostic(message, result.filePath, cwd));
    }

    const sourceText = virtualSources.get(normaliseFilename(result.filePath))
      ?? await readFile(result.filePath, 'utf8');
    for (const suppression of analyzeSuppressionDirectives(sourceText, result.filePath)) {
      diagnostics.push({
        ...suppression,
        path: repositoryPath(result.filePath, cwd),
      });
    }
  }
  return { parseFailed: false, diagnostics };
}

/**
 * Execute the A frontend lint contract through ESLint's Node API.  Exit 0 is
 * silent, exit 1 reports deterministic policy lines, and exit 2 is reserved
 * for configuration, parsing, or runtime failures.
 */
export async function runFrontendLint(options = {}) {
  const cwd = resolve(options.cwd ?? process.cwd());
  const { filePatterns, configFile } = parseLintArguments(options.args);
  const virtualFiles = normaliseVirtualFiles(cwd, options.virtualFiles);
  const eslintOptions = {
    cwd,
    errorOnUnmatchedPattern: filePatterns.length > 0,
    warnIgnored: false,
    ...(configFile ? { overrideConfigFile: resolve(cwd, String(configFile)) } : {}),
  };

  try {
    const eslint = new ESLint(eslintOptions);
    let results;
    let virtualSources = new Map();
    if (virtualFiles.length > 0) {
      const selectedVirtualFiles = selectVirtualTargets(cwd, filePatterns, virtualFiles);
      virtualSources = new Map(selectedVirtualFiles.map(({ filePath, sourceText }) => [
        normaliseFilename(filePath),
        sourceText,
      ]));
      results = [];
      for (const { filePath, sourceText } of selectedVirtualFiles) {
        results.push(...await eslint.lintText(sourceText, { filePath }));
      }
    } else {
      results = await eslint.lintFiles(filePatterns.length > 0 ? filePatterns : DEFAULT_LINT_TARGETS);
    }

    const { parseFailed, diagnostics } = await diagnosticsFromResults(results, cwd, virtualSources);
    if (parseFailed) {
      return {
        exitCode: 2,
        stdout: '',
        stderr: 'ESLint parse failed\n',
      };
    }

    return {
      exitCode: diagnostics.length > 0 ? 1 : 0,
      stdout: renderDiagnostics(diagnostics),
      stderr: '',
    };
  } catch (error) {
    return runtimeFailure(error, configFile);
  }
}

export default {
  rules: {
    'no-direct-transport-access': noDirectTransportAccess,
    'module-matrix': moduleMatrix,
  },
};
