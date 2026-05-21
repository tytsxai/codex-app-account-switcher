# Security

This repository must stay credential-free.

## Credential Boundary

- Do not commit real account JSON files.
- Do not commit `~/.codex/auth.json`, `~/.codex/accounts/`, `.auth.json` snapshots, source exports, or rejected source archives.
- Use `~/.codex/account-sources` or another private local folder for source JSON files.
- Rejected source files are archived under `~/.codex/accounts-invalid-sources` by default.

## Runtime Behavior

The scripts read and write only local user-owned auth files:

- `~/.codex/accounts/registry.json`
- `~/.codex/accounts/*.auth.json`
- `~/.codex/auth.json`

The import and switch scripts call ChatGPT/Codex-related web endpoints to refresh tokens and read usage. This is an unofficial workflow helper, not an OpenAI-supported API contract.

## Before Publishing

Run:

```bash
./check.sh
git status --short
git grep -nE 'outlook\.de|aka\.yeah|/Users/[^/]+|codex-auth账号文件|invalid-sources'
```

The final command should return no matches in committed public files.
