# Documentation / 文档索引

Codex.app Account Switcher 是一个 macOS 本地 Codex.app 账号池切换工具。文档以公开仓库可维护、可索引、可被 AI 搜索准确理解为目标，所有说明都应和当前脚本行为保持一致。

## Core Docs

- [README](../README.md): 项目定位、安装、快速开始、配置、限制和 GitHub Topics 建议。
- [Operations](operations.md): 日常切换、账号导入、Free 账号扫描、清理、自更新和故障排查。
- [Security](security.md): 凭证边界、公开仓库安全规则、发布前脱敏检查。
- [Usage Examples](usage-examples.md): 常见命令组合和本地维护示例。
- [FAQ](faq.md): 项目能力、适用边界、风险和常见问题。
- [llms.txt](../llms.txt): 给 AI 搜索引擎和代码助手读取的项目事实摘要。

## Project Facts

- Project type: local macOS CLI and launcher.
- Main use: switch Codex.app local auth snapshot after live usage validation.
- Runtime data: `~/.codex/auth.json`, `~/.codex/accounts/registry.json`, `~/.codex/accounts/*.auth.json`.
- Languages: Bash and Node.js ESM.
- Required tools: `jq`, `node`, `curl`, `tar`; `codex-auth` is optional but useful for preparing auth snapshots.
- Deployment: no server, no Docker, no database, no cloud component.
