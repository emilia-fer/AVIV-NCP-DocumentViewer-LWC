// scripts/generateCoverageMd.js
const fs = require('fs');
const path = require('path');

const root = path.join(__dirname, '..');
const coverageDir = path.join(root, 'coverage');
const jestSummaryPath = path.join(coverageDir, 'coverage-summary.json');
const apexDir = path.join(coverageDir, 'apex');
const mdOut = path.join(root, 'docs', 'code-coverage.md');

function fail(msg) {
  console.error(msg);
  process.exit(1);
}

if (!fs.existsSync(jestSummaryPath)) {
  fail('Coverage summary not found. Run tests with coverage first.');
}

const jestSummary = JSON.parse(fs.readFileSync(jestSummaryPath, 'utf8'));
const overallPct =
  parseFloat(
    jestSummary.total?.statements?.pct ?? jestSummary.total?.lines?.pct ?? 0
  ) || 0;

/* ---------- find Apex coverage ---------- */
function findFiles(dir, names) {
  const out = [];
  if (!fs.existsSync(dir)) return out;
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, entry.name);
    if (entry.isDirectory()) out.push(...findFiles(p, names));
    else if (names.includes(entry.name)) out.push(p);
  }
  return out;
}

function extractApexCoverages(obj) {
  if (!obj || typeof obj !== 'object') return [];
  const results = [];

  const arrays = [];
  if (Array.isArray(obj)) arrays.push(obj);
  if (Array.isArray(obj.codecoverage)) arrays.push(obj.codecoverage);
  if (Array.isArray(obj.coverage)) arrays.push(obj.coverage);
  if (Array.isArray(obj.codeCoverage)) arrays.push(obj.codeCoverage);

  for (const arr of arrays) {
    for (const c of arr) {
      const name =
        c.name ||
        c.apexClassOrTriggerName ||
        c.ApexClassOrTriggerName ||
        c.apexClassName ||
        c.className;
      if (!name) continue;

      const pct =
        (c.percentage !== undefined && parseFloat(c.percentage)) ||
        (c.coveredPercent !== undefined && parseFloat(c.coveredPercent)) ||
        (c.NumLocationsCovered !== undefined && c.NumLocations !== undefined
          ? (Number(c.NumLocationsCovered) / Number(c.NumLocations)) * 100
          : c.numLocationsCovered !== undefined && c.numLocations !== undefined
          ? (Number(c.numLocationsCovered) / Number(c.numLocations)) * 100
          : 0);

      results.push({ name, pct: Number(pct) || 0 });
    }
  }

  for (const v of Object.values(obj)) {
    if (v && typeof v === 'object') results.push(...extractApexCoverages(v));
  }

  const byName = new Map();
  for (const r of results) {
    const current = byName.get(r.name);
    if (!current || r.pct > current.pct) byName.set(r.name, r);
  }
  return Array.from(byName.values()).sort((a, b) => a.name.localeCompare(b.name));
}

let apexCoverages = [];
const apexFiles = [
  ...findFiles(apexDir, ['test-result-codecoverage.json']),
  ...findFiles(apexDir, ['test-result.json'])
];

for (const f of apexFiles) {
  try {
    const obj = JSON.parse(fs.readFileSync(f, 'utf8'));
    apexCoverages = extractApexCoverages(obj);
    if (apexCoverages.length) break;
  } catch (_) {
    // ignore and try next
  }
}

/* ---------- utility ---------- */
function coverageColor(pct) {
  if (pct >= 90) return 'brightgreen';
  if (pct >= 70) return 'yellow';
  if (pct >= 50) return 'orange';
  return 'red';
}

/* ---------- build markdown ---------- */
const overallColor = coverageColor(overallPct);
const overallLabel = `${overallPct.toFixed(2)}%`;
const overallBadge = `![Overall ${overallLabel}](https://img.shields.io/badge/-${encodeURIComponent(
  overallLabel
)}-${overallColor}?label=Overall%20Coverage)`;

const lines = [];
lines.push('# Code Coverage', '');
lines.push(`_Last Updated: ${new Date().toISOString()}_`, '');
lines.push('## Overall Coverage', '');
lines.push(overallBadge, '');
lines.push('## Coverage by Component', '');
lines.push('| Component | Coverage |');
lines.push('| --- | --- |');

Object.entries(jestSummary)
  .filter(([file]) => file !== 'total')
  .sort((a, b) => a[0].localeCompare(b[0]))
  .forEach(([file, stats]) => {
    const pct =
      parseFloat(stats.statements?.pct ?? stats.lines?.pct ?? 0) || 0;
    const name = path.basename(file);
    const color = coverageColor(pct);
    const label = pct.toFixed(2) + '%';
    const badge = `![${label}](https://img.shields.io/badge/-${encodeURIComponent(
      label
    )}-${color}?label=)`;
    lines.push(`| ${name} | ${badge} |`);
  });

if (apexCoverages.length) {
  lines.push('', '## Coverage by Class', '');
  lines.push('| Class | Coverage |');
  lines.push('| --- | --- |');
  apexCoverages.forEach(({ name, pct }) => {
    const color = coverageColor(pct);
    const label = (Number.isFinite(pct) ? pct : 0).toFixed(2) + '%';
    const badge = `![${label}](https://img.shields.io/badge/-${encodeURIComponent(
      label
    )}-${color}?label=)`;
    const display = name.endsWith('.cls') ? name : `${name}.cls`;
    lines.push(`| ${display} | ${badge} |`);
  });
}

lines.push('', '> Generated automatically. Run `npm run coverage:md` to refresh.', '');
lines.push('[Detailed HTML coverage report](../coverage/lcov-report/index.html)', '');

fs.mkdirSync(path.dirname(mdOut), { recursive: true });
fs.writeFileSync(mdOut, lines.join('\n') + '\n', 'utf8');
