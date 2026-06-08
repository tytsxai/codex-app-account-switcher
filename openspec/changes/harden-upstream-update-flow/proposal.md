# Harden Upstream Update Flow

## Problem

The project already checks whether the installed switcher repository is current, but installs can track a fork or a corresponding upstream open-source project. The old wrapper always fell back to the default `REPO_SLUG` / `BRANCH` unless the user provided environment variables again, so self-update could drift away from the source that was originally installed.

There is also a separate upstream CLI dependency issue: the old update check treated `codex-auth` as the unscoped npm package `codex-auth`, while the active local command is installed from `@loongphy/codex-auth`. That can hide real dependency updates and make maintenance look complete even when the upstream CLI remains stale.

## Goals

- Persist and reuse the installed open-source project source and branch.
- Detect the actual installed `codex-auth` package name when possible.
- Check upstream `codex-auth` against npm and GitHub latest release signals.
- Provide an explicit command to update upstream CLI dependencies.
- Keep project self-update separate by default so it does not unexpectedly mutate the user's global npm environment.

## Non-Goals

- Replacing `codex-auth` account management.
- Automatically updating Codex.app itself.
- Introducing a background updater or daemon.
