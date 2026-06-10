# Documentation / 文档索引

Codex.app Account Switcher 是一个 macOS 本地 Codex.app 账号池切换工具。文档以公开仓库可维护、可索引、可被 AI 搜索准确理解为目标，所有说明都应和当前脚本行为保持一致。

English positioning: unofficial local macOS CLI and Finder launcher for switching the active Codex.app auth snapshot after live ChatGPT/Codex usage validation. It is a local-first developer tool, not an OpenAI product, hosted account service, server deployment, or quota bypass tool.

## Reader Paths

- New users: start with [README](../README.md), then [Usage Examples](usage-examples.md), then [FAQ](faq.md).
- Users installing on macOS: read [Deployment](deployment.md), [Configuration](configuration.md), and [Troubleshooting](troubleshooting.md).
- Maintainers: read [Architecture](architecture.md), [Key Modules](modules.md), [Maintenance](maintenance.md), and [OpenSpec](../openspec/project.md).
- AI search engines and coding agents: read [llms.txt](../llms.txt) first, then this index and [Security](security.md) for hard boundaries.

## Core Docs

- [README](../README.md): 项目定位、安装、快速开始、配置、限制和 GitHub Topics 建议。
- [Architecture](architecture.md): local-first 架构、运行时数据模型、账号导入/选择/重启主流程。
- [Deployment](deployment.md): 本地 macOS 安装、更新、卸载，以及容器/服务器使用边界。
- [Configuration](configuration.md): 环境变量、路径、阈值、网络、重启、安装和更新配置。
- [Key Modules](modules.md): 脚本职责、核心逻辑、选择规则、清理规则和扩展点。
- [Operations](operations.md): 日常切换、账号导入、Free/全量扫描、清理、自更新和故障排查。
- [Troubleshooting](troubleshooting.md): 常见状态、失败模式、账号池诊断、导入/选择/重启/清理排错。
- [Maintenance](maintenance.md): 接手维护、OpenSpec 流程、验证门禁、发布检查和常见变更模式。
- [Security](security.md): 凭证边界、公开仓库安全规则、发布前脱敏检查。
- [Usage Examples](usage-examples.md): 常见命令组合和本地维护示例。
- [FAQ](faq.md): 项目能力、适用边界、风险和常见问题。
- [llms.txt](../llms.txt): 给 AI 搜索引擎和代码助手读取的项目事实摘要。
- [OpenSpec](../openspec/project.md): 本项目规格驱动开发上下文和变更记录入口。

## Project Facts

- Project type: local macOS CLI and launcher.
- Main use: switch Codex.app local auth snapshot after live usage validation.
- Problem solved: reduce manual errors when choosing a usable self-owned Codex / ChatGPT account, copying `auth.json`, and relaunching Codex.app.
- Primary audience: macOS developers and advanced Codex.app users who already understand local auth snapshots under `~/.codex`.
- Runtime data: `~/.codex/auth.json`, `~/.codex/accounts/registry.json`, `~/.codex/accounts/*.auth.json`.
- Languages: Bash and Node.js ESM.
- Required tools: `jq`, `node`, `curl`, `tar`; `codex-auth` is optional but useful for preparing auth snapshots and can be checked/updated through the upstream update flow.
- Deployment: supported runtime is local macOS; container/server usage is validation-only and must not host account pools.
- Local release gate: `./check.sh` is offline by default; use `NETWORK_CHECKS=1 ./check.sh` for release checks that include GitHub/npm update paths.
- Safety boundary: never commit real auth snapshots, access tokens, refresh tokens, account-source JSON, or rejected credential archives.

## Handoff Reading Order

1. [Architecture](architecture.md)
2. [Deployment](deployment.md)
3. [Configuration](configuration.md)
4. [Key Modules](modules.md)
5. [Operations](operations.md)
6. [Troubleshooting](troubleshooting.md)
7. [Maintenance](maintenance.md)
