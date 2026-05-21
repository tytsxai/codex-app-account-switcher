# Security / 安全边界

This repository must stay credential-free.

## Credential Boundary

- Do not commit real account JSON files.
- Do not commit `~/.codex/auth.json`, `~/.codex/accounts/`, `.auth.json` snapshots, source exports, or rejected source archives.
- Use `~/.codex/account-sources` or another private local folder for source JSON files.
- Rejected source files are archived under `~/.codex/accounts-invalid-sources` by default.
- Do not paste real tokens into GitHub Issues, Discussions, README examples, screenshots, logs, or AI prompts.

## Runtime Behavior

The scripts read and write only local user-owned auth files:

- `~/.codex/accounts/registry.json`
- `~/.codex/accounts/*.auth.json`
- `~/.codex/auth.json`

The import and switch scripts call ChatGPT/Codex-related web endpoints to refresh tokens and read usage. This is an unofficial workflow helper, not an OpenAI-supported API contract.

## What This Project Does Not Do

- It does not provide accounts, credentials, token sources, or hosted account pools.
- It does not bypass service limits.
- It does not run a remote server or upload your auth snapshots to this repository.
- It does not make invalid or reused refresh tokens valid again.

## Safe Source Handling

Recommended local layout:

```bash
mkdir -p "$HOME/.codex/account-sources"
chmod 700 "$HOME/.codex" "$HOME/.codex/account-sources"
```

Run imports with `--dry-run` first. If a source is rejected, get a fresh export instead of repeatedly retrying the same stale credential.

## Before Publishing

Run:

```bash
./check.sh
git status --short
git grep -nE 'outlook\.de|aka\.yeah|/Users/[^/]+|codex-auth账号文件|invalid-sources'
```

The final command should return no matches in committed public files.
