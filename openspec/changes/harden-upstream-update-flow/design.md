# Design

## Installed Source Tracking

The installer records:

- `.install-source`: the GitHub repository slug used by install/update.
- `.install-branch`: the Git branch used by install/update.
- `.install-revision`: the installed commit SHA when known.

The generated `codex-account-switch` wrapper exports `REPO_SLUG` and `BRANCH` from those metadata files before dispatching to `--check-updates` or `--self-update`, unless the user explicitly supplied environment overrides. `scripts/check-updates.sh` uses the same metadata fallback when run directly from an installed tree.

## Dependency Detection

`scripts/check-updates.sh` resolves the `codex-auth` command path and walks upward to find the owning `package.json`. If it finds a package that exposes `codex-auth` or has `codex-auth` in the package name, it uses that package name for npm checks. If detection fails, it falls back to `@loongphy/codex-auth`.

## Upstream Signals

The checker reports:

- local `codex-auth --version`
- npm version for `${CODEX_AUTH_PACKAGE}@${CODEX_AUTH_NPM_TAG}`
- GitHub latest release from `${CODEX_AUTH_REPO_SLUG}`
- synthesized latest version from the newest semver signal

Defaults:

- `CODEX_AUTH_PACKAGE=@loongphy/codex-auth` when detection fails
- `CODEX_AUTH_NPM_TAG=latest`
- `CODEX_AUTH_REPO_SLUG=Loongphy/codex-auth`
- GitHub/codeload curl calls use `UPDATE_CONNECT_TIMEOUT` and `UPDATE_MAX_TIME`
- npm version checks use `NPM_VIEW_TIMEOUT` as a wall-clock guard plus `NPM_FETCH_TIMEOUT_MS`

## Update Execution

`scripts/update-upstreams.sh` consumes the JSON output from `scripts/check-updates.sh` and runs:

```bash
npm install -g "${package}@${npm_tag}"
```

It only updates automatically when status is `update_available`. Missing installation requires `--install-missing`, and ambiguous states fail closed.

The installed wrapper exposes:

- `codex-account-switch --update-upstreams`
- `codex-account-switch --self-update --update-upstreams`

## Safety

Project self-update remains script/document replacement only. Upstream package updates are explicit because they mutate global npm state and may change upstream behavior independently from this repository.
