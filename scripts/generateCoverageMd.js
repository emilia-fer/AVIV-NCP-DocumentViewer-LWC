// scripts/generateCoverageMd.js
const fs = require('fs');
const path = require('path');

const root = path.join(__dirname, '..');
const coverageDir = path.join(root, 'coverage');
const jestSummaryPath = path.join(coverageDir, 'coverage-summary.json');
const apexDir = path.join(coverageDir, 'apex');
const mdOut = path.join(root, 'docs', 'code-coverage.md');

function fail(msg) { console.error(msg); process.exit(1); }
if (!fs.existsSync(jestSummaryPath)) fail('Coverage summary not found. Run tests with coverage first.');

const jestSummary = JSON.parse(fs.readFileSync(jestSummaryPath, 'utf8'));

// ---------- LWC totals ----------
const lwcTotal = Number(jestSummary.total?.statements?.total) || 0;
const lwcCovered = Number(jestSummary.total?.statements?.covered) || 0;
const lwcPct = lwcTotal
  ? (lwcCovered / lwcTotal) * 100
  : (parseFloat(jestSummary.total?.statements?.pct ?? jestSummary.total?.lines?.pct ?? 0) || 0);

// ---------- Apex scanning ----------
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

function walk(obj, visit) {
  if (!obj || typeof obj !== 'object') return;
  visit(obj);
  if (Array.isArray(obj)) obj.forEach((x) => walk(x, visit));
  else Object.values(obj).forEach((v) => walk(v, visit));
}

function collectApexTotals(files) {
  let classes = [];
  let total = 0, covered = 0;

  for (const f of files) {
    try {
      const json = JSON.parse(fs.readFileSync(f, 'utf8'));
      walk(json, (node) => {
        const name = node.name || node.apexClassOrTriggerName || node.className;
        const nLoc = Number(node.numLocations ?? node.NumLocations);
        const nCov = Number(node.numLocationsCovered ?? node.NumLocationsCovered);
        const pct  = node.percentage ?? node.coveredPercent;

        if (name && (Number.isFinite(nLoc) || Number.isFinite(pct))) {
          classes.push({
            name,
            total: Number.isFinite(nLoc) ? nLoc : undefined,
            covered: Number.isFinite(nCov) ? nCov : undefined,
            pct: Number.isFinite(pct) ? Number(pct) : undefined,
          });
        }
      });
      if (classes.length) break; // first usable file is enough
    } catch (_) { /* ignore and try next */ }
  }

  // compute real totals if present
  for (const c of classes) {
    if (Number.isFinite(c.total) && Number.isFinite(c.covered)) {
      total += c.total;
      covered += c.covered;
    }
  }
  const hasTotals = total > 0;
  const apexPct = hasTotals
    ? (covered / total) * 100
    : classes.length
      ? classes.reduce((a, c) => a + (c.pct || 0), 0) / classes.length
      : 0;

  return { classes, apexPct, apexTotal: total, apexCovered: covered, hasTotals };
}

const apexFiles = [
  ...findFiles(apexDir, ['test-result-codecoverage.json']),
  ...findFiles(apexDir, ['test-result.json']),
];
const { classes: apexClasses, apexPct, apexTotal, apexCovered, hasTotals } = collectApexTotals(apexFiles);

// ---------- project rollup ----------
const haveLwcTotals = lwcTotal > 0;
const projectPct = (haveLwcTotals && hasTotals)
  ? ((lwcCovered + apexCovered) / (lwcTotal + apexTotal)) * 100
  : (lwcPct + apexPct) / 2;

// ---------- utils ----------
function coverageColor(pct) {
  if (pct >= 90) return 'brightgreen';
  if (pct >= 70) return 'yellow';
  if (pct >= 50) return 'orange';
  return 'red';
}
function badge(labelText, pct) {
  const color = coverageColor(pct);
  const label = `${(Number.isFinite(pct) ? pct : 0).toFixed(2)}%`;
  return `![${label}](https://img.shields.io/badge/-${encodeURIComponent(label)}-${color}?label=${encodeURIComponent(labelText)})`;
}

// ---------- build markdown ----------
const lines = [];
lines.push('# Code Coverage', '');
lines.push(`_Last Updated: ${new Date().toISOString()}_`, '');
lines.push('## Overall Coverage', '');
lines.push(badge('Overall Project', projectPct), '');
lines.push(badge('Overall LWC', lwcPct), '');
lines.push(badge('Overall Apex', apexPct), '');

lines.push('## Coverage by Component', '');
lines.push('| Component | Coverage |');
lines.push('| --- | --- |');

Object.entries(jestSummary)
  .filter(([file]) => file !== 'total')
  .sort((a, b) => a[0].localeCompare(b[0]))
  .forEach(([file, stats]) => {
    const pct = parseFloat(stats.statements?.pct ?? stats.lines?.pct ?? 0) || 0;
    const name = path.basename(file);
    lines.push(`| ${name} | ${badge('', pct)} |`);
  });

// Apex table
if (apexClasses.length) {
  // de-dup per class with best available pct
  const byName = new Map();
  for (const c of apexClasses) {
    const pct = Number.isFinite(c.covered) && Number.isFinite(c.total)
      ? (c.covered / c.total) * 100
      : (c.pct || 0);
    const prev = byName.get(c.name);
    if (!prev || pct > prev.pct) byName.set(c.name, { name: c.name, pct });
  }

  lines.push('', '## Coverage by Class', '');
  lines.push('| Class | Coverage |');
  lines.push('| --- | --- |');
  [...byName.values()]
    .sort((a, b) => a.name.localeCompare(b.name))
    .forEach(({ name, pct }) => {
      const display = name.endsWith('.cls') ? name : `${name}.cls`;
      lines.push(`| ${display} | ${badge('', pct)} |`);
    });
}

lines.push('', '> Generated automatically. Run `npm run coverage:md` to refresh.', '');
lines.push('[Detailed HTML coverage report](../coverage/lcov-report/index.html)', '');

fs.mkdirSync(path.dirname(mdOut), { recursive: true });
fs.writeFileSync(mdOut, lines.join('\n') + '\n', 'utf8');
