# Configuration / 配置说明

Configuration is intentionally environment-variable based. There is no project-level config file because the runtime state belongs to the current macOS user and must stay local.

## Core Paths

| Variable | Default | Used By | Purpose |
| --- | --- | --- | --- |
| `CODEX_HOME` | `~/.codex` | switcher, importer, launcher | Root for active auth, account registry, and account snapshots. |
| `INVALID_SOURCE_ROOT` | `$CODEX_HOME/accounts-invalid-sources` | importer | Archive root for rejected import source files. |
| `INVALID_ARCHIVE_ROOT` | `$CODEX_HOME/accounts-invalid-archive` | switcher cleanup | Archive root for cleaned account snapshots. |
| `INSTALL_DIR` | `~/.local/share/codex-app-account-switcher` | installer, update checker | Installed app files. |
| `BIN_DIR` | `~/.local/bin` | installer | CLI wrapper destination. |

Example:

```bash
CODEX_HOME="$HOME/.codex-test" codex-account-switch --dry-run
```

## Selection Thresholds

| Variable | Default | Purpose |
| --- | --- | --- |
| `MIN_5H_REMAIN` | `10` | Minimum remaining percentage for the primary 5h window. |
| `MIN_WEEKLY_REMAIN` | `5` | Minimum remaining percentage for weekly windows when present. |
| `USABLE_PLANS` | `free,plus,pro,team,business` | Live plans allowed for import cleanup and auto selection. |
| `SKIP_ACTIVE` | `1` | Skip current active account during normal selection unless `--include-active` or `--force-email` is used. |
| `POOL_PREVIEW_LIMIT` | `0` | Limit pool preview rows. `0` means no limit. |
| `SHOW_ALL_ACCOUNTS` | `0` | Launcher uses this for preloading diagnostics. |

Examples:

```bash
MIN_5H_REMAIN=20 USABLE_PLANS=free,plus codex-account-switch --dry-run
POOL_PREVIEW_LIMIT=5 codex-account-switch --dry-run
```

## Plan Weights

Pool-level remaining percentages are weighted by plan. These weights affect pool summary metrics, not the core Free-first ranking rule.

| Variable | Default |
| --- | --- |
| `PLAN_WEIGHT_FREE` | `1` |
| `PLAN_WEIGHT_PLUS` | `1` |
| `PLAN_WEIGHT_PRO` | `1` |
| `PLAN_WEIGHT_TEAM` | `1` |
| `PLAN_WEIGHT_BUSINESS` | `1` |
| `PLAN_WEIGHT_UNKNOWN` | `1` |

Example:

```bash
PLAN_WEIGHT_TEAM=3 PLAN_WEIGHT_BUSINESS=3 codex-account-switch --dry-run
```

## Network and Concurrency

| Variable | Default | Used By | Purpose |
| --- | --- | --- | --- |
| `MAX_PARALLEL_REFRESH` | `4` | switcher | Maximum concurrent account usage refresh tasks. |
| `CURL_CONNECT_TIMEOUT` | `4` | switcher, cleanup | Curl connection timeout in seconds. |
| `CURL_MAX_TIME` | `6` | switcher, cleanup | Curl total timeout in seconds. |
| `IMPORT_TIMEOUT_MS` | `8000` | importer | Node fetch timeout per import network call. |

Use lower concurrency if the network is unstable:

```bash
MAX_PARALLEL_REFRESH=2 CURL_MAX_TIME=10 codex-account-switch --dry-run
```

## Codex.app Relaunch

| Variable | Default | Purpose |
| --- | --- | --- |
| `CODEX_APP_BUNDLE_ID` | `com.openai.codex` | Bundle id used by `open -b` and AppleScript quit. |
| `WAIT_TIMEOUT` | `30` | General relaunch wait timeout in seconds. |
| `WAIT_INTERVAL` | `0.25` | Poll interval for process wait loops. |
| `GRACEFUL_WAIT_TIMEOUT` | `10` | Wait after AppleScript quit. |
| `TERM_WAIT_TIMEOUT` | `8` | Wait after `TERM` before `KILL`. |

Example:

```bash
WAIT_TIMEOUT=45 codex-account-switch --relaunch
```

## Import Loader

| Variable | Default | Purpose |
| --- | --- | --- |
| `FREE_IMPORT_SEARCH_DIRS` | built-in local folders | Colon-separated roots scanned by `codex-auth-load-free.mjs`. |

Default scan roots include `~/Downloads`, `~/.codex/account-sources`, `~/.Trash`, `~/Documents/codex-accounts`, `~/Documents/账号codex`, `~/.codex/accounts-invalid-archive`, and `~/.codex/accounts-backup*`.

Examples:

```bash
FREE_IMPORT_SEARCH_DIRS="$HOME/.codex/account-sources:$HOME/Documents/codex-accounts" ./codex-auth-load-free.mjs --dry-run
./codex-auth-load-free.mjs --all-plans --yes
```

## Installer and Update Checker

| Variable | Default | Purpose |
| --- | --- | --- |
| `REPO_SLUG` | `.install-source`, fallback `tytsxai/codex-app-account-switcher` | GitHub repo for install/update. |
| `BRANCH` | `.install-branch`, fallback `main` | Branch used by remote install/update checks. |
| `REPO_TARBALL_URL` | empty | Explicit source archive URL for installer. |
| `SOURCE_REVISION` | empty | Commit SHA recorded by installer for pre-downloaded source trees. |
| `CURRENT_REVISION` | `.install-revision` | Override current revision for update checks. |
| `CODEX_AUTH_PACKAGE` | detected, fallback `@loongphy/codex-auth` | npm package used for upstream `codex-auth` checks and updates. |
| `CODEX_AUTH_NPM_TAG` | `latest` | npm dist-tag used for upstream `codex-auth` updates. |
| `CODEX_AUTH_REPO_SLUG` | `Loongphy/codex-auth` | GitHub repo used for upstream `codex-auth` latest release checks. |
| `UPDATE_CONNECT_TIMEOUT` | `5` | Curl connect timeout in seconds for install/update GitHub checks. |
| `UPDATE_MAX_TIME` | `20` checker, `60` installer | Curl total timeout in seconds for install/update GitHub checks. |
| `NPM_VIEW_TIMEOUT` | `20` | Wall-clock timeout in seconds for npm version checks. |
| `NPM_FETCH_TIMEOUT_MS` | `60000` | npm fetch timeout for upstream package checks and updates. |
| `NETWORK_CHECKS` | `0` | Enables live GitHub/npm update checks in `check.sh`. |

## Operational Defaults

Recommended default command sequence:

```bash
codex-account-switch --dry-run
codex-account-switch --relaunch
```

Recommended import sequence:

```bash
./codex-auth-import-json.mjs --dry-run "$HOME/.codex/account-sources/source.json"
./codex-auth-import-json.mjs --yes "$HOME/.codex/account-sources/source.json"
```

Do not encode real credentials or private local paths into committed config examples.
