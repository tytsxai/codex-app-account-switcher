#!/usr/bin/env node
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import process from 'node:process';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const PROJECT_DIR = path.dirname(fileURLToPath(import.meta.url));
const IMPORT_SCRIPT = path.join(PROJECT_DIR, 'codex-auth-import-json.mjs');
const DEFAULT_DIRS = [
  path.join(os.homedir(), 'Downloads'),
  path.join(os.homedir(), '.codex', 'account-sources'),
  path.join(os.homedir(), '.Trash'),
  path.join(os.homedir(), 'Documents', 'codex-accounts'),
  path.join(os.homedir(), 'Documents', '账号codex'),
  path.join(os.homedir(), '.codex', 'accounts-invalid-archive'),
];

let dryRun = false;
let yes = false;
let scanAll = false;
const explicitPaths = [];
const scanWarnings = [];

for (let i = 2; i < process.argv.length; i += 1) {
  const arg = process.argv[i];
  if (arg === '--dry-run') dryRun = true;
  else if (arg === '--yes' || arg === '-y') yes = true;
  else if (arg === '--scan-all') scanAll = true;
  else if (arg === '--help' || arg === '-h') {
    usage();
    process.exit(0);
  } else {
    explicitPaths.push(arg);
  }
}

function usage() {
  console.log(`Usage:
  codex-auth-load-free.mjs [--dry-run] [--yes] [--scan-all] [file-or-dir...]

Behavior:
  - Scans common local source folders for Codex auth JSON files
  - Locally prefilters files whose access token declares chatgpt_plan_type=free
  - Validates those Free candidates through the normal import script
  - Imports only live Free accounts whose ChatGPT usage API can be read

Default scan dirs:
  ~/Downloads
  ~/.codex/account-sources
  ~/.Trash
  ~/Documents/codex-accounts
  ~/Documents/账号codex
  ~/.codex/accounts-invalid-archive

Use --scan-all only when local token claims are missing or stale; it validates
more files live and may consume refresh tokens for invalid source snapshots.`);
}

function base64UrlDecode(input) {
  const normalized = String(input || '').replace(/-/g, '+').replace(/_/g, '/');
  const padded = normalized + '='.repeat((4 - (normalized.length % 4)) % 4);
  return Buffer.from(padded, 'base64').toString('utf8');
}

function jwtPayload(token) {
  if (!token || !String(token).includes('.')) return {};
  try {
    return JSON.parse(base64UrlDecode(String(token).split('.')[1]));
  } catch {
    return {};
  }
}

function isJsonFile(file) {
  return /(?:\.auth)?\.json$/i.test(file);
}

function walk(inputPath, out) {
  if (!fs.existsSync(inputPath)) return;
  let stat;
  try {
    stat = fs.statSync(inputPath);
  } catch (error) {
    scanWarnings.push({ path: inputPath, error: error.message });
    return;
  }
  if (stat.isFile()) {
    if (isJsonFile(inputPath)) out.push(inputPath);
    return;
  }
  if (!stat.isDirectory()) return;

  const base = path.basename(inputPath);
  if (['.git', 'node_modules', '.cache'].includes(base)) return;

  let entries;
  try {
    entries = fs.readdirSync(inputPath);
  } catch (error) {
    const fallback = spawnSync('/usr/bin/find', [
      inputPath,
      '-type',
      'f',
      '(',
      '-iname',
      '*.json',
      '-o',
      '-iname',
      '*.auth.json',
      ')',
    ], { encoding: 'utf8', maxBuffer: 20 * 1024 * 1024 });
    const found = (fallback.stdout || '').trim().split(/\n/).filter(Boolean);
    if (fallback.status === 0 && found.length > 0) {
      out.push(...found);
      scanWarnings.push({ path: inputPath, error: error.message, fallback: `find recovered ${found.length} files` });
      return;
    }
    scanWarnings.push({ path: inputPath, error: error.message, fallback: 'find recovered 0 files' });
    return;
  }

  for (const entry of entries) {
    walk(path.join(inputPath, entry), out);
  }
}

function readJson(file) {
  try {
    return JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch {
    return null;
  }
}

function tokenCandidates(data) {
  const result = [];
  if (!data) return result;

  if (Array.isArray(data.accounts)) {
    for (const account of data.accounts) {
      const c = account.credentials || {};
      result.push({
        email: c.email || account.name || account.extra?.email || '',
        access_token: c.access_token || '',
        refresh_token: c.refresh_token || '',
      });
    }
    return result;
  }

  if (Array.isArray(data)) {
    for (const item of data) result.push(...tokenCandidates(item));
    return result;
  }

  const t = data.tokens || data.credentials || data;
  result.push({
    email: data.email || data.user?.email || t.email || '',
    access_token: t.access_token || data.access_token || '',
    refresh_token: t.refresh_token || data.refresh_token || '',
  });
  return result;
}

function declaredPlan(candidate) {
  const claims = jwtPayload(candidate.access_token);
  const auth = claims['https://api.openai.com/auth'] || {};
  return String(auth.chatgpt_plan_type || '').toLowerCase();
}

function backupDirs() {
  const codexDir = path.join(os.homedir(), '.codex');
  try {
    return fs.readdirSync(codexDir)
      .filter((entry) => entry.startsWith('accounts-backup'))
      .map((entry) => path.join(codexDir, entry));
  } catch {
    return [];
  }
}

const scanRoots = explicitPaths.length > 0
  ? explicitPaths
  : (process.env.FREE_IMPORT_SEARCH_DIRS
    ? process.env.FREE_IMPORT_SEARCH_DIRS.split(':').filter(Boolean)
    : [...DEFAULT_DIRS, ...backupDirs()]);

const files = [];
for (const root of scanRoots) walk(path.resolve(root), files);

const candidates = [];
const seenFiles = new Set();

for (const file of files) {
  const data = readJson(file);
  const tokens = tokenCandidates(data).filter((item) => item.access_token || item.refresh_token);
  if (tokens.length === 0) continue;

  const plans = tokens.map(declaredPlan).filter(Boolean);
  const hasDeclaredFree = plans.includes('free');
  if (!scanAll && !hasDeclaredFree) continue;

  if (!seenFiles.has(file)) {
    seenFiles.add(file);
    candidates.push({
      file,
      token_count: tokens.length,
      declared_plans: [...new Set(plans.length > 0 ? plans : ['unknown'])],
      emails: [...new Set(tokens.map((item) => item.email).filter(Boolean))],
    });
  }
}

const args = [IMPORT_SCRIPT, '--only-plan', 'free'];
if (dryRun) args.push('--dry-run');
if (yes) args.push('--yes');
for (const candidate of candidates) args.push(candidate.file);

let importResult = null;
let importStdout = '';
let importStderr = '';
let importExit = 0;

if (candidates.length > 0) {
  const child = spawnSync(process.execPath, args, {
    cwd: PROJECT_DIR,
    encoding: 'utf8',
    maxBuffer: 50 * 1024 * 1024,
    env: process.env,
  });
  importExit = child.status ?? 1;
  importStdout = child.stdout || '';
  importStderr = child.stderr || '';
  try {
    importResult = JSON.parse(importStdout);
  } catch {
    importResult = null;
  }
}

const summary = {
  status: importExit === 0 ? 'ok' : 'import_failed',
  dry_run: dryRun,
  scan_all: scanAll,
  scan_roots: scanRoots,
  scan_warnings: scanWarnings,
  scanned_json_files: files.length,
  free_source_files: candidates.length,
  imported_count: importResult?.imported_count ?? 0,
  valid_free_count: importResult?.valid_count ?? 0,
  invalid_count: importResult?.invalid_count ?? 0,
  skipped_count: importResult?.skipped_count ?? 0,
  candidates,
  import_result: importResult,
};

console.log(JSON.stringify(summary, null, 2));

if (importExit !== 0) {
  if (importStderr) process.stderr.write(importStderr);
  if (importStdout && !importResult) process.stderr.write(importStdout);
  process.exit(importExit);
}
