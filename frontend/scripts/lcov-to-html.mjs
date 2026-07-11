import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname } from 'node:path';

const [, , input = 'coverage/lcov.info', output = 'coverage/index.html'] = process.argv;

function pct(hit, total) {
  return total === 0 ? '100.00' : ((hit / total) * 100).toFixed(2);
}

function cssClass(value) {
  const n = Number(value);
  if (n >= 80) return 'good';
  if (n >= 60) return 'warn';
  return 'bad';
}

function escapeHtml(value) {
  return String(value)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');
}

const text = await readFile(input, 'utf8');
const records = [];
let current = null;

for (const line of text.split(/\r?\n/)) {
  if (line.startsWith('SF:')) {
    current = { file: line.slice(3), linesFound: 0, linesHit: 0, branchesFound: 0, branchesHit: 0, functionsFound: 0, functionsHit: 0 };
    records.push(current);
  } else if (current && line.startsWith('LF:')) {
    current.linesFound = Number(line.slice(3));
  } else if (current && line.startsWith('LH:')) {
    current.linesHit = Number(line.slice(3));
  } else if (current && line.startsWith('BRF:')) {
    current.branchesFound = Number(line.slice(4));
  } else if (current && line.startsWith('BRH:')) {
    current.branchesHit = Number(line.slice(4));
  } else if (current && line.startsWith('FNF:')) {
    current.functionsFound = Number(line.slice(4));
  } else if (current && line.startsWith('FNH:')) {
    current.functionsHit = Number(line.slice(4));
  }
}

const totals = records.reduce(
  (sum, item) => ({
    linesFound: sum.linesFound + item.linesFound,
    linesHit: sum.linesHit + item.linesHit,
    branchesFound: sum.branchesFound + item.branchesFound,
    branchesHit: sum.branchesHit + item.branchesHit,
    functionsFound: sum.functionsFound + item.functionsFound,
    functionsHit: sum.functionsHit + item.functionsHit,
  }),
  { linesFound: 0, linesHit: 0, branchesFound: 0, branchesHit: 0, functionsFound: 0, functionsHit: 0 },
);

const rows = records.map((item) => {
  const linePct = pct(item.linesHit, item.linesFound);
  const branchPct = pct(item.branchesHit, item.branchesFound);
  const functionPct = pct(item.functionsHit, item.functionsFound);
  return `<tr>
    <td>${escapeHtml(item.file)}</td>
    <td class="${cssClass(linePct)}">${linePct}%</td>
    <td>${item.linesHit}/${item.linesFound}</td>
    <td class="${cssClass(branchPct)}">${branchPct}%</td>
    <td>${item.branchesHit}/${item.branchesFound}</td>
    <td class="${cssClass(functionPct)}">${functionPct}%</td>
    <td>${item.functionsHit}/${item.functionsFound}</td>
  </tr>`;
}).join('\n');

const totalLinePct = pct(totals.linesHit, totals.linesFound);
const totalBranchPct = pct(totals.branchesHit, totals.branchesFound);
const totalFunctionPct = pct(totals.functionsHit, totals.functionsFound);

const html = `<!doctype html>
<html lang="ja">
<head>
  <meta charset="utf-8">
  <title>Frontend Coverage</title>
  <style>
    body { font-family: "Segoe UI", sans-serif; margin: 32px; color: #1f2937; }
    h1 { margin-bottom: 8px; }
    table { border-collapse: collapse; margin-top: 24px; min-width: 760px; }
    th, td { border: 1px solid #d1d5db; padding: 10px 12px; text-align: right; }
    th:first-child, td:first-child { text-align: left; }
    th { background: #f3f4f6; }
    tfoot td { font-weight: 700; background: #f9fafb; }
    .good { color: #047857; }
    .warn { color: #b45309; }
    .bad { color: #b91c1c; }
  </style>
</head>
<body>
  <h1>Frontend Coverage</h1>
  <p>Generated from ${escapeHtml(input)}</p>
  <table>
    <thead>
      <tr>
        <th>File</th>
        <th>Lines</th>
        <th>Line Hits</th>
        <th>Branches</th>
        <th>Branch Hits</th>
        <th>Functions</th>
        <th>Function Hits</th>
      </tr>
    </thead>
    <tbody>${rows}</tbody>
    <tfoot>
      <tr>
        <td>All files</td>
        <td class="${cssClass(totalLinePct)}">${totalLinePct}%</td>
        <td>${totals.linesHit}/${totals.linesFound}</td>
        <td class="${cssClass(totalBranchPct)}">${totalBranchPct}%</td>
        <td>${totals.branchesHit}/${totals.branchesFound}</td>
        <td class="${cssClass(totalFunctionPct)}">${totalFunctionPct}%</td>
        <td>${totals.functionsHit}/${totals.functionsFound}</td>
      </tr>
    </tfoot>
  </table>
</body>
</html>
`;

await mkdir(dirname(output), { recursive: true });
await writeFile(output, html, 'utf8');
console.log(`Coverage HTML written to ${output}`);
