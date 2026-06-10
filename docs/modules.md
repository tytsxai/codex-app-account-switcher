# Key Modules / 关键模块与核心逻辑

This document maps each important file to its responsibility, dependencies, write targets, and maintenance notes.

## Runtime Scripts

| File | Responsibility | Writes |
| --- | --- | --- |
| `codex-app-hot-switch.sh` | Orchestrates account selection, switch, shared lock, and optional relaunch. | Lock directory under `~/.codex/accounts`. |
| `codex-auth-smart-switch.sh` | Core account refresh, ranking, switching, JSON summary, shared lock, and cleanup. | `~/.codex/auth.json`, `registry.json`, auth snapshots during refresh, cleanup archives. |
| `codex-app-relaunch.sh` | Safely restarts Codex.app after auth switch. | No project data writes. |
| `codex-auth-import-json.mjs` | Parses source JSON, refreshes tokens for real imports, validates live usage and identity, writes pool entries. | `registry.json`, `*.auth.json`, invalid source archives. |
| `codex-auth-load-free.mjs` | Scans local folders and forwards candidate files to the importer. | Delegates writes to importer. |
| `启动Codex换号.command` | Finder-friendly interactive launcher and maintenance menu. | Temp logs/plans, then delegates writes to scripts. |

## Supporting Scripts

| File | Responsibility |
| --- | --- |
| `scripts/install.sh` | Installs scripts, docs, examples, tests, CLI wrapper, launcher, and install metadata. |
| `scripts/check-updates.sh` | Checks repo revision, installer URLs, codeload archive, upstream `codex-auth` npm/GitHub versions, and Codex.app version. |
| `scripts/update-upstreams.sh` | Updates explicitly approved upstream tooling such as `@loongphy/codex-auth` through npm. |
| `check.sh` | Local release gate: syntax checks, fixture tests, optional shellcheck, dependency checks, update self-test, secret patterns. |
| `tests/selection-fixtures.sh` | Offline jq fixture for account availability, Free-first selection, exclusion, and stale-source diagnostics. |

## Core Logic Details

### Identity Key

The stable account key is:

```text
chatgpt_user_id::chatgpt_account_id
```

The auth snapshot file path is:

```text
~/.codex/accounts/<base64(account_key-without-padding)>.auth.json
```

When switching, the script normalizes:

- `.auth_mode = "chatgpt"`
- `.email`
- `.tokens.account_id`
- `.tokens.chatgpt_account_id`
- `.tokens.user_id`
- `.tokens.chatgpt_user_id`
- `.last_refresh` when missing

This prevents registry metadata and active auth identity from drifting.

### Import Validation

`codex-auth-import-json.mjs` accepts these source shapes:

- `codex-auth` auth snapshot JSON.
- `codex-sub2api` export JSON with an `accounts` array.
- Flat token JSON containing token fields.

A valid switchable account must have:

- `refresh_token`
- readable live usage
- email
- account id
- user id

`access_token`-only sources are rejected as `missing_refresh_token` because they cannot reliably become `~/.codex/auth.json` for Codex.app.

Importer `--dry-run` does not refresh tokens or write account state. If a candidate needs refresh to validate, it is reported as `dry_run_refresh_required`; real imports require `--yes` in interactive terminals before validation begins.

### Usage Refresh

`codex-auth-smart-switch.sh` checks each account through:

1. Existing `access_token` usage request.
2. One refresh-token rotation when usage fails or access token is missing.
3. Fallback diagnostic source only when live API usage cannot be read.

Only `source == "api"` can be selected. `cache`, `api_failed`, `auth_failed`, and `no_refresh_token` are diagnostics.

Switcher dry-runs do not switch active auth or relaunch Codex.app. They may still persist refreshed account snapshots if live validation rotates tokens; this prevents losing the new refresh token.

### Account-State Lock

Mutating entrypoints share `${CODEX_ACCOUNT_LOCK_DIR:-$CODEX_HOME/accounts/.codex-app-hot-switch.lock}`. Direct switcher runs, cleanup, hot-switch orchestration, and real imports fail closed when another live owner holds the lock. Hot-switch delegates the already-held lock to the child switcher through `CODEX_ACCOUNT_LOCK_HELD`.

### Availability Rules

Availability requires all of these:

- Fresh source: `source == "api"`.
- Live plan is in `USABLE_PLANS`.
- `fiveh_remaining >= MIN_5H_REMAIN`.
- If weekly window is present: `weekly_remaining >= MIN_WEEKLY_REMAIN`.

Plan exclusion with `--exclude-plan` removes plans from auto-selection but keeps them visible in pool diagnostics.

### Ranking Rules

The ranking block sorts by:

1. Available accounts before unavailable accounts.
2. Free plan before paid plans.
3. Higher combined weekly plus 5h remaining.
4. Higher weekly remaining.
5. Higher 5h remaining.
6. Newer live usage refresh.

Forced accounts still pass the same live availability gate.

### Cleanup Rules

`--cleanup-invalid` removes only deterministic invalid states:

- `auth_failed`
- `missing_file`
- `no_refresh_token`

`--cleanup-unusable` additionally removes live plans outside `USABLE_PLANS`.

It does not delete network failures, HTTP unknown states, or usage refresh failures. Archives are created before deletion.

## Change Guidelines

- Keep writes atomic: write temp file, then rename.
- Keep dry-run semantics explicit: import dry-run must not refresh or write; switch dry-run must not switch active auth or relaunch, but may save rotated account snapshots.
- Keep JSON output stable for launcher and automation.
- Add fixture coverage when ranking, filtering, stale-source handling, cleanup rules, or account-state locking changes.
- Update docs in the same change when behavior changes.
