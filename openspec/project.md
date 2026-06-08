# Project OpenSpec Context

## Purpose

Codex.app Account Switcher is a local macOS account-pool switching helper for Codex.app. It validates user-owned local auth snapshots against live usage, writes the selected snapshot to `~/.codex/auth.json`, and optionally restarts Codex.app.

## Constraints

- Runtime target is local macOS with `/Applications/Codex.app`.
- No remote account hosting, remote credential upload, server daemon, or multi-user service.
- The repository must remain credential-free.
- Live usage validation is the source of truth for account selection.
- Documentation under `docs/` must be updated with behavior changes.

## Specification Process

Development changes should create a folder under `openspec/changes/<change-id>/` with:

- `proposal.md`
- `tasks.md`
- `design.md` when the change touches architecture, security, deployment, or data model.

Emergency production fixes may patch first, but the OpenSpec record must be completed afterward.
