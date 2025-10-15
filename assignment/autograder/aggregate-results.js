#!/usr/bin/env node
const fs = require('fs');
const path = require('path');

const resultsDir = path.resolve(process.argv[2] || path.join(process.cwd(), 'results'));

function toNumber(value, fallback = 0) {
  const num = Number(value);
  return Number.isFinite(num) ? num : fallback;
}

function stripAnsi(input) {
  if (!input) return input;
  // eslint-disable-next-line no-control-regex
  const ansiRegex = /[\u001B\u009B][[\]()#;?]*(?:[0-9]{1,4}(?:;[0-9]{0,4})*)?[0-9A-ORZcf-nqry=><]/g;
  return input.replace(ansiRegex, '');
}

function escapeHtml(value) {
  if (value == null) return '';
  return String(value)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;')
    .replace(/\r?\n/g, '<br/>');
}

function normalizeStatus(status) {
  if (!status) return 'unknown';
  const normal = String(status).toLowerCase();
  if (['pass', 'passed', 'success'].includes(normal)) return 'passed';
  if (['fail', 'failed', 'error'].includes(normal)) return 'failed';
  if (['skip', 'skipped'].includes(normal)) return 'skipped';
  if (['pending', 'todo'].includes(normal)) return 'pending';
  return normal;
}

function collectTestsFromRuns(runs) {
  if (!Array.isArray(runs)) return [];
  const details = [];
  runs.forEach((run) => {
    if (!run || !Array.isArray(run.tests)) return;
    const filePath = run.spec?.relative || run.spec?.name || run.spec?.url || run.spec?.absolute || '';
    run.tests.forEach((test) => {
      if (!test) return;
      const titleParts = Array.isArray(test.title) ? test.title : [test.title || test.name || ''];
      const testName = titleParts.filter(Boolean).join(' › ') || filePath || 'Unnamed test';
      const status = test.state || test.status || (test.displayError ? 'failed' : 'passed');
      const message = test.displayError || test.error || test.err?.message || '';
      details.push({
        name: testName,
        status,
        message,
        filePath,
      });
    });
  });
  return details;
}

function collectTestsFromResults(results) {
  if (!results) return [];
  const source = Array.isArray(results) ? results : results.tests;
  if (!Array.isArray(source)) return [];
  return source.map((entry) => ({
    name: entry?.name
      || (Array.isArray(entry?.title) ? entry.title.join(' › ') : entry?.title || 'Unnamed test'),
    status: entry?.status || entry?.state || entry?.rawStatus || (entry?.err ? 'failed' : 'passed'),
    message: entry?.message || entry?.trace || entry?.error || entry?.err?.message || '',
    filePath: entry?.filePath || entry?.file || '',
  }));
}

function collectTestsFromSuites(suites) {
  if (!Array.isArray(suites)) return [];
  const details = [];
  suites.forEach((suite) => {
    if (!suite) return;
    if (Array.isArray(suite.tests)) {
      suite.tests.forEach((test) => {
        const name = test?.title || test?.name || 'Unnamed test';
        details.push({
          name,
          status: test?.state || test?.status || (test?.err ? 'failed' : 'passed'),
          message: test?.err?.message || test?.error || '',
          filePath: suite.file || '',
        });
      });
    }
    if (Array.isArray(suite.suites)) {
      details.push(...collectTestsFromSuites(suite.suites));
    }
  });
  return details;
}

function collectTestsFromJestResults(results) {
  if (!Array.isArray(results)) return [];
  const details = [];
  results.forEach((suite) => {
    if (!suite) return;
    const filePath = suite.name || suite.testFilePath || suite.displayName || '';
    const assertions = Array.isArray(suite.assertionResults) ? suite.assertionResults : suite.testResults;
    if (!Array.isArray(assertions)) return;
    assertions.forEach((assertion) => {
      if (!assertion) return;
      const ancestors = Array.isArray(assertion.ancestorTitles) ? assertion.ancestorTitles : [];
      const titleParts = [...ancestors, assertion.title || assertion.fullName || assertion.name || ''];
      const name = titleParts.filter(Boolean).join(' › ') || assertion.title || assertion.fullName || assertion.name || 'Unnamed test';
      let message = '';
      if (Array.isArray(assertion.failureMessages) && assertion.failureMessages.length > 0) {
        message = assertion.failureMessages.join('\n');
      } else if (Array.isArray(assertion.errors) && assertion.errors.length > 0) {
        message = assertion.errors.map((err) => err?.message || err).join('\n');
      } else if (assertion.failureMessage) {
        message = assertion.failureMessage;
      }
      details.push({
        name,
        status: assertion.status || assertion.state || (message ? 'failed' : 'passed'),
        message: stripAnsi(message),
        filePath,
      });
    });
  });
  return details;
}

function collectContributionsFromData(data) {
  const contributions = [];
  if (data == null) return contributions;

  const pushContribution = (summarySource, testsSource = []) => {
    if (!summarySource) return;
    const summary = { ...summarySource };
    const tests = Array.isArray(testsSource) ? testsSource : [];
    contributions.push({ summary, tests });
  };

  if (Array.isArray(data)) {
    data.forEach((item) => {
      collectContributionsFromData(item).forEach((entry) => contributions.push(entry));
    });
    return contributions;
  }

  if (data?.results?.summary) {
    const tests = collectTestsFromResults(data.results);
    pushContribution(data.results.summary, tests);
  }

  if (data?.summary && data.summary !== data?.results?.summary) {
    const tests = collectTestsFromResults(data);
    pushContribution(data.summary, tests);
  }

  if (Number.isFinite(Number(data?.numTotalTests)) || Number.isFinite(Number(data?.numPassedTests))) {
    const totalTests = toNumber(data.numTotalTests);
    const passed = toNumber(data.numPassedTests);
    const failed = toNumber(data.numFailedTests);
    const pending = toNumber(data.numTodoTests);
    const skipped = toNumber(data.numPendingTests) + pending;
    const tests = collectTestsFromJestResults(data.testResults);
    pushContribution(
      {
        tests: totalTests,
        passed,
        failed,
        skipped,
        pending,
      },
      tests,
    );
  }

  if (Number.isFinite(Number(data?.totalTests)) || Number.isFinite(Number(data?.totalPassed))) {
    const summary = {
      tests: data.totalTests,
      passed: data.totalPassed,
      failed: data.totalFailed,
      skipped: data.totalSkipped,
      pending: data.totalPending,
    };
    const tests = collectTestsFromRuns(data.runs) ?? collectTestsFromResults(data.results);
    pushContribution(summary, tests);
  }

  if (data?.stats) {
    const summary = {
      tests: data.stats.tests,
      passed: data.stats.passes,
      failed: data.stats.failures,
      skipped: data.stats.skipped,
      pending: data.stats.pending,
    };
    const tests = collectTestsFromRuns(data.runs);
    pushContribution(summary, tests);
  }

  if (Array.isArray(data?.runs)) {
    data.runs.forEach((run) => {
      if (!run?.stats) return;
      const summary = {
        tests: run.stats.tests,
        passed: run.stats.passes,
        failed: run.stats.failures,
        skipped: run.stats.skipped,
        pending: run.stats.pending,
      };
      const tests = collectTestsFromRuns([run]);
      pushContribution(summary, tests);
    });
  }

  if (Array.isArray(data?.suites)) {
    const tests = collectTestsFromSuites(data.suites);
    if (tests.length > 0) {
      pushContribution(
        {
          tests: tests.length,
          passed: tests.filter((t) => normalizeStatus(t.status) === 'passed').length,
        },
        tests,
      );
    }
  }

  if (contributions.length === 0 && typeof data === 'object') {
    const summary = data?.summary || data?.results?.summary || data?.stats;
    if (summary) {
      const tests = collectTestsFromResults(data?.results) || collectTestsFromRuns(data?.runs);
      pushContribution(summary, tests);
    }
  }

  return contributions;
}

function parseJsonFile(filePath) {
  try {
    const raw = fs.readFileSync(filePath, 'utf8');
    const data = JSON.parse(raw);
    return collectContributionsFromData(data);
  } catch (err) {
    return [];
  }
}

function findJsonBlocks(text) {
  const blocks = [];
  let depth = 0;
  let start = -1;
  let inString = false;
  let escaped = false;

  for (let i = 0; i < text.length; i += 1) {
    const char = text[i];

    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (char === '\\') {
        escaped = true;
      } else if (char === '"') {
        inString = false;
      }
      continue;
    }

    if (char === '"') {
      inString = true;
      continue;
    }

    if (char === '{') {
      if (depth === 0) start = i;
      depth += 1;
    } else if (char === '}' && depth > 0) {
      depth -= 1;
      if (depth === 0 && start !== -1) {
        const block = text.slice(start, i + 1);
        blocks.push(block);
        start = -1;
      }
    }
  }

  return blocks;
}

function parseTextFile(filePath) {
  try {
    const raw = fs.readFileSync(filePath, 'utf8');
    const text = stripAnsi(raw);
    const contributions = [];

    const blocks = findJsonBlocks(text);
    blocks.forEach((block) => {
      try {
        const parsed = JSON.parse(block);
        const items = collectContributionsFromData(parsed);
        if (items.length > 0) contributions.push(...items);
      } catch (_) {
        /* ignore parse failures */
      }
    });

    if (contributions.length > 0) {
      return contributions;
    }

    const matches = (regex) => {
      const found = [...text.matchAll(regex)];
      if (found.length === 0) return 0;
      return Number(found[found.length - 1][1]);
    };

    const passing = matches(/(\d+)\s+passing/gi);
    const failing = matches(/(\d+)\s+failing/gi);
    const pending = matches(/(\d+)\s+pending/gi);
    const skipped = matches(/(\d+)\s+skipped/gi);
    const totalMatch = [...text.matchAll(/(\d+)\s+tests?\s*completed/gi)];
    const total = totalMatch.length > 0 ? Number(totalMatch.pop()[1]) : passing + failing + pending + skipped;

    if (total > 0 || passing > 0) {
      return [{
        summary: {
          tests: total,
          passed: passing,
          failed: failing,
          skipped: skipped,
          pending,
        },
        tests: [],
      }];
    }
  } catch (err) {
    return [];
  }
  return [];
}

function uniqueTestKey(file, detail) {
  const parts = [
    file || '',
    detail.filePath || '',
    detail.name || '',
    detail.status || '',
  ];
  return parts.join('|');
}

function aggregateResults() {
  const totals = { tests: 0, passed: 0, skipped: 0 };
  const contributions = [];
  const failures = [];
  const warnings = [];
  const seenTests = new Set();

  if (!fs.existsSync(resultsDir)) {
    return {
      totals,
      contributions,
      failures,
      warnings: ['Results directory not found'],
    };
  }

  const entries = fs.readdirSync(resultsDir);
  entries.forEach((entry) => {
    const fullPath = path.join(resultsDir, entry);
    const stat = fs.statSync(fullPath);
    if (!stat.isFile()) return;

    let parsed = [];
    if (entry.endsWith('.json')) {
      parsed = parseJsonFile(fullPath);
    } else if (entry.endsWith('.log') || entry.includes('raw')) {
      parsed = parseTextFile(fullPath);
    }

    if (parsed.length === 0) return;

    parsed.forEach(({ summary, tests }) => {
      const totalTests = toNumber(summary.tests);
      const skipped = toNumber(summary.skipped) + toNumber(summary.pending) + toNumber(summary.other);
      const detailList = Array.isArray(tests) ? tests : [];
      const detailPassed = detailList.filter((t) => normalizeStatus(t.status) === 'passed').length;
      const detailExecuted = detailList.filter((t) => {
        const status = normalizeStatus(t.status);
        return !['skipped', 'pending'].includes(status);
      }).length;

      let passed = summary.passed ?? summary.passes;
      const failedCount = toNumber(summary.failed) + toNumber(summary.failures) + toNumber(summary.fail);
      if (passed == null) {
        passed = totalTests - Math.max(0, skipped) - failedCount;
      }
      passed = toNumber(passed);

      let effectiveTests = totalTests;
      const executedFromSummary = Math.max(0, passed + Math.max(0, failedCount));

      if (effectiveTests === 0 || (executedFromSummary > 0 && effectiveTests > executedFromSummary)) {
        effectiveTests = executedFromSummary;
      }

      if (detailExecuted > 0 && (effectiveTests === 0 || effectiveTests > detailExecuted)) {
        effectiveTests = detailExecuted;
      }

      if (effectiveTests === 0 && passed > 0) {
        effectiveTests = passed;
      }

      if (effectiveTests < passed) {
        effectiveTests = passed;
      }

      if (detailPassed > passed) passed = detailPassed;
      if (effectiveTests === 0 && detailPassed > 0) effectiveTests = detailPassed;
      const cappedPassed = Math.max(0, Math.min(passed, effectiveTests));

      totals.tests += Math.max(0, effectiveTests);
      totals.passed += cappedPassed;
      totals.skipped += Math.max(0, skipped);

      contributions.push({
        file: entry,
        tests: Math.max(0, effectiveTests),
        passed: cappedPassed,
        skipped: Math.max(0, skipped),
      });

      detailList.forEach((detail) => {
        const key = uniqueTestKey(entry, detail);
        if (seenTests.has(key)) return;
        seenTests.add(key);
        const status = normalizeStatus(detail.status);
        if (!['passed', 'skipped', 'pending'].includes(status)) {
          failures.push({
            file: detail.filePath || entry,
            name: detail.name || 'Unnamed test',
            status,
            message: (detail.message || '').toString(),
          });
        }
      });
    });
  });

  if (totals.tests === 0 && totals.passed === 0) {
    const rawFile = path.join(resultsDir, 'autograder-e2e.log');
    if (fs.existsSync(rawFile)) {
      const fallback = parseTextFile(rawFile);
      fallback.forEach(({ summary }) => {
        const totalTests = toNumber(summary.tests);
        const skipped = toNumber(summary.skipped) + toNumber(summary.pending);
        const passedSummary = toNumber(summary.passed ?? summary.passes);
        const failedCount = toNumber(summary.failed) + toNumber(summary.failures) + toNumber(summary.fail);
        let effectiveTests = totalTests;
        const executed = Math.max(0, passedSummary + Math.max(0, failedCount));

        if (effectiveTests === 0 || (executed > 0 && effectiveTests > executed)) {
          effectiveTests = executed;
        }

        if (effectiveTests === 0 && passedSummary > 0) {
          effectiveTests = passedSummary;
        }

        const cappedPassed = Math.max(0, Math.min(passedSummary, effectiveTests));

        totals.tests += Math.max(0, effectiveTests);
        totals.passed += cappedPassed;
        totals.skipped += Math.max(0, skipped);
        contributions.push({
          file: path.basename(rawFile),
          tests: Math.max(0, effectiveTests),
          passed: cappedPassed,
          skipped: Math.max(0, skipped),
        });
      });
    }
  }

  const failureItems = failures.map((fail) => {
    const location = fail.file ? `<code>${escapeHtml(fail.file)}</code>: ` : '';
    const message = fail.message ? `<br/><span class="detail">${escapeHtml(fail.message)}</span>` : '';
    return `<li>${location}${escapeHtml(fail.name)}${message}</li>`;
  });

  return {
    totals,
    contributions,
    failures,
    warnings,
    html: {
      failuresList: failureItems.length ? `<ul>${failureItems.join('')}</ul>` : '',
    },
  };
}

const result = aggregateResults();
console.log(JSON.stringify({
  tests: result.totals.tests,
  passed: result.totals.passed,
  skipped: result.totals.skipped,
  failures: result.failures,
  warnings: result.warnings,
  contributions: result.contributions,
  html: result.html,
}, null, 2));
