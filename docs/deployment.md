# Deployment / 部署方式

The supported deployment target is a single macOS user account running Codex.app locally. Container and server deployment are documented only as maintenance/build patterns; they are not supported for real account switching because they cannot safely operate `/Applications/Codex.app` or the user's live `~/.codex/auth.json`.

## Local macOS Deployment

### Prerequisites

- macOS with `/Applications/Codex.app`.
- `jq`, `node`, `curl`, `tar`.
- Optional: `codex-auth` for preparing local login snapshots.
- A private `~/.codex` directory containing user-owned auth snapshots.

Install prerequisites with Homebrew:

```bash
brew install jq node
```

### Install From GitHub

```bash
repo="tytsxai/codex-app-account-switcher" \
  && sha="$(curl -fsSL "https://api.github.com/repos/$repo/commits/main" | jq -r '.sha')" \
  && tmp="$(mktemp -d)" \
  && curl -fsSL "https://codeload.github.com/$repo/tar.gz/$sha" \
  | tar -xz -C "$tmp" --strip-components 1 \
  && SOURCE_REVISION="$sha" bash "$tmp/scripts/install.sh"
```

Default installed paths:

- App files: `~/.local/share/codex-app-account-switcher`
- CLI wrapper: `~/.local/bin/codex-account-switch`
- Finder launcher: `~/Desktop/启动Codex换号.command`
- Install metadata: `.install-revision`, `.install-source`, and `.install-branch` in the app files directory.

Add this to the shell profile when needed:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

### Install From Local Checkout

```bash
./scripts/install.sh
./scripts/install.sh --dry-run
./scripts/install.sh --install-dir "$HOME/.local/share/codex-app-account-switcher" --bin-dir "$HOME/.local/bin"
```

Use local install during development when validating installer behavior without waiting for a remote release.

### Upgrade

```bash
codex-account-switch --check-updates
codex-account-switch --self-update
codex-account-switch --update-upstreams
```

Self-update replaces installed scripts, docs, examples, tests, and metadata under the install directory. It reads `.install-source` and `.install-branch` first, so an install from a fork or upstream open-source repo keeps tracking that same source unless `REPO_SLUG` or `BRANCH` is explicitly overridden. It does not delete or rewrite `~/.codex/accounts` or `~/.codex/auth.json`.

Upstream updates are explicit. `codex-account-switch --update-upstreams` updates frequently changing upstream tooling such as `@loongphy/codex-auth` through npm after checking the detected local package, npm `latest`, and the GitHub latest release. Use `codex-account-switch --self-update --update-upstreams` when you want to update this repository and the upstream CLI in one maintenance command.

### Rollback

There is no built-in versioned rollback. Use one of these operational rollback paths:

- Reinstall from a known commit tarball by setting `REPO_TARBALL_URL` or `SOURCE_REVISION` when running `scripts/install.sh`.
- Restore the previous install directory from backup if one was taken.
- For account state rollback, copy a known-good auth snapshot back to `~/.codex/auth.json` and then reopen Codex.app.

## Container Deployment

Container deployment is not supported for real switching. Reasons:

- Codex.app is a macOS GUI app under `/Applications/Codex.app`.
- Relaunch depends on macOS `open`, process inspection, and optional AppleScript.
- Real auth files live under the user's local `~/.codex` and must not be copied into images.

Allowed container use is limited to source validation:

```bash
docker run --rm -v "$PWD:/work" -w /work node:22-bookworm bash -lc '
  apt-get update >/dev/null && apt-get install -y jq shellcheck >/dev/null
  ./check.sh
'
```

Do not mount a real `~/.codex` into a shared or remote container. If a CI container needs tests, use fixtures only.

## Server Deployment

Server deployment is not supported for production use. This project has no server process, HTTP interface, daemon, database migration, or multi-user isolation layer.

Permitted server-side usage:

- CI running `./check.sh`.
- Release automation running `NETWORK_CHECKS=1 ./check.sh`.
- Static documentation or source mirror hosting.

Not permitted:

- Hosting account pools.
- Uploading user auth snapshots.
- Running switch commands against another user's `~/.codex`.
- Exposing switching as an API.

## Uninstall

```bash
rm -rf "$HOME/.local/share/codex-app-account-switcher"
rm -f "$HOME/.local/bin/codex-account-switch"
rm -f "$HOME/Desktop/启动Codex换号.command"
```

This does not remove `~/.codex/auth.json`, `~/.codex/accounts`, or account source archives.

## Deployment Checklist

- Run `./check.sh`.
- Confirm `jq`, `node`, `curl`, and `tar` exist.
- Confirm `/Applications/Codex.app` exists for real relaunch workflows.
- Confirm no real credentials are in the repository.
- Run `codex-account-switch --dry-run` before `--relaunch`.
- For release validation, run `NETWORK_CHECKS=1 ./check.sh`.
