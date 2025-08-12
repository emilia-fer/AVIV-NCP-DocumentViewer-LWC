const fs = require('fs');
const path = require('path');

const coveragePath = path.join(__dirname, '..', 'coverage', 'coverage-summary.json');
const outputPath = path.join(__dirname, '..', 'docs', 'code-coverage.md');

if (!fs.existsSync(coveragePath)) {
  console.error('Coverage summary not found. Run tests with coverage first.');
  process.exit(1);
}

const summary = JSON.parse(fs.readFileSync(coveragePath, 'utf8'));
const totalPct = Number(summary.total?.statements?.pct || 0);

const apexCoveragePath = path.join(
  __dirname,
  '..',
  'coverage',
  'test-result-codecoverage.json'
);

let apexCoverages = [];
if (fs.existsSync(apexCoveragePath)) {
  try {
    const apexRaw = JSON.parse(fs.readFileSync(apexCoveragePath, 'utf8'));
    const entries = apexRaw.result?.codecoverage || [];
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
            ? c.percentage
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

const bar = `
<div style="position:relative;width:100%;height:20px;border-radius:4px;background:linear-gradient(to right,#dc2626,#f97316,#facc15,#16a34a);">
  <div style="position:absolute;top:0;right:0;height:100%;width:${(100 - totalPct).toFixed(2)}%;background:#ddd;border-radius:0 4px 4px 0;"></div>
</div>
`;

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
    const pct = stats.statements.pct;
    const name = path.basename(file);
    const color = coverageColor(pct);
    const label = pct.toFixed(2) + '%';
    const badge = `![${label}](https://img.shields.io/badge/-${encodeURIComponent(label)}-${color}?label=)`;
    lines.push(`| ${name} | ${badge} |`);
  });

if (apexCoverages.length) {
  lines.push('');
  lines.push('### Apex Classes');
  lines.push('');
  lines.push('| Class | Coverage |');
  lines.push('| --- | --- |');
  apexCoverages.forEach(({ name, pct }) => {
    const color = coverageColor(pct);
    const label = pct.toFixed(2) + '%';
    const badge = `![${label}](https://img.shields.io/badge/-${encodeURIComponent(label)}-${color}?label=)`;
    lines.push(`| ${name}.cls | ${badge} |`);
  });
}

lines.push('');
lines.push('> Generated automatically. Run `npm run coverage:md` to refresh.');
lines.push('');
lines.push('[Detailed HTML coverage report](../coverage/lcov-report/index.html)');

fs.writeFileSync(outputPath, lines.join('\n') + '\n');