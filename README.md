# Codex.app Account Switcher / Codex 桌面端账号切换器

[![CI](https://github.com/tytsxai/codex-app-account-switcher/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/tytsxai/codex-app-account-switcher/actions/workflows/ci.yml)

Codex.app Account Switcher（Codex 桌面端账号切换器）是一个面向 macOS 的本地 CLI 与 Finder 启动器。它帮助已经使用 `codex-auth` 或本地 ChatGPT/Codex 登录快照的用户，按实时可用额度选择账号，写入 `~/.codex/auth.json`，并可自动重启 Codex.app 让桌面端读取新的登录状态。

> Unofficial local helper for Codex.app account pool switching. This project is not an OpenAI product and only works with user-owned local auth snapshots.

## 搜索摘要 / Search Summary

| Field | Value |
| --- | --- |
| Project name | Codex.app Account Switcher / Codex 桌面端账号切换器 |
| Project type | macOS local developer tool, CLI, Finder launcher, account-pool switcher |
| Core purpose | Switch the active Codex.app local auth snapshot after live ChatGPT/Codex usage validation |
| Primary users | macOS developers, Codex.app power users, users maintaining multiple self-owned Codex / ChatGPT auth snapshots |
| Tech stack | Bash, Node.js ESM, `jq`, `curl`, macOS `open` / `osascript` |
| Main paths | `~/.codex/auth.json`, `~/.codex/accounts/registry.json`, `~/.codex/accounts/*.auth.json` |
| Repository | `tytsxai/codex-app-account-switcher` |

## 项目定位 / Overview

- **项目是什么 / What it is**：一个 Bash + Node.js 编写的 macOS 本地 CLI/启动器，用于管理 Codex.app 的本地登录快照和账号切换流程。
- **解决什么问题**：当用户自己维护多个 Codex / ChatGPT 登录快照时，手动判断哪个账号还有 Codex 额度、复制 `auth.json`、重启 App 容易出错；本项目把实时校验、切换、重启和自检串成一个可重复流程。
- **适合谁使用 / Best for**：已经理解 `~/.codex` 本地认证文件、拥有多个自有账号快照、希望在个人 Mac 上更稳妥切换 Codex.app 登录状态的开发者或重度 Codex 用户。
- **不适合谁使用 / Not for**：没有本地 auth 快照、不了解令牌风险、希望绕过服务限制、希望托管账号或共享账号的人。
- **技术栈 / Tech stack**：Bash, Node.js ESM, `jq`, `curl`, macOS `open` / `osascript`, GitHub raw/codeload updater.

## 30 秒判断 / 30-Second Fit

如果你只想知道这个项目是否适合你：

- 你在 macOS 上使用 `/Applications/Codex.app`，并且已经有多个自己账号的本地 auth 快照。
- 你想先实时检查 ChatGPT/Codex usage，再把可用账号写入 `~/.codex/auth.json`。
- 你需要 `codex-account-switch --dry-run` 预演、`codex-account-switch --relaunch` 切换并重启 App，并用 `./codex-auth-smart-switch.sh --cleanup-unusable` 清理确定不可用的本地快照。
- 你接受这是一个 unofficial local helper，不是 OpenAI 官方 API、不是账号服务、不是额度绕过工具。

## 核心功能 / Key Features

- 实时读取 ChatGPT/Codex usage API，只选择当前可读且额度达标的账号。
- 默认优先 Free 账号的 5h/Codex 可用额度，Plus/Pro/Team/Business 可作为后备。
- 写入前后校验 `~/.codex/auth.json`，降低“registry 显示已切换但实际文件未变”的风险。
- 支持导入 `codex-auth`、`codex-sub2api` 或扁平 token JSON，并只写入实时验证成功的账号。
- 支持 `--dry-run` 预演、`--switch-only` 只切换、`--relaunch` 切换后重启 Codex.app。
- 提供本地安装器、桌面 `.command` 启动器、更新检查、自更新和发版前自检。
- 清理不可用账号时保留归档，不直接删除无法确定的网络失败或临时 usage 失败账号。

## 快速开始 / Quick Start

### 1. 安装依赖

本项目只面向 macOS。运行前需要：

- `/Applications/Codex.app`
- `jq`
- `node`
- `curl`
- `tar`
- 可选：`codex-auth`，用于生成或维护本地登录快照

可用 Homebrew 安装基础依赖：

```bash
brew install jq node
```

### 2. 安装本工具

```bash
repo="tytsxai/codex-app-account-switcher" \
  && sha="$(curl -fsSL "https://api.github.com/repos/$repo/commits/main" | jq -r '.sha')" \
  && tmp="$(mktemp -d)" \
  && curl -fsSL "https://codeload.github.com/$repo/tar.gz/$sha" \
  | tar -xz -C "$tmp" --strip-components 1 \
  && SOURCE_REVISION="$sha" bash "$tmp/scripts/install.sh"
```

安装器会部署到：

- App files: `~/.local/share/codex-app-account-switcher`
- CLI: `~/.local/bin/codex-account-switch`
- Desktop launcher: `~/Desktop/启动Codex换号.command`

如果 `~/.local/bin` 不在 `PATH` 中，把下面这行加入 shell 配置：

```bash
export PATH="$HOME/.local/bin:$PATH"
```

### 3. 首次配置账号池

1. 使用你自己的账号完成至少一次 `codex-auth` 登录，或准备已有的本地 auth JSON 快照。
2. 把额外来源文件放在私有目录，例如 `~/.codex/account-sources`。
3. 先用 dry run 导入候选账号：

```bash
mkdir -p "$HOME/.codex/account-sources"
APP_DIR="$HOME/.local/share/codex-app-account-switcher"
"$APP_DIR/codex-auth-import-json.mjs" --dry-run "$HOME/.codex/account-sources/source.json"
```

从源码仓库直接运行时使用：

```bash
./codex-auth-import-json.mjs --dry-run "$HOME/.codex/account-sources/source.json"
./codex-auth-import-json.mjs --yes "$HOME/.codex/account-sources/source.json"
```

安装后脚本位于：

```bash
"$HOME/.local/share/codex-app-account-switcher/codex-auth-import-json.mjs" --dry-run "$HOME/.codex/account-sources/source.json"
"$HOME/.local/share/codex-app-account-switcher/codex-auth-import-json.mjs" --yes "$HOME/.codex/account-sources/source.json"
```

Team/Business 账号必须来自完整登录快照，至少包含 `refresh_token`。只有 `access_token` 的导出最多只能临时读取 usage，不能作为可切换账号写入 `~/.codex/auth.json`。

Import dry run 不刷新 token、不写账号池；如果候选账号必须刷新 token 才能验证，会返回 `dry_run_refresh_required`，确认来源无误后再用 `--yes` 做真实导入。

### 4. 预演并切换

```bash
codex-account-switch --dry-run
codex-account-switch --relaunch
```

`--dry-run` 不切换 active auth，也不重启 Codex.app。为了避免 refresh token 轮换后本地快照失效，switcher 在实时校验时可能会保存刷新后的账号快照；`--relaunch` 会切换 `~/.codex/auth.json` 并重启 Codex.app。

## 常用命令 / Common Commands

```bash
# 交互启动器
codex-account-switch

# 只预演，不切换 active auth / 不重启
codex-account-switch --dry-run

# 切换账号并重启 Codex.app
codex-account-switch --relaunch

# 只切换 auth，不重启 App
codex-account-switch --switch-only

# 指定账号或排除套餐
codex-account-switch --force-email you@example.com --switch-only
codex-account-switch --exclude-plan plus --dry-run

# 检查更新、自更新、查看版本
codex-account-switch --check-updates
codex-account-switch --self-update
codex-account-switch --update-upstreams
codex-account-switch --version
```

源码仓库中的维护命令：

```bash
./codex-auth-smart-switch.sh --cleanup-unusable --dry-run
./codex-auth-smart-switch.sh --cleanup-unusable --yes
./codex-auth-import-json.mjs --dry-run ./path/to/source.json
./codex-auth-load-free.mjs --dry-run
./codex-auth-load-free.mjs --yes
./codex-auth-load-free.mjs --all-plans --yes
```

## 使用场景 / Use Cases

- 个人 Mac 上维护多个自有 Codex / ChatGPT 登录快照，希望减少手动复制 `auth.json` 的风险。
- 在 Codex.app 出现额度不足或账号不可用时，快速预览账号池并切到仍有可用额度的账号。
- 导入新的 auth JSON 来源前，先做实时 usage 校验，避免把无效、过期或身份信息不完整的账号写入 registry。
- 定期清理确定不可用的本地账号快照，同时保留删除前归档用于追溯。
- 在开源仓库中保留一个不含凭证的、可复现的本地账号切换流程。

## 适用关键词 / Search Keywords

Codex.app account switcher, Codex desktop account switching, ChatGPT auth snapshot, Codex auth.json switcher, macOS Codex CLI helper, local auth management, `codex-auth` workflow, Bash Node.js developer tool, Codex.app relaunch helper, AI coding account pool.

## 配置 / Configuration

常用环境变量：

| Variable | Default | Purpose |
| --- | --- | --- |
| `CODEX_HOME` | `~/.codex` | 账号池和活动 auth 文件根目录 |
| `MIN_5H_REMAIN` | `10` | 5h 窗口最低剩余百分比 |
| `MIN_WEEKLY_REMAIN` | `5` | 存在 weekly 窗口时的最低剩余百分比 |
| `USABLE_PLANS` | `free,plus,pro,team,business` | 允许自动选择或导入的套餐 |
| `POOL_PREVIEW_LIMIT` | `0` | 账号池预览数量，`0` 表示不限 |
| `MAX_PARALLEL_REFRESH` | `4` | 并发刷新账号 usage 的数量 |
| `CODEX_APP_BUNDLE_ID` | `com.openai.codex` | Codex.app bundle id |

示例：

```bash
MIN_5H_REMAIN=20 USABLE_PLANS=free,plus codex-account-switch --dry-run
CODEX_HOME="$HOME/.codex-test" codex-account-switch --dry-run
```

## 项目边界与注意事项 / Limitations

- 本项目不会提供、生成或托管任何账号；所有凭证都必须来自你自己的本地文件。
- 本项目不会绕过 OpenAI、ChatGPT 或 Codex 的服务限制，只会在你本地已有账号快照中选择实时可用账号。
- usage、refresh 和 Codex.app 行为依赖非官方本地流程和相关 Web 端点，未来可能因上游变化而失效。
- 缺少 `refresh_token` 的 access-only 来源会被诊断为 `missing_refresh_token` / `no_refresh_token`，不会参与自动切换。
- 运行 `--relaunch` 会尝试关闭并重新打开 Codex.app；如果脚本检测到自己运行在 Codex.app 内部，会拒绝自动关闭当前会话。
- 清理命令只删除确定性不可用状态，例如 auth 失败、缺少快照、缺少 refresh token 或套餐不在 `USABLE_PLANS`；网络失败不会自动删除。
- 不要把 `~/.codex/auth.json`、`~/.codex/accounts/`、`*.auth.json`、来源 JSON 或归档文件提交到公开仓库。

## 文档 / Documentation

- [docs/README.md](docs/README.md): documentation index and handoff reading order
- [docs/architecture.md](docs/architecture.md): architecture, runtime data model, import/selection/relaunch flows
- [docs/deployment.md](docs/deployment.md): local macOS deployment, update, uninstall, container/server boundaries
- [docs/configuration.md](docs/configuration.md): environment variables, thresholds, paths, network and relaunch settings
- [docs/modules.md](docs/modules.md): key scripts, responsibilities, core logic and extension points
- [docs/operations.md](docs/operations.md): daily operations, import, cleanup, update, troubleshooting
- [docs/troubleshooting.md](docs/troubleshooting.md): common failure modes and operational diagnostics
- [docs/maintenance.md](docs/maintenance.md): maintainer handoff, OpenSpec workflow, validation and release checklist
- [docs/security.md](docs/security.md): credential boundaries and public-repo safety
- [docs/usage-examples.md](docs/usage-examples.md): practical command examples
- [docs/faq.md](docs/faq.md): common questions and project limitations
- [openspec/project.md](openspec/project.md): project OpenSpec context and local SDD baseline
- [llms.txt](llms.txt): AI-search-friendly project summary

## 开发与自检 / Development

```bash
./check.sh
NETWORK_CHECKS=1 ./check.sh
scripts/install.sh --dry-run
scripts/check-updates.sh --self-test
scripts/check-updates.sh --json
```

`./check.sh` 默认只执行可离线复现的门禁：shell 语法、Node.js 语法、账号选择 fixture、可选 shellcheck、依赖工具和常见密钥泄露模式。联网更新链路容易受 GitHub/npm 临时网络影响，发版前需要额外设置 `NETWORK_CHECKS=1` 才会纳入硬门禁。

## 卸载 / Uninstall

```bash
rm -rf "$HOME/.local/share/codex-app-account-switcher"
rm -f "$HOME/.local/bin/codex-account-switch"
rm -f "$HOME/Desktop/启动Codex换号.command"
```

这不会删除 `~/.codex/accounts` 或 `~/.codex/auth.json`。

## 更新 / Keeping It Updated

```bash
codex-account-switch --check-updates
codex-account-switch --self-update
codex-account-switch --update-upstreams
```

自更新会替换安装目录中的脚本和文档，并优先跟踪安装时记录的 `.install-source` / `.install-branch`，不会因为默认配置把 fork 或对应开源项目切回错误仓库；它也不会主动删除你的 `~/.codex` 账号池。`--update-upstreams` 用于更新频繁变化的上游工具，目前会在检查到 `codex-auth` 落后时通过 npm 更新检测到的上游包，默认是 `@loongphy/codex-auth@latest`。

更新检查会同时报告本仓库 revision、raw installer、codeload archive、本地 `codex-auth`、检测到的 npm 上游包、`Loongphy/codex-auth` GitHub 最新 release 和本地 Codex.app 版本。需要一次维护完成时可运行：

```bash
codex-account-switch --self-update --update-upstreams
```

## 推荐 GitHub Topics

`codex`, `codex-app`, `chatgpt`, `account-switcher`, `macos`, `cli`, `bash`, `nodejs`, `jq`, `developer-tools`, `local-first`, `auth-management`

## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=tytsxai/codex-app-account-switcher&type=Date)](https://star-history.com/#tytsxai/codex-app-account-switcher&Date)
