# Troubleshooting / 运维与排错指南

Start with the least destructive command:

```bash
codex-account-switch --dry-run
```

Use `--verbose` when diagnosing pool state:

```bash
codex-account-switch --dry-run --verbose
```

## Quick Diagnosis Matrix

| Symptom | Likely Cause | Action |
| --- | --- | --- |
| `registry not found` | No account pool has been imported. | Import a source JSON with `codex-auth-import-json.mjs --dry-run`, then `--yes`. |
| `missing required command: jq` | Missing local dependency. | `brew install jq node`. |
| `当前所有账号均无可用额度` | All accounts failed live usage, are below thresholds, or are excluded. | Run dry run verbose, check unavailable reasons, import fresh snapshots, or wait for reset. |
| `target_unavailable` | Forced/preloaded account failed final live gate. | Run without `--force-email`; refresh or re-import that source. |
| `stale_plan` | Preloaded selection was no longer live when switching. | Let hot switch fallback to real-time selection; investigate network if repeated. |
| `missing_refresh_token` | Source contains only access token. | Re-export a complete login snapshot with refresh token. |
| `no_refresh_token` | Existing pool snapshot cannot be refreshed. | Re-import complete snapshot; cleanup can remove it after confirmation. |
| `inside_codex_host` | Relaunch command is running inside Codex.app. | Use Finder launcher or system Terminal for `--relaunch`. |
| `quit_timeout` | Codex.app did not exit in time. | Close Codex.app manually, reopen, then dry run. |
| `launch_timeout` or `launch_failed` | macOS launch confirmation failed. | Open `/Applications/Codex.app` manually and validate current account. |

## Account Pool Inspection

Check registry shape without exposing tokens:

```bash
jq '.accounts[] | {email, plan, account_key, last_usage_at, last_used_at}' "$HOME/.codex/accounts/registry.json"
```

Check active key:

```bash
jq -r '.active_account_key // ""' "$HOME/.codex/accounts/registry.json"
```

Check active auth identity without printing tokens:

```bash
jq '{email, auth_mode, token_keys:(.tokens | keys)}' "$HOME/.codex/auth.json"
```

Do not paste token values into issues, docs, screenshots, or AI prompts.

## Import Problems

Dry run first:

```bash
./codex-auth-import-json.mjs --dry-run "$HOME/.codex/account-sources/source.json"
```

Common import statuses:

- `missing_refresh_token`: source is access-only and cannot be switched.
- `refresh_http_400`, `refresh_http_401`: refresh token is rejected.
- `usage_http_401`: access token failed and refresh did not produce usable usage.
- `missing_identity`: usage was readable but required identity fields are incomplete.
- `invalid_json`: file is not valid JSON.

Rejected files may be archived under `~/.codex/accounts-invalid-sources`. Do not re-import stale rejected files unless credentials were refreshed.

## Selection Problems

Run:

```bash
codex-account-switch --dry-run --verbose
```

Unavailable reasons:

- `cache`: registry had cached usage only; live API was not trusted.
- `api_failed`: usage refresh failed after token handling.
- `auth_failed`: refresh failed with deterministic auth failure.
- `no_refresh_token`: account snapshot cannot be refreshed.
- `low_5h`: 5h remaining is below `MIN_5H_REMAIN`.
- `low_weekly`: weekly remaining is below `MIN_WEEKLY_REMAIN`.
- `unusable_plan`: live plan is not in `USABLE_PLANS`.

Operational knobs:

```bash
MIN_5H_REMAIN=5 codex-account-switch --dry-run
MAX_PARALLEL_REFRESH=2 CURL_MAX_TIME=10 codex-account-switch --dry-run
USABLE_PLANS=free,plus,pro,team,business codex-account-switch --dry-run
```

Lower thresholds only if the operational goal accepts more frequent quota exhaustion after switching.

## Relaunch Problems

Check whether Codex.app is running:

```bash
ps -axo pid=,command= | grep '/Applications/Codex.app/Contents/MacOS/Codex' | grep -v grep
```

Dry-run relaunch:

```bash
./codex-app-relaunch.sh --dry-run --verbose
```

If relaunch fails after switching, the auth file may already be correct. Manually close and reopen Codex.app, then validate:

```bash
codex-account-switch --dry-run
```

## Cleanup Problems

Always inspect before deletion:

```bash
./codex-auth-smart-switch.sh --cleanup-unusable --dry-run
```

Confirm only when candidates are expected:

```bash
./codex-auth-smart-switch.sh --cleanup-unusable --yes
```

Cleanup archives include:

- `registry-before.json`
- `probe-results.json`
- `dead-accounts.json`
- copied auth snapshots
- manifest mapping account/email/status to archived files

Network failures are intentionally preserved.

## Update Problems

```bash
codex-account-switch --check-updates
scripts/check-updates.sh --json
scripts/check-updates.sh --self-test
```

If GitHub or npm is temporarily unreachable, local switching can still work. Treat update check failure as release-blocking only when `NETWORK_CHECKS=1 ./check.sh` is part of a release gate.

## Secret Leak Response

If real credentials were committed or shared:

1. Stop using the leaked snapshot.
2. Re-login or rotate credentials through the upstream auth flow.
3. Remove the secret from git history before publishing.
4. Run `./check.sh` and manually inspect docs, logs, screenshots, and examples.
