# Operations

## Daily Switch

```bash
codex-account-switch --dry-run
codex-account-switch --relaunch
```

The first command previews the selected account and pool state. The second command switches `~/.codex/auth.json` and restarts Codex.app.

## Import Account Sources

Use a private local folder:

```bash
mkdir -p "$HOME/.codex/account-sources"
./codex-auth-import-json.mjs --dry-run "$HOME/.codex/account-sources/source.json"
./codex-auth-import-json.mjs --yes "$HOME/.codex/account-sources/source.json"
```

Only accounts with live readable usage are imported. Invalid source files are copied to `~/.codex/accounts-invalid-sources` for traceability.

## Load Free Accounts

```bash
./codex-auth-load-free.mjs --dry-run
./codex-auth-load-free.mjs --yes
```

The loader scans common private local folders and only forwards Free candidates to the importer.

## Cleanup

```bash
./codex-auth-smart-switch.sh --cleanup-unusable --dry-run
./codex-auth-smart-switch.sh --cleanup-unusable --yes
```

Network failures and temporary usage failures are not deleted automatically. Cleanup candidates must be auth failures, missing snapshots, missing refresh tokens, or plans outside `USABLE_PLANS`.

## Updates

```bash
codex-account-switch --check-updates
codex-account-switch --self-update
codex-account-switch --version
```

`--self-update` re-runs the installer against the current GitHub `main` branch and overwrites the installed scripts under `~/.local/share/codex-app-account-switcher`. It does not delete or rewrite `~/.codex/accounts` unless you separately run account maintenance commands.

For automation:

```bash
scripts/check-updates.sh --json
scripts/check-updates.sh --fail-if-outdated
```

The checker covers this repository, the raw installer URL, the codeload archive, local `codex-auth`, npm's latest `codex-auth`, and the installed Codex.app version.

## Troubleshooting

- Missing `jq` or `node`: install them before running the switcher.
- Codex.app does not restart: open `/Applications/Codex.app` manually and run `codex-account-switch --dry-run` again.
- No available accounts: import fresh source files or wait for quota reset.
- Source JSON rejected: obtain a fresh login/export; reused or invalidated refresh tokens should not be retried indefinitely.
