# Harden Account State Locking

## Problem

The account pool can be mutated from multiple entrypoints:

- `codex-app-hot-switch.sh` through the desktop launcher or CLI wrapper.
- `codex-auth-smart-switch.sh` when run directly.
- `codex-auth-import-json.mjs` and `codex-auth-load-free.mjs` during imports.

Before this change, only the hot-switch orchestration layer held a lock. Direct switcher runs and imports could still write `~/.codex/auth.json`, `~/.codex/accounts/registry.json`, or account snapshots while another operation was in progress. That creates a race where registry metadata and active auth can disagree.

There was also a dry-run semantics gap: switch dry-runs may persist refreshed account snapshots to avoid losing rotated refresh tokens, while importer dry-runs could attempt live refresh without persisting the rotated token.

## Goals

- Use one shared account-state lock for hot-switch, direct switcher, cleanup, and real imports.
- Let hot-switch delegate its already-held lock to the child switcher without deadlocking.
- Prevent importer dry-runs from refreshing tokens or writing account state.
- Refuse interactive real imports before live validation unless `--yes` is supplied.
- Add deterministic offline tests for lock behavior.
- Update docs so dry-run and locking behavior match the implementation.

## Non-Goals

- Introducing a daemon, database, or cross-user service.
- Changing account ranking rules.
- Changing the live usage API source of truth.
