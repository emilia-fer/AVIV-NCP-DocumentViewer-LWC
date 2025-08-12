const fs = require('fs');
const path = require('path');

const coverageDir = path.join(__dirname, '..', 'coverage');
const coveragePath = path.join(coverageDir, 'coverage-summary.json');
const outputPath = path.join(__dirname, '..', 'docs', 'code-coverage.md');

if (!fs.existsSync(coveragePath)) {
  console.error('Coverage summary not found. Run tests with coverage first.');
  process.exit(1);
}

const summary = JSON.parse(fs.readFileSync(coveragePath, 'utf8'));
const totalPct =
  parseFloat(
    summary.total?.statements?.pct ?? summary.total?.lines?.pct ?? 0
  ) || 0;

function findApexCoverage(dir) {
  const candidate = path.join(dir, 'test-result-codecoverage.json');
  if (fs.existsSync(candidate)) return candidate;
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (entry.isDirectory()) {
      const found = findApexCoverage(path.join(dir, entry.name));
      if (found) return found;
    }
  }
  return null;
}

function extractApexCoverages(obj) {
  if (!obj || typeof obj !== 'object') return [];
  if (Array.isArray(obj)) return obj.flatMap(extractApexCoverages);

  const collections = [];
  for (const key of ['codeCoverage', 'codecoverage', 'coverage']) {
    const val = obj[key];
    if (Array.isArray(val)) collections.push(val);
    else if (val && Array.isArray(val.coverage)) collections.push(val.coverage);
  }

  return collections.flat().concat(
    Object.values(obj).flatMap(extractApexCoverages)
  );
}

const apexCoveragePath = findApexCoverage(coverageDir);
let apexCoverages = [];
if (apexCoveragePath && fs.existsSync(apexCoveragePath)) {
  try {
    const apexRaw = JSON.parse(fs.readFileSync(apexCoveragePath, 'utf8'));
    const entries = extractApexCoverages(apexRaw);
    apexCoverages = entries
      .map((c) => {
        const total =
          c.numLocations ??
          (Array.isArray(c.coveredLines) && Array.isArray(c.uncoveredLines)
            ? c.coveredLines.length + c.uncoveredLines.length
            : undefined);
        const covered =
          c.numLocationsCovered ??
          (Array.isArray(c.coveredLines) ? c.coveredLines.length : undefined);
        const pct =
          c.percentage !== undefined
            ? parseFloat(c.percentage)
            : total
            ? (covered / total) * 100
            : 0;
        return { name: c.name || c.apexClassOrTriggerName, pct };
      })
      .sort((a, b) => a.name.localeCompare(b.name));
  } catch (e) {
    console.warn('Failed to parse Apex coverage:', e.message);
  }
}

function coverageColor(pct) {
  if (pct >= 90) return 'brightgreen';
  if (pct >= 70) return 'yellow';
  if (pct >= 50) return 'orange';
  return 'red';
}

const bar = `![Overall ${totalPct.toFixed(2)}%](https://progress-bar.dev/${Math.round(totalPct)}?scale=100&width=500&suffix=%25)`;

const lines = [];
lines.push('# Code Coverage');
lines.push('');
lines.push(`_Last Updated: ${new Date().toISOString()}_`);
lines.push('');
lines.push('## Overall Coverage');
lines.push('');
lines.push(bar);
lines.push('');
lines.push(`**${totalPct.toFixed(2)}%**`);
lines.push('');
lines.push('## Coverage by Component');
lines.push('');
lines.push('| Component | Coverage |');
lines.push('| --- | --- |');

Object.entries(summary)
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
  lines.push('');
  lines.push('## Coverage by Class');
  lines.push('');
  lines.push('| Class | Coverage |');
  lines.push('| --- | --- |');
  apexCoverages.forEach(({ name, pct }) => {
    const color = coverageColor(pct);
    const label = pct.toFixed(2) + '%';
    const badge = `![${label}](https://img.shields.io/badge/-${encodeURIComponent(
      label
    )}-${color}?label=)`;
    lines.push(`| ${name}.cls | ${badge} |`);
  });
}

lines.push('');
lines.push('> Generated automatically. Run `npm run coverage:md` to refresh.');
lines.push('');
lines.push('[Detailed HTML coverage report](../coverage/lcov-report/index.html)');
lines.push('');

fs.writeFileSync(outputPath, lines.join('\n') + '\n');