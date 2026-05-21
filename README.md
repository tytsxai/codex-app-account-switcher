# Codex.app Account Switcher

macOS 本机 Codex.app 账号池切换方案。它面向已经使用 `codex-auth` 管理多个自有 Codex / ChatGPT 登录快照的用户，自动选择实时可用账号，写入 `~/.codex/auth.json`，然后重启 Codex.app 让桌面端读取新账号。

> This is an unofficial local workflow helper. It is not an OpenAI product and it relies on user-owned local auth snapshots.

## What It Does

- 实时刷新账号池额度，只选择 usage API 可读且额度达标的账号。
- 默认优先使用仍有 5h/Codex 额度的 Free 账号，Plus/Pro/Team/Business 作为后备。
- 切换前后校验 `~/.codex/auth.json`，避免 registry 显示已切换但实际 auth 文件未变。
- 可导入 `codex-auth`、`codex-sub2api` 或扁平 token JSON，但只会写入实时校验通过的账号。
- 提供 macOS 启动器和命令行两种入口。

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/tytsxai/codex-app-account-switcher/main/scripts/install.sh | bash
```

安装器会部署到：

- App files: `~/.local/share/codex-app-account-switcher`
- CLI: `~/.local/bin/codex-account-switch`
- Optional launcher: `~/Desktop/启动Codex换号.command`

如果 `~/.local/bin` 不在 `PATH` 中，把下面这行加入 shell 配置：

```bash
export PATH="$HOME/.local/bin:$PATH"
```

## Usage

交互启动器：

```bash
codex-account-switch
```

直接切换并重启 Codex.app：

```bash
codex-account-switch --relaunch
```

只预演，不写入账号文件：

```bash
codex-account-switch --dry-run
```

只切换 auth，不重启 App：

```bash
codex-account-switch --switch-only
```

检查更新并自更新：

```bash
codex-account-switch --check-updates
codex-account-switch --self-update
codex-account-switch --version
```

维护账号池：

```bash
./codex-auth-smart-switch.sh --cleanup-unusable --dry-run
./codex-auth-smart-switch.sh --cleanup-unusable --yes
./codex-auth-import-json.mjs --dry-run ./path/to/source.json
./codex-auth-load-free.mjs --yes
```

## First Setup

1. Install `codex-auth` and finish at least one login with your own account.
2. Put any additional source JSON files in a private local folder such as `~/.codex/account-sources`.
3. Import candidates with `./codex-auth-import-json.mjs --dry-run <file...>` first.
4. Re-run with `--yes` only after the dry run shows live validation success.
5. Run `codex-account-switch --dry-run` to confirm the pool before switching.

The repository never ships real account files. All live credentials stay in your local `~/.codex` tree or in files you explicitly pass to the importer.

## Configuration

Common environment variables:

- `CODEX_HOME`: account pool root, default `~/.codex`.
- `MIN_5H_REMAIN`: minimum 5h remaining percentage, default `10`.
- `MIN_WEEKLY_REMAIN`: minimum weekly remaining percentage when a weekly window exists, default `5`.
- `USABLE_PLANS`: comma-separated allowed plans, default `free,plus,pro,team,business`.
- `POOL_PREVIEW_LIMIT`: account preview limit, default `0` for no limit.
- `MAX_PARALLEL_REFRESH`: concurrent refresh limit, default `4`.
- `CODEX_APP_BUNDLE_ID`: app bundle id, default `com.openai.codex`.

## Uninstall

```bash
rm -rf "$HOME/.local/share/codex-app-account-switcher"
rm -f "$HOME/.local/bin/codex-account-switch"
rm -f "$HOME/Desktop/启动Codex换号.command"
```

This does not delete `~/.codex/accounts` or `~/.codex/auth.json`.

## Keeping It Updated

This project is intentionally small and can be safely reinstalled in place. The updater replaces the installed scripts and docs, but does not touch your `~/.codex` account pool.

```bash
codex-account-switch --check-updates
codex-account-switch --self-update
```

The update checker also reports the local `codex-auth` version, npm's latest published `codex-auth` version, raw installer availability, and the local Codex.app version when available.

## Development

```bash
./check.sh
scripts/install.sh --dry-run
scripts/check-updates.sh
```

The self-check validates shell syntax, Node syntax, optional shellcheck, required local tools, and common secret-leak patterns.

## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=tytsxai/codex-app-account-switcher&type=Date)](https://star-history.com/#tytsxai/codex-app-account-switcher&Date)
