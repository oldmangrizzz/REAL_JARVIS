#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');
const { parseArgs } = require('../../shared/args');
const { logEvent } = require('../../shared/event-log');
const { sendTelegram } = require('../../shared/telegram-delivery');
const { resolveWorkspaceRoot, resolveSkillsDir } = require('../../shared/workspace-root');

let SKILLS_DIR = resolveSkillsDir({});
let TELEGRAM_GROUP = process.env.SKILL_DRIFT_TELEGRAM_GROUP || '';
let TELEGRAM_TOPIC = process.env.SKILL_DRIFT_TELEGRAM_TOPIC || '';

// Stop words excluded from overlap detection
const STOP_WORDS = new Set([
  'use', 'when', 'for', 'the', 'a', 'is', 'to', 'and', 'or', 'not',
  'in', 'of', 'with', 'it', 'an', 'as', 'by', 'on', 'at', 'be',
  'this', 'that', 'from', 'are', 'was', 'were', 'has', 'have', 'had',
  'do', 'does', 'did', 'will', 'would', 'can', 'could', 'should',
  'may', 'might', 'must', 'shall', 'its', 'than', 'then', 'also',
  'about', 'up', 'out', 'if', 'no', 'so', 'but', 'all', 'any',
  'each', 'every', 'other', 'into', 'over', 'such', 'only', 'very',
  'just', 'more', 'most', 'some', 'these', 'those', 'what', 'which',
  'who', 'how', 'your', 'you', 'my', 'our', 'their', 'his', 'her',
  'he', 'she', 'they', 'we', 'me', 'us', 'him', 'them',
]);

/**
 * Parse YAML frontmatter from a SKILL.md file.
 * Splits on `---` markers and parses key: value lines.
 * Handles multi-line `description: >` blocks.
 */
function parseFrontmatter(content) {
  const match = content.match(/^---\s*\n([\s\S]*?)\n---/);
  if (!match) return null;

  const raw = match[1];
  const result = {};
  let currentKey = null;
  let multiLine = false;

  for (const line of raw.split('\n')) {
    // Continuation of a multi-line value (indented line)
    if (multiLine && currentKey && /^\s+\S/.test(line)) {
      result[currentKey] = (result[currentKey] + ' ' + line.trim()).trim();
      continue;
    }
    multiLine = false;

    const kvMatch = line.match(/^(\w[\w-]*):\s*(.*)/);
    if (kvMatch) {
      currentKey = kvMatch[1];
      const val = kvMatch[2].trim();
      if (val === '>' || val === '|') {
        // Multi-line scalar indicator
        result[currentKey] = '';
        multiLine = true;
      } else {
        result[currentKey] = val;
        multiLine = false;
      }
    }
  }

  return result;
}

/**
 * Extract significant words from a description for overlap detection.
 */
function getSignificantWords(description) {
  if (!description) return new Set();
  const words = description
    .toLowerCase()
    .replace(/[^a-z0-9\s-]/g, ' ')
    .split(/\s+/)
    .filter(w => w.length > 2 && !STOP_WORDS.has(w));
  return new Set(words);
}

/**
 * Compute Jaccard-like overlap between two word sets.
 * Returns the fraction of the smaller set that overlaps.
 */
function computeOverlap(setA, setB) {
  if (setA.size === 0 || setB.size === 0) return 0;
  let shared = 0;
  for (const w of setA) {
    if (setB.has(w)) shared++;
  }
  const minSize = Math.min(setA.size, setB.size);
  return shared / minSize;
}

/**
 * Check if two skills have negative triggers referencing each other.
 */
function hasDisambiguation(descA, descB, nameA, nameB) {
  if (!descA || !descB) return false;
  const lowerA = descA.toLowerCase();
  const lowerB = descB.toLowerCase();
  // Check if A mentions B in a "not for" / negative context, or vice versa
  const aRefsB = lowerA.includes(nameB.toLowerCase()) || lowerA.includes(nameB.replace(/-/g, ' '));
  const bRefsA = lowerB.includes(nameA.toLowerCase()) || lowerB.includes(nameA.replace(/-/g, ' '));
  return aRefsB || bRefsA;
}

/**
 * Run all checks on a single skill.
 */
function checkSkill(skillDir, skillName) {
  const results = {
    name: skillName,
    checks: [],
    warnings: 0,
    failures: 0,
    passes: 0,
  };

  const skillMdPath = path.join(skillDir, 'SKILL.md');
  if (!fs.existsSync(skillMdPath)) {
    results.checks.push({ check: 'skill-md-exists', status: 'fail', detail: 'No SKILL.md found' });
    results.failures++;
    return results;
  }

  const content = fs.readFileSync(skillMdPath, 'utf8');
  const frontmatter = parseFrontmatter(content);

  // === Frontmatter Validity ===
  if (!frontmatter) {
    results.checks.push({ check: 'frontmatter-exists', status: 'fail', detail: 'No YAML frontmatter found' });
    results.failures++;
    return results;
  }

  // Has name field
  if (frontmatter.name) {
    results.checks.push({ check: 'has-name', status: 'pass' });
    results.passes++;
  } else {
    results.checks.push({ check: 'has-name', status: 'fail', detail: 'Missing name field in frontmatter' });
    results.failures++;
  }

  // Has description field
  if (frontmatter.description) {
    results.checks.push({ check: 'has-description', status: 'pass' });
    results.passes++;
  } else {
    results.checks.push({ check: 'has-description', status: 'fail', detail: 'Missing description field in frontmatter' });
    results.failures++;
  }

  // Name is kebab-case
  if (frontmatter.name) {
    const kebabOk = /^[a-z0-9]+(-[a-z0-9]+)*$/.test(frontmatter.name);
    if (kebabOk) {
      results.checks.push({ check: 'name-kebab-case', status: 'pass' });
      results.passes++;
    } else {
      results.checks.push({ check: 'name-kebab-case', status: 'fail', detail: `Name "${frontmatter.name}" is not kebab-case` });
      results.failures++;
    }
  }

  const description = frontmatter.description || '';

  // === Description Quality ===

  // Has trigger phrases
  const triggerPattern = /use when|says|ask(?:s|ed)? (?:about|for|to)|want(?:s)? to|mention/i;
  if (triggerPattern.test(description)) {
    results.checks.push({ check: 'has-trigger-phrases', status: 'pass' });
    results.passes++;
  } else {
    results.checks.push({ check: 'has-trigger-phrases', status: 'warn', detail: 'Missing trigger phrases (e.g. "Use when...")' });
    results.warnings++;
  }

  // Has negative triggers
  const negativeTriggerPattern = /not for|do not use|don't use|NOT for|instead/i;
  if (negativeTriggerPattern.test(description)) {
    results.checks.push({ check: 'has-negative-triggers', status: 'pass' });
    results.passes++;
  } else {
    results.checks.push({ check: 'has-negative-triggers', status: 'warn', detail: 'Missing negative triggers (e.g. "NOT for...")' });
    results.warnings++;
  }

  // Description length > 100
  if (description.length > 100) {
    results.checks.push({ check: 'description-min-length', status: 'pass' });
    results.passes++;
  } else {
    results.checks.push({ check: 'description-min-length', status: 'warn', detail: `Description too short (${description.length} chars, min 100)` });
    results.warnings++;
  }

  // Description length < 1024
  if (description.length <= 1024) {
    results.checks.push({ check: 'description-max-length', status: 'pass' });
    results.passes++;
  } else {
    results.checks.push({ check: 'description-max-length', status: 'warn', detail: `Description too long (${description.length} chars, max 1024)` });
    results.warnings++;
  }

  // === SKILL.md Size ===
  // Get content after frontmatter
  const bodyContent = content.replace(/^---[\s\S]*?---\s*/, '');
  const wordCount = bodyContent.split(/\s+/).filter(w => w.length > 0).length;

  if (wordCount < 5000) {
    results.checks.push({ check: 'skillmd-word-count', status: 'pass', detail: `${wordCount} words` });
    results.passes++;
  } else {
    results.checks.push({ check: 'skillmd-word-count', status: 'warn', detail: `SKILL.md has ${wordCount} words (max 5000)` });
    results.warnings++;
  }

  // If > 3000 words, check for references/ directory
  if (wordCount > 3000) {
    const refsDir = path.join(skillDir, 'references');
    if (fs.existsSync(refsDir)) {
      results.checks.push({ check: 'progressive-disclosure', status: 'pass', detail: 'references/ directory exists' });
      results.passes++;
    } else {
      results.checks.push({
        check: 'progressive-disclosure',
        status: 'warn',
        detail: `SKILL.md over 3000 words (${wordCount}), no references/ dir; could benefit from progressive disclosure`,
      });
      results.warnings++;
    }
  }

  return results;
}

/**
 * Run overlap detection across all skills.
 */
function checkOverlaps(skillResults) {
  const overlaps = [];
  const skillData = skillResults.map(r => {
    const skillMdPath = path.join(SKILLS_DIR, r.name, 'SKILL.md');
    let description = '';
    if (fs.existsSync(skillMdPath)) {
      const content = fs.readFileSync(skillMdPath, 'utf8');
      const fm = parseFrontmatter(content);
      if (fm) description = fm.description || '';
    }
    return { name: r.name, description, words: getSignificantWords(description) };
  });

  for (let i = 0; i < skillData.length; i++) {
    for (let j = i + 1; j < skillData.length; j++) {
      const a = skillData[i];
      const b = skillData[j];
      const overlap = computeOverlap(a.words, b.words);

      if (overlap > 0.4) {
        const disambiguated = hasDisambiguation(a.description, b.description, a.name, b.name);
        overlaps.push({
          skills: [a.name, b.name],
          overlapPct: Math.round(overlap * 100),
          status: disambiguated ? 'resolved' : 'warn',
          detail: disambiguated
            ? `${Math.round(overlap * 100)}% keyword overlap (disambiguated via negative triggers)`
            : `${Math.round(overlap * 100)}% keyword overlap, potential duplication`,
        });
      }
    }
  }

  return overlaps;
}

/**
 * Format the Telegram notification message.
 */
function formatTelegramMessage(report) {
  const { summary, skills, overlaps } = report;
  const lines = ['🔍 Skill Drift Report', ''];

  if (summary.failures > 0 || summary.warnings > 0) {
    const parts = [];
    if (summary.warnings > 0) parts.push(`${summary.warnings} warning${summary.warnings !== 1 ? 's' : ''}`);
    if (summary.failures > 0) parts.push(`${summary.failures} failure${summary.failures !== 1 ? 's' : ''}`);
    lines.push(`⚠️ ${parts.join(', ')} across ${summary.totalSkills} skills`);
    lines.push('');
  }

  // Collect warnings and failures
  const issues = [];

  for (const skill of skills) {
    for (const check of skill.checks) {
      if (check.status === 'warn' || check.status === 'fail') {
        const icon = check.status === 'fail' ? '❌' : '⚠️';
        issues.push(`${icon} ${skill.name}: ${check.detail}`);
      }
    }
  }

  // Add unresolved overlaps
  for (const overlap of overlaps) {
    if (overlap.status === 'warn') {
      issues.push(`⚠️ potential overlap: ${overlap.skills[0]} ↔ ${overlap.skills[1]} (${overlap.overlapPct}%)`);
    }
  }

  if (issues.length > 0) {
    lines.push('Issues:');
    for (const issue of issues) {
      lines.push(`• ${issue}`);
    }
    lines.push('');
  }

  // Frontmatter summary
  const fmFailures = skills.some(s =>
    s.checks.some(c => ['has-name', 'has-description', 'name-kebab-case'].includes(c.check) && c.status === 'fail')
  );
  if (!fmFailures) {
    lines.push('All skills pass frontmatter validation ✅');
  }

  return lines.join('\n');
}

async function main() {
  const opts = parseArgs({ notify: false, json: false, verbose: false, workspace: '', skillsDir: '', group: '', topic: '' });
  const workspaceRoot = resolveWorkspaceRoot({ workspace: opts.workspace });
  SKILLS_DIR = resolveSkillsDir({ workspace: workspaceRoot, skillsDir: opts.skillsDir });
  TELEGRAM_GROUP = opts.group || process.env.SKILL_DRIFT_TELEGRAM_GROUP || '';
  TELEGRAM_TOPIC = opts.topic || process.env.SKILL_DRIFT_TELEGRAM_TOPIC || '';
  let skillDirs;
  try {
    skillDirs = fs.readdirSync(SKILLS_DIR).filter((name) => { const fullPath = path.join(SKILLS_DIR, name); return fs.statSync(fullPath).isDirectory(); });
  } catch (err) {
    console.error(`Failed to read skills directory at ${SKILLS_DIR}: ${err.message}. Set OPENCLAW_WORKSPACE, pass --workspace, or pass --skills-dir to point at a valid skills folder.`);
    process.exit(1);
  }
  const skillResults = skillDirs.map((name) => checkSkill(path.join(SKILLS_DIR, name), name));
  const overlaps = checkOverlaps(skillResults);
  let totalWarnings = 0, totalFailures = 0, totalPasses = 0;
  for (const skill of skillResults) { totalWarnings += skill.warnings; totalFailures += skill.failures; totalPasses += skill.passes; }
  const overlapWarnings = overlaps.filter((o) => o.status === 'warn').length;
  totalWarnings += overlapWarnings;
  const report = { summary: { totalSkills: skillDirs.length, warnings: totalWarnings, failures: totalFailures, passes: totalPasses, overlapPairs: overlaps.length, unresolvedOverlaps: overlapWarnings }, skills: opts.verbose ? skillResults : skillResults.filter((s) => s.warnings > 0 || s.failures > 0), overlaps: opts.verbose ? overlaps : overlaps.filter((o) => o.status === 'warn') };
  if (opts.json) { console.log(JSON.stringify(report, null, 2)); } else { console.log(`
Skill Drift Report: ${report.summary.totalSkills} skills scanned from ${SKILLS_DIR}`); console.log(`  ✅ ${totalPasses} passes | ⚠️ ${totalWarnings} warnings | ❌ ${totalFailures} failures
`); }
  logEvent({ event: 'skill-drift-check', ok: totalFailures === 0, warnings: totalWarnings, failures: totalFailures, passes: totalPasses, totalSkills: skillDirs.length, workspaceRoot, skillsDir: SKILLS_DIR }, { workspace: workspaceRoot });
  if (opts.notify && (totalWarnings > 0 || totalFailures > 0)) { if (!TELEGRAM_GROUP || !TELEGRAM_TOPIC) throw new Error('Missing SKILL_DRIFT_TELEGRAM_GROUP or SKILL_DRIFT_TELEGRAM_TOPIC for --notify delivery.'); const message = formatTelegramMessage(report); await sendTelegram(TELEGRAM_GROUP, TELEGRAM_TOPIC, message, { priority: 'high' }); if (!opts.json) console.log('Telegram notification sent.'); } else if (opts.notify && !opts.json) { console.log('All checks passed; configure your outer cron or harness if you want clean-run notifications.'); }
  process.exit(totalFailures > 0 ? 1 : 0);
}
main().catch((err) => { console.error(err instanceof Error ? err.message : String(err)); process.exit(1); });
