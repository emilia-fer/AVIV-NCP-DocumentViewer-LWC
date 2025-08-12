const fs = require('fs');
const path = require('path');

const coveragePath = path.join(__dirname, '..', 'coverage', 'coverage-summary.json');
const outputPath = path.join(__dirname, '..', 'docs', 'code-coverage.md');

if (!fs.existsSync(coveragePath)) {
  console.error('Coverage summary not found. Run tests with coverage first.');
  process.exit(1);
}

const summary = JSON.parse(fs.readFileSync(coveragePath, 'utf8'));
const totalPct = summary.total.statements.pct;

function coverageColor(pct) {
  if (pct >= 90) return 'brightgreen';
  if (pct >= 70) return 'yellow';
  if (pct >= 50) return 'orange';
  return 'red';
}

const bar = `\n<div style="position:relative;background:linear-gradient(to right,#dc2626,#f97316,#facc15,#16a34a);width:100%;height:20px;border-radius:4px;">\n  <div style="position:absolute;right:0;top:0;height:100%;width:${(100 - totalPct).toFixed(2)}%;background-color:#ddd;border-radius:0 4px 4px 0;"></div>\n</div>\n`;

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

lines.push('');
lines.push('> Generated automatically. Run `npm run coverage:md` to refresh.');
lines.push('');
lines.push('[Detailed HTML coverage report](../coverage/lcov-report/index.html)');

fs.writeFileSync(outputPath, lines.join('\n') + '\n');