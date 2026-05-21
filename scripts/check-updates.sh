#!/usr/bin/env bash
set -euo pipefail

REPO_SLUG="${REPO_SLUG:-tytsxai/codex-app-account-switcher}"
BRANCH="${BRANCH:-main}"
INSTALL_DIR="${INSTALL_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
CURRENT_REVISION="${CURRENT_REVISION:-$(cat "$INSTALL_DIR/.install-revision" 2>/dev/null || true)}"
JSON_OUTPUT=0
FAIL_IF_OUTDATED=0

usage() {
  cat <<'EOF'
Usage:
  check-updates.sh [--json] [--fail-if-outdated]

Checks:
  - This project's latest GitHub main revision
  - Raw installer and codeload archive availability
  - Local codex-auth version vs npm latest
  - Local Codex.app version when installed
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --json)
      JSON_OUTPUT=1
      ;;
    --fail-if-outdated)
      FAIL_IF_OUTDATED=1
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      printf 'unknown argument: %s\n' "$1" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

have() {
  command -v "$1" >/dev/null 2>&1
}

json_string() {
  jq -Rn --arg v "$1" '$v'
}

semver_gt() {
  local left="$1"
  local right="$2"
  [[ -n "$left" && -n "$right" ]] || return 1
  [[ "$left" != "$right" ]] || return 1
  [[ "$(printf '%s\n%s\n' "$right" "$left" | sort -V | tail -n 1)" == "$left" ]]
}

latest_revision=""
project_status="unknown"
installer_status="unknown"
codeload_status="unknown"
codex_auth_local=""
codex_auth_latest=""
codex_auth_status="unknown"
codex_app_version=""

if have curl && have jq; then
  latest_revision="$(curl -fsSL "https://api.github.com/repos/${REPO_SLUG}/commits/${BRANCH}" | jq -r '.sha // empty' 2>/dev/null || true)"
fi

if [[ -n "$latest_revision" && -n "$CURRENT_REVISION" ]]; then
  if [[ "$latest_revision" == "$CURRENT_REVISION" ]]; then
    project_status="current"
  else
    project_status="update_available"
  fi
elif [[ -n "$latest_revision" ]]; then
  project_status="remote_known"
fi

if have curl; then
  if curl -fsIL "https://raw.githubusercontent.com/${REPO_SLUG}/${BRANCH}/scripts/install.sh" >/dev/null 2>&1; then
    installer_status="ok"
  else
    installer_status="unreachable"
  fi
  if curl -fsIL "https://codeload.github.com/${REPO_SLUG}/tar.gz/refs/heads/${BRANCH}" >/dev/null 2>&1; then
    codeload_status="ok"
  else
    codeload_status="unreachable"
  fi
fi

if have codex-auth; then
  codex_auth_local="$(codex-auth --version 2>/dev/null | awk '{print $NF}' || true)"
fi
if have npm; then
  codex_auth_latest="$(npm view codex-auth version 2>/dev/null || true)"
fi

if [[ -n "$codex_auth_local" && -n "$codex_auth_latest" ]]; then
  if [[ "$codex_auth_local" == "$codex_auth_latest" ]]; then
    codex_auth_status="current"
  elif semver_gt "$codex_auth_latest" "$codex_auth_local"; then
    codex_auth_status="update_available"
  elif semver_gt "$codex_auth_local" "$codex_auth_latest"; then
    codex_auth_status="local_newer_than_npm"
  else
    codex_auth_status="version_mismatch"
  fi
elif [[ -n "$codex_auth_local" ]]; then
  codex_auth_status="local_only"
elif [[ -n "$codex_auth_latest" ]]; then
  codex_auth_status="not_installed"
fi

if [[ -d /Applications/Codex.app ]] && have defaults; then
  codex_app_version="$(defaults read /Applications/Codex.app/Contents/Info CFBundleShortVersionString 2>/dev/null || true)"
fi

outdated=0
if [[ "$project_status" == "update_available" || "$codex_auth_status" == "update_available" || "$installer_status" == "unreachable" || "$codeload_status" == "unreachable" ]]; then
  outdated=1
fi

if [[ "$JSON_OUTPUT" -eq 1 ]]; then
  jq -cn \
    --arg repo "$REPO_SLUG" \
    --arg branch "$BRANCH" \
    --arg install_dir "$INSTALL_DIR" \
    --arg current_revision "$CURRENT_REVISION" \
    --arg latest_revision "$latest_revision" \
    --arg project_status "$project_status" \
    --arg installer_status "$installer_status" \
    --arg codeload_status "$codeload_status" \
    --arg codex_auth_local "$codex_auth_local" \
    --arg codex_auth_latest "$codex_auth_latest" \
    --arg codex_auth_status "$codex_auth_status" \
    --arg codex_app_version "$codex_app_version" \
    --argjson outdated "$outdated" \
    '{
      repo: $repo,
      branch: $branch,
      install_dir: $install_dir,
      current_revision: $current_revision,
      latest_revision: $latest_revision,
      project_status: $project_status,
      installer_status: $installer_status,
      codeload_status: $codeload_status,
      codex_auth: {
        local: $codex_auth_local,
        npm_latest: $codex_auth_latest,
        status: $codex_auth_status
      },
      codex_app: {
        version: $codex_app_version
      },
      outdated: ($outdated == 1)
    }'
else
  printf 'Project: %s [%s]\n' "$REPO_SLUG" "$project_status"
  printf '  installed: %s\n' "${CURRENT_REVISION:-unknown}"
  printf '  latest:    %s\n' "${latest_revision:-unknown}"
  printf 'Installer raw URL: %s\n' "$installer_status"
  printf 'Codeload archive: %s\n' "$codeload_status"
  printf 'codex-auth: local=%s npm_latest=%s status=%s\n' "${codex_auth_local:-unknown}" "${codex_auth_latest:-unknown}" "$codex_auth_status"
  printf 'Codex.app: %s\n' "${codex_app_version:-unknown}"
  if [[ "$project_status" == "update_available" ]]; then
    printf '\nRun: codex-account-switch --self-update\n'
  fi
fi

if [[ "$FAIL_IF_OUTDATED" -eq 1 && "$outdated" -eq 1 ]]; then
  exit 1
fi
