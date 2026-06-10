# Design

## Shared Lock

All mutating account-state paths use the same directory lock:

```text
${CODEX_ACCOUNT_LOCK_DIR:-$CODEX_HOME/accounts/.codex-app-hot-switch.lock}
```

The lock is acquired with atomic `mkdir`. The owner writes both a legacy `pid` file and an `owner` metadata file. When an existing lock points at a live process, the operation fails closed. When the owner PID is gone, the stale lock is removed and recreated.

`codex-app-hot-switch.sh` keeps the lock across selection and relaunch orchestration, then exports:

- `CODEX_ACCOUNT_LOCK_DIR`
- `CODEX_ACCOUNT_LOCK_HELD`

The child switcher treats an exact `CODEX_ACCOUNT_LOCK_HELD` match as a parent-held lock and does not reacquire it.

## Import Safety

`codex-auth-import-json.mjs` acquires the shared lock before real validation and writes, because validation can rotate refresh tokens that must be persisted with the resulting account snapshot.

Interactive real imports now refuse to start without `--yes` before live validation, not after it. This avoids consuming refresh tokens and then aborting before persistence.

Importer `--dry-run` does not refresh tokens and does not acquire the account-state lock. It may read usage with an existing access token. If validation would require a token refresh, it reports `dry_run_refresh_required` and tells the user to rerun with `--yes`.

## Switch Dry-Run Semantics

The switcher may persist refreshed account snapshots during dry-run if live validation rotates tokens. This is intentionally allowed to avoid losing a rotated refresh token. Dry-run still does not switch the active account or relaunch Codex.app.

## Test Strategy

`tests/state-lock-fixtures.sh` covers:

- Direct switcher rejects a live lock.
- Direct switcher recovers a stale lock.
- Child switcher accepts a parent-held delegated lock.
- Real importer rejects a live lock.
- Importer dry-run does not require the lock.
