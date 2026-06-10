# Maintenance / 接手维护指南

This guide is for a maintainer who needs to change, release, or debug the project without prior context.

## First 15 Minutes

1. Read [architecture.md](architecture.md) for runtime boundaries.
2. Read [modules.md](modules.md) for file ownership and core logic.
3. Run the offline gate:

```bash
./check.sh
```

4. Inspect local changes before editing:

```bash
git status --short
git diff --stat
```

5. Never open or print real token files unless the task explicitly requires local private diagnosis.

## Development Rules

- Preserve local-first behavior. Do not add a server, hosted pool, telemetry, or remote credential upload.
- Keep Bash for macOS orchestration and Node.js ESM for structured JSON parsing/import logic.
- Keep side effects explicit: import dry-run must not refresh or write; switch dry-run must not switch active auth or relaunch, but may save refreshed account snapshots when live validation rotates tokens.
- Keep live usage as the selection source of truth.
- Do not clean network failures automatically.
- Update relevant docs under `docs/` whenever code behavior changes.
- For development tasks, create or update an OpenSpec change under `openspec/changes/<change-id>/`.

## OpenSpec Workflow

Project-local OpenSpec records live under `openspec/`.

Recommended flow:

```bash
mkdir -p openspec/changes/<change-id>
$EDITOR openspec/changes/<change-id>/proposal.md
$EDITOR openspec/changes/<change-id>/tasks.md
$EDITOR openspec/changes/<change-id>/design.md
```

Minimum expected files:

- `proposal.md`: problem, goals, non-goals, scope, acceptance criteria.
- `tasks.md`: implementation and validation checklist.
- `design.md`: required when behavior, data model, security boundary, or deployment changes are non-trivial.

After implementation, mark tasks complete and keep the docs/code behavior synchronized.

## Validation Gates

Local default:

```bash
./check.sh
```

Release gate:

```bash
NETWORK_CHECKS=1 ./check.sh
```

Installer validation:

```bash
scripts/install.sh --dry-run
scripts/check-updates.sh --self-test
scripts/check-updates.sh --json
```

Manual operational validation on a private Mac:

```bash
codex-account-switch --dry-run
codex-account-switch --switch-only
codex-account-switch --relaunch
```

Only run real switch commands against user-owned local credentials.

## Release Checklist

- `./check.sh` passes.
- `NETWORK_CHECKS=1 ./check.sh` passes for release branches/tags.
- `README.md`, `docs/`, and `llms.txt` match the current behavior.
- No real credentials or private account dumps are present.
- Installer copies any new required files.
- `VERSION` is updated when publishing a user-visible release.
- Update checker still reports meaningful status.

## Documentation Ownership

| Area | File |
| --- | --- |
| High-level onboarding | `README.md`, `docs/README.md` |
| Architecture and flows | `docs/architecture.md` |
| Deployment and install | `docs/deployment.md` |
| Environment variables | `docs/configuration.md` |
| Code/module ownership | `docs/modules.md` |
| Day-to-day operations | `docs/operations.md`, `docs/usage-examples.md` |
| Troubleshooting | `docs/troubleshooting.md`, `docs/faq.md` |
| Security boundaries | `docs/security.md` |
| AI/search summary | `llms.txt` |

When behavior changes, update the most specific document plus any index or README section that references it.

## Common Change Patterns

### Add a New Import Source Shape

- Update `candidatesFromFile()` in `codex-auth-import-json.mjs`.
- Preserve validation requirements: refresh token, live usage, email, user id, account id.
- Add examples or status notes in [usage-examples.md](usage-examples.md) and [troubleshooting.md](troubleshooting.md).
- Run `node --check codex-auth-import-json.mjs` and `./check.sh`.

### Change Selection Ranking

- Update jq ranking logic in `codex-auth-smart-switch.sh`.
- Update `tests/selection-fixtures.sh`.
- Update [modules.md](modules.md) ranking rules.
- Run `./check.sh`.

### Change Install Layout

- Update `scripts/install.sh`.
- Update [deployment.md](deployment.md), [README.md](../README.md), and [operations.md](operations.md).
- Verify `scripts/install.sh --dry-run` and local install.

### Change Relaunch Behavior

- Update `codex-app-relaunch.sh` or `codex-app-hot-switch.sh`.
- Preserve `inside_codex_host` safety.
- Update [troubleshooting.md](troubleshooting.md).
- Validate with `--dry-run` before any real relaunch.

## Operational Risk Notes

- Upstream auth and usage endpoints are not an official stable API contract.
- Refresh-token rotation can change local snapshots; avoid repeated experiments on important accounts.
- `--cleanup-unusable --yes` is intentionally conservative but still destructive after archive.
- Relaunch can close the user's current Codex.app session unless protected by `inside_codex_host`.
- Container/server environments are suitable for checks, not real switching.
