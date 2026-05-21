#!/usr/bin/env node
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import process from 'node:process';

const CODEX_HOME = process.env.CODEX_HOME || path.join(os.homedir(), '.codex');
const ACCOUNTS_DIR = path.join(CODEX_HOME, 'accounts');
const REGISTRY_FILE = path.join(ACCOUNTS_DIR, 'registry.json');
const ACTIVE_AUTH_FILE = path.join(CODEX_HOME, 'auth.json');
const CLIENT_ID = 'app_EMoamEEZ73f0CkXaXp7hrann';
const CURL_TIMEOUT_MS = Number(process.env.IMPORT_TIMEOUT_MS || 8000);
const INVALID_SOURCE_ROOT = process.env.INVALID_SOURCE_ROOT || path.join(CODEX_HOME, 'accounts-invalid-sources');

let dryRun = false;
let yes = false;
let onlyPlan = '';
const inputFiles = [];

for (let i = 2; i < process.argv.length; i += 1) {
  const arg = process.argv[i];
  if (arg === '--dry-run') dryRun = true;
  else if (arg === '--yes' || arg === '-y') yes = true;
  else if (arg === '--only-plan') {
    i += 1;
    if (i >= process.argv.length) {
      console.error('missing value for --only-plan');
      process.exit(1);
    }
    onlyPlan = lower(process.argv[i]);
  } else if (arg.startsWith('--only-plan=')) {
    onlyPlan = lower(arg.slice('--only-plan='.length));
  }
  else if (arg === '--help' || arg === '-h') {
    usage();
    process.exit(0);
  } else {
    inputFiles.push(arg);
  }
}

if (inputFiles.length === 0) {
  usage();
  process.exit(1);
}

function usage() {
  console.log(`Usage:
  codex-auth-import-json.mjs [--dry-run] [--yes] <json-file>...

Behavior:
  - Accepts codex-sub2api export JSON and codex-auth auth JSON snapshots
  - Imports only accounts whose ChatGPT usage API can be read in real time
  - --only-plan <plan> imports only live accounts whose usage plan matches
    the requested plan, for example --only-plan free
  - If access_token is expired, refresh_token is used once and the rotated token
    is saved into the account snapshot before registry update
  - Invalid accounts are reported and never written to registry
  - Rejected source files are archived under INVALID_SOURCE_ROOT, which defaults
    to ~/.codex/accounts-invalid-sources rather than this project directory`);
}

function readJson(file) {
  return JSON.parse(fs.readFileSync(file, 'utf8'));
}

function base64UrlDecode(input) {
  const normalized = input.replace(/-/g, '+').replace(/_/g, '/');
  const padded = normalized + '='.repeat((4 - (normalized.length % 4)) % 4);
  return Buffer.from(padded, 'base64').toString('utf8');
}

function jwtPayload(token) {
  if (!token || !token.includes('.')) return {};
  try {
    return JSON.parse(base64UrlDecode(token.split('.')[1]));
  } catch {
    return {};
  }
}

function lower(value) {
  return String(value || '').toLowerCase();
}

function usageFromApi(payload) {
  const primary = payload?.rate_limit?.primary_window;
  if (primary?.used_percent == null) return null;
  const secondary = payload?.rate_limit?.secondary_window || null;
  return {
    primary: {
      used_percent: Math.floor(primary.used_percent),
      window_minutes: Math.floor((primary.limit_window_seconds || 18000) / 60),
      resets_at: primary.reset_at || 0,
    },
    secondary: {
      used_percent: secondary?.used_percent == null ? null : Math.floor(secondary.used_percent),
      window_minutes: secondary == null ? null : Math.floor((secondary.limit_window_seconds || 604800) / 60),
      resets_at: secondary?.reset_at || 0,
      present: secondary != null,
    },
    credits: payload?.credits ?? null,
    plan_type: lower(payload?.plan_type || 'unknown'),
  };
}

function accountFileForKey(accountKey) {
  const encoded = Buffer.from(accountKey).toString('base64').replace(/=+$/g, '');
  return path.join(ACCOUNTS_DIR, `${encoded}.auth.json`);
}

function timestamp() {
  const d = new Date();
  const pad = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}${pad(d.getMonth() + 1)}${pad(d.getDate())}-${pad(d.getHours())}${pad(d.getMinutes())}${pad(d.getSeconds())}`;
}

function safeFileName(value) {
  return String(value || 'unknown').replace(/[^A-Za-z0-9._@-]+/g, '_').slice(0, 160);
}

function authPayload(tokens) {
  const out = {
    auth_mode: 'chatgpt',
    last_refresh: new Date().toISOString(),
    tokens: {
      access_token: tokens.access_token,
      refresh_token: tokens.refresh_token,
      id_token: tokens.id_token,
      account_id: tokens.account_id,
    },
  };
  for (const key of Object.keys(out.tokens)) {
    if (out.tokens[key] == null || out.tokens[key] === '') delete out.tokens[key];
  }
  return out;
}

function candidatesFromFile(file) {
  const data = readJson(file);
  const result = [];
  if (Array.isArray(data.accounts)) {
    for (const account of data.accounts) {
      const c = account.credentials || {};
      result.push({
        file,
        source: 'sub2api',
        email: c.email || account.name || account.extra?.email || '',
        account_name: account.name || null,
        tokens: {
          access_token: c.access_token || '',
          refresh_token: c.refresh_token || '',
          id_token: c.id_token || '',
          account_id: c.chatgpt_account_id || c.account_id || '',
        },
        hints: {
          chatgpt_user_id: c.chatgpt_user_id || '',
          organization_id: c.organization_id || '',
        },
      });
    }
    return result;
  }

  const t = data.tokens || {};
  result.push({
    file,
    source: t.access_token || t.refresh_token ? 'codex-auth' : 'flat-token',
    email: data.email || data.user?.email || '',
    account_name: data.account_name || data.user?.name || data.email || null,
    tokens: {
      access_token: t.access_token || data.access_token || '',
      refresh_token: t.refresh_token || data.refresh_token || '',
      id_token: t.id_token || data.id_token || '',
      account_id: t.account_id || data.account_id || '',
    },
    hints: {
      chatgpt_user_id: data.chatgpt_user_id || '',
      organization_id: data.organization_id || '',
    },
  });
  return result;
}

async function fetchJson(url, options) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), CURL_TIMEOUT_MS);
  try {
    const res = await fetch(url, { ...options, signal: controller.signal });
    let body = null;
    try {
      body = await res.json();
    } catch {
      body = {};
    }
    return { status: res.status, body };
  } finally {
    clearTimeout(timer);
  }
}

async function refreshTokens(tokens) {
  if (!tokens.refresh_token) return { ok: false, status: 'no_refresh_token' };
  const { status, body } = await fetchJson('https://auth.openai.com/oauth/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      grant_type: 'refresh_token',
      refresh_token: tokens.refresh_token,
      client_id: CLIENT_ID,
      scope: 'openid profile email offline_access',
    }),
  });

  if (status !== 200 || !body?.access_token) {
    return { ok: false, status: `refresh_http_${status}`, error: body?.error || body?.message || '' };
  }

  return {
    ok: true,
    tokens: {
      ...tokens,
      access_token: body.access_token,
      id_token: body.id_token || tokens.id_token,
      refresh_token: body.refresh_token || tokens.refresh_token,
    },
  };
}

async function fetchUsage(tokens) {
  if (!tokens.access_token) return { ok: false, status: 'no_access_token' };
  const { status, body } = await fetchJson('https://chatgpt.com/backend-api/wham/usage', {
    headers: {
      Authorization: `Bearer ${tokens.access_token}`,
      Accept: 'application/json',
      'Content-Type': 'application/json',
    },
  });
  const usage = status === 200 ? usageFromApi(body) : null;
  if (!usage) return { ok: false, status: `usage_http_${status}` };
  return { ok: true, usage };
}

async function validateCandidate(candidate) {
  let tokens = candidate.tokens;
  let usageResult = await fetchUsage(tokens);
  let refreshed = false;

  if (!usageResult.ok && tokens.refresh_token) {
    const refreshResult = await refreshTokens(tokens);
    if (!refreshResult.ok) {
      return { ...candidate, valid: false, status: refreshResult.status, error: refreshResult.error || '' };
    }
    tokens = refreshResult.tokens;
    refreshed = true;
    usageResult = await fetchUsage(tokens);
  }

  if (!usageResult.ok) {
    return { ...candidate, valid: false, status: usageResult.status, error: '' };
  }

  const accessClaims = jwtPayload(tokens.access_token);
  const idClaims = jwtPayload(tokens.id_token);
  const authClaims = accessClaims['https://api.openai.com/auth'] || idClaims['https://api.openai.com/auth'] || {};
  const profileClaims = accessClaims['https://api.openai.com/profile'] || {};
  const accountId = tokens.account_id || authClaims.chatgpt_account_id || '';
  const userId = candidate.hints.chatgpt_user_id || authClaims.chatgpt_user_id || authClaims.user_id || '';
  const email = candidate.email || profileClaims.email || idClaims.email || '';

  if (!accountId || !userId || !email) {
    return { ...candidate, valid: false, status: 'missing_identity', error: `account_id=${Boolean(accountId)} user_id=${Boolean(userId)} email=${Boolean(email)}` };
  }

  return {
    ...candidate,
    valid: true,
    status: refreshed ? 'ok_refreshed' : 'ok',
    email,
    tokens: { ...tokens, account_id: accountId },
    usage: usageResult.usage,
    chatgpt_account_id: accountId,
    chatgpt_user_id: userId,
    account_key: `${userId}::${accountId}`,
    plan: lower(usageResult.usage.plan_type || authClaims.chatgpt_plan_type || 'unknown'),
  };
}

function loadRegistry() {
  if (!fs.existsSync(REGISTRY_FILE)) {
    return {
      schema_version: 1,
      api: {},
      auto_switch: {},
      active_account_key: '',
      accounts: [],
    };
  }
  return readJson(REGISTRY_FILE);
}

function upsertAccounts(registry, validAccounts) {
  const now = Math.floor(Date.now() / 1000);
  const byKey = new Map((registry.accounts || []).map((a) => [a.account_key, a]));
  for (const account of validAccounts) {
    const previous = byKey.get(account.account_key) || {};
    byKey.set(account.account_key, {
      ...previous,
      account_key: account.account_key,
      chatgpt_account_id: account.chatgpt_account_id,
      chatgpt_user_id: account.chatgpt_user_id,
      email: account.email,
      alias: previous.alias || '',
      account_name: previous.account_name ?? account.account_name ?? null,
      plan: account.plan,
      auth_mode: 'chatgpt',
      created_at: previous.created_at || now,
      last_used_at: previous.last_used_at || 0,
      last_usage: account.usage,
      last_usage_at: now,
    });
  }
  registry.accounts = Array.from(byKey.values()).sort((a, b) => String(a.email).localeCompare(String(b.email)));
  if (!registry.active_account_key && registry.accounts[0]) {
    registry.active_account_key = registry.accounts[0].account_key;
  }
  return registry;
}

function writeInvalidSourceArchive(validAccounts, invalidAccounts) {
  if (dryRun || invalidAccounts.length === 0) return '';

  const validFiles = new Set(validAccounts.map((item) => item.file));
  const invalidFiles = new Map();
  for (const item of invalidAccounts) {
    if (!item.file || validFiles.has(item.file)) continue;
    if (!invalidFiles.has(item.file)) invalidFiles.set(item.file, []);
    invalidFiles.get(item.file).push(item);
  }

  if (invalidFiles.size === 0) return '';

  const archiveDir = path.join(INVALID_SOURCE_ROOT, `invalid-import-${timestamp()}`);
  const sourceDir = path.join(archiveDir, 'source-files');
  fs.mkdirSync(sourceDir, { recursive: true });

  const archivedFiles = [];
  for (const [file, items] of invalidFiles.entries()) {
    const firstEmail = items.find((item) => item.email)?.email || path.basename(file);
    const dest = path.join(sourceDir, `${safeFileName(firstEmail)}__${safeFileName(path.basename(file))}`);
    try {
      fs.copyFileSync(file, dest);
      archivedFiles.push({ source_file: file, archived_file: dest, candidates: items.length });
    } catch (error) {
      archivedFiles.push({ source_file: file, archived_file: '', copy_error: error.message, candidates: items.length });
    }
  }

  const report = {
    archived_at: new Date().toISOString(),
    invalid_source_root: INVALID_SOURCE_ROOT,
    invalid_file_count: invalidFiles.size,
    invalid_candidate_count: invalidAccounts.length,
    archived_files: archivedFiles,
    invalid: invalidAccounts.map((item) => ({
      email: item.email || '',
      status: item.status,
      error: item.error || '',
      source_file: item.file,
    })),
  };
  fs.writeFileSync(path.join(archiveDir, 'invalid-candidates.json'), `${JSON.stringify(report, null, 2)}\n`);
  fs.writeFileSync(path.join(archiveDir, 'README.md'), [
    '# Invalid Codex Auth Sources',
    '',
    `Archived at: ${report.archived_at}`,
    '',
    'These source JSON files were rejected by live validation and were not imported into the active account pool.',
    'Keep them isolated here for traceability; do not re-import unless fresh credentials are obtained.',
    '',
    `Invalid files: ${invalidFiles.size}`,
    `Invalid candidates: ${invalidAccounts.length}`,
    '',
  ].join('\n'));
  return archiveDir;
}

const candidates = [];
for (const file of inputFiles) {
  if (!fs.existsSync(file)) {
    console.error(`missing file: ${file}`);
    process.exitCode = 1;
    continue;
  }
  try {
    candidates.push(...candidatesFromFile(file));
  } catch (error) {
    candidates.push({ file, valid: false, status: 'invalid_json', error: error.message, email: '' });
  }
}

const validated = [];
for (const candidate of candidates) {
  if (candidate.valid === false) validated.push(candidate);
  else validated.push(await validateCandidate(candidate));
}

const validAccountsBeforeFilter = validated.filter((item) => item.valid);
const skippedAccounts = [];
const validAccounts = validAccountsBeforeFilter.filter((item) => {
  if (!onlyPlan) return true;
  const keep = lower(item.plan) === onlyPlan;
  if (!keep) {
    skippedAccounts.push({ ...item, skipped_reason: `plan_not_${onlyPlan}` });
  }
  return keep;
});
const invalidAccounts = validated.filter((item) => !item.valid);
const invalidArchiveDir = writeInvalidSourceArchive(validAccounts, invalidAccounts);

if (!dryRun && validAccounts.length > 0) {
  if (!yes && process.stdin.isTTY) {
    console.error('refusing to write without --yes');
    process.exit(1);
  }
  fs.mkdirSync(ACCOUNTS_DIR, { recursive: true });
  const registry = upsertAccounts(loadRegistry(), validAccounts);
  for (const account of validAccounts) {
    fs.writeFileSync(accountFileForKey(account.account_key), `${JSON.stringify(authPayload(account.tokens), null, 2)}\n`);
    if (registry.active_account_key === account.account_key) {
      fs.writeFileSync(ACTIVE_AUTH_FILE, `${JSON.stringify(authPayload(account.tokens), null, 2)}\n`);
    }
  }
  const tmp = `${REGISTRY_FILE}.tmp.${process.pid}`;
  fs.writeFileSync(tmp, `${JSON.stringify(registry, null, 2)}\n`);
  fs.renameSync(tmp, REGISTRY_FILE);
}

console.log(JSON.stringify({
  status: 'ok',
  dry_run: dryRun,
  only_plan: onlyPlan || null,
  imported_count: dryRun ? 0 : validAccounts.length,
  valid_count: validAccounts.length,
  valid_before_filter_count: validAccountsBeforeFilter.length,
  skipped_count: skippedAccounts.length,
  invalid_count: invalidAccounts.length,
  invalid_archive_dir: invalidArchiveDir,
  valid: validAccounts.map((item) => ({
    email: item.email,
    plan: item.plan,
    status: item.status,
    fiveh_remaining: 100 - item.usage.primary.used_percent,
    weekly_remaining: item.usage.secondary.present && item.usage.secondary.used_percent != null ? 100 - item.usage.secondary.used_percent : null,
    weekly_limit_present: item.usage.secondary.present,
    source_file: item.file,
  })),
  skipped: skippedAccounts.map((item) => ({
    email: item.email,
    plan: item.plan,
    status: item.status,
    skipped_reason: item.skipped_reason,
    source_file: item.file,
  })),
  invalid: invalidAccounts.map((item) => ({
    email: item.email || '',
    status: item.status,
    error: item.error || '',
    source_file: item.file,
  })),
}, null, 2));
