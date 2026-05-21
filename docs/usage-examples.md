# Usage Examples / 使用示例

These examples match the current repository scripts. Replace placeholder paths and emails with your own local values.

## Preview Account Pool

```bash
codex-account-switch --dry-run
```

Use this before every real switch. It prints the selected account, plan, 5h remaining percentage, weekly remaining state when available, and pool preview.

## Switch and Relaunch Codex.app

```bash
codex-account-switch --relaunch
```

This writes the selected auth snapshot to `~/.codex/auth.json`, verifies the file, then restarts `/Applications/Codex.app`.

## Switch Without Relaunch

```bash
codex-account-switch --switch-only
```

Use this when you want to control app restart manually.

## Force a Specific Account

```bash
codex-account-switch --force-email you@example.com --dry-run
codex-account-switch --force-email you@example.com --switch-only
```

The forced account is still validated live before any write. If usage cannot be read or quota is below threshold, the switch is rejected.

## Exclude a Plan From Auto Selection

```bash
codex-account-switch --exclude-plan plus --dry-run
codex-account-switch --exclude-plan plus --exclude-plan pro --relaunch
```

`--exclude-plan` affects automatic selection only. The pool preview can still show excluded accounts for diagnosis.

## Import Account Source JSON

```bash
mkdir -p "$HOME/.codex/account-sources"
./codex-auth-import-json.mjs --dry-run "$HOME/.codex/account-sources/source.json"
./codex-auth-import-json.mjs --yes "$HOME/.codex/account-sources/source.json"
```

Supported source shapes include `codex-auth` snapshots, `codex-sub2api` exports, and flat token JSON. The importer writes only accounts that pass live identity and usage checks.

## Load Free Candidates From Local Folders

```bash
./codex-auth-load-free.mjs --dry-run
./codex-auth-load-free.mjs --yes
```

The loader locally prefilters files that declare `chatgpt_plan_type=free`, then forwards them to the importer with `--only-plan free`.

## Cleanup Unusable Accounts

```bash
./codex-auth-smart-switch.sh --cleanup-unusable --dry-run
./codex-auth-smart-switch.sh --cleanup-unusable --yes
```

Run dry run first. Cleanup removes only deterministic unusable states and keeps an archive under the configured invalid archive root.

## Check and Update Installation

```bash
codex-account-switch --check-updates
codex-account-switch --self-update
codex-account-switch --version
```

Self-update replaces installed scripts and docs under `~/.local/share/codex-app-account-switcher`. It does not delete `~/.codex/accounts` or `~/.codex/auth.json`.
