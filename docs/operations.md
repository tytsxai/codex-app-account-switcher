# Operations / 运维与日常使用

## Daily Switch

```bash
codex-account-switch --dry-run
codex-account-switch --relaunch
```

The first command previews the selected account and pool state without switching active auth or relaunching Codex.app. It can still persist refreshed account snapshots if live validation rotates tokens. The second command switches `~/.codex/auth.json` and restarts Codex.app.

日常建议先 dry run，确认账号池可用数量、选中账号、5h 剩余和 weekly 剩余后，再执行真实切换。

## Import Account Sources

Use a private local folder:

```bash
mkdir -p "$HOME/.codex/account-sources"
./codex-auth-import-json.mjs --dry-run "$HOME/.codex/account-sources/source.json"
./codex-auth-import-json.mjs --yes "$HOME/.codex/account-sources/source.json"
```

Only accounts with live readable usage are imported. Invalid source files are copied to `~/.codex/accounts-invalid-sources` for traceability.

Importer accepts:

- `codex-auth` auth snapshot JSON.
- `codex-sub2api` export JSON with an `accounts` array.
- Flat token JSON containing access/refresh/id token fields.

Run with `--dry-run` first. Import dry-run does not refresh tokens or write account state; if an account needs refresh to validate, it is reported as `dry_run_refresh_required`. Use `--yes` only after the source is trusted, because real validation may rotate refresh tokens and must persist them.

For Team/Business accounts, live usage alone is not enough. The source must include a `refresh_token` so Codex.app can keep the session usable after the switch. Access-only exports are reported as `missing_refresh_token` during import or `no_refresh_token` in the pool diagnostics and are not selected for switching.

## Load Free Accounts

```bash
./codex-auth-load-free.mjs --dry-run
./codex-auth-load-free.mjs --yes
./codex-auth-load-free.mjs --all-plans --yes
```

The loader scans common private local folders and normally forwards only Free candidates to the importer. Use `--all-plans` when you intentionally want to import Plus/Pro/Team/Business snapshots from the same local source folders.

Default scan roots include `~/Downloads`, `~/.codex/account-sources`, `~/Documents/codex-accounts`, `~/Documents/账号codex`, and related local archive folders. Use `--scan-all` only when local token claims are missing or stale, because it validates more files live.

## Cleanup

```bash
./codex-auth-smart-switch.sh --cleanup-unusable --dry-run
./codex-auth-smart-switch.sh --cleanup-unusable --yes
```

Network failures and temporary usage failures are not deleted automatically. Cleanup candidates must be auth failures, missing snapshots, missing refresh tokens, or plans outside `USABLE_PLANS`.

Cleanup archives are stored outside the active account pool so that a later account-pool cleanup does not remove the evidence trail.

## Updates

```bash
codex-account-switch --check-updates
codex-account-switch --self-update
codex-account-switch --update-upstreams
codex-account-switch --version
```

`--self-update` re-runs the installer against the installed GitHub source and overwrites the scripts under `~/.local/share/codex-app-account-switcher`. The installed source is recorded in `.install-source` and `.install-branch`, which prevents a fork or tracked upstream open-source project from silently falling back to the default repository. It does not delete or rewrite `~/.codex/accounts` unless you separately run account maintenance commands.

`--update-upstreams` updates frequently changing upstream tools, currently `codex-auth`, through npm when the checker reports an upstream update. It is separate from `--self-update` because it mutates the user's global npm package state. To run both in one maintenance pass:

```bash
codex-account-switch --self-update --update-upstreams
```

For automation:

```bash
scripts/check-updates.sh --json
scripts/check-updates.sh --fail-if-outdated
scripts/check-updates.sh --self-test
```

The checker covers this repository, the raw installer URL, the codeload archive, local `codex-auth`, the detected upstream npm package, GitHub latest release for `Loongphy/codex-auth`, and the installed Codex.app version. `--self-test` is offline and validates the portable version comparison used on macOS, without depending on GNU `sort -V`.

## Local Release Gate

```bash
./check.sh
NETWORK_CHECKS=1 ./check.sh
```

The default check is safe for offline CI and local maintenance: it validates shell syntax, Node.js syntax, account-selection fixtures, optional shellcheck, required local tools, and common secret-leak patterns. Set `NETWORK_CHECKS=1` before publishing a release or validating an installed copy against live GitHub/npm update paths.

## Installed Paths

Default installation paths:

- App files: `~/.local/share/codex-app-account-switcher`
- CLI wrapper: `~/.local/bin/codex-account-switch`
- Desktop launcher: `~/Desktop/启动Codex换号.command`

The installer copies scripts, docs, examples, `README.md`, `llms.txt`, `LICENSE`, and `VERSION`. It does not copy or create real auth snapshots.
It also copies `tests/` so the installed `check.sh` can run its offline fixture gate.

## Useful Environment Variables

- `CODEX_HOME`: account pool root, default `~/.codex`.
- `MIN_5H_REMAIN`: minimum 5h remaining percentage, default `10`.
- `MIN_WEEKLY_REMAIN`: minimum weekly remaining percentage, default `5`.
- `USABLE_PLANS`: allowed plans, default `free,plus,pro,team,business`.
- `MAX_PARALLEL_REFRESH`: live usage refresh concurrency, default `4`.
- `CODEX_APP_BUNDLE_ID`: default `com.openai.codex`.

## Troubleshooting

- Missing `jq` or `node`: install them before running the switcher.
- Codex.app does not restart: open `/Applications/Codex.app` manually and run `codex-account-switch --dry-run` again.
- No available accounts: import fresh source files or wait for quota reset.
- Source JSON rejected: obtain a fresh login/export; reused or invalidated refresh tokens should not be retried indefinitely.
- `inside_codex_host`: run the launcher from Finder or a normal terminal. The script refuses to close the Codex.app process that is currently executing the session.
- `target_unavailable`: the forced account or preloaded selection failed the final live check; run without `--force-email` or refresh the source account.
- `quit_timeout` or `launch_timeout`: account switching already completed, but app process handling was not fully confirmed. Manually reopen Codex.app and run a dry run again.
