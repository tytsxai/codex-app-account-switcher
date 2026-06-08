#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK_UPDATES="$SCRIPT_DIR/check-updates.sh"
NPM_FETCH_TIMEOUT_MS="${NPM_FETCH_TIMEOUT_MS:-60000}"
DRY_RUN=0
INSTALL_MISSING=0

usage() {
  cat <<'EOF'
Usage:
  update-upstreams.sh [--dry-run] [--install-missing]

Updates:
  - codex-auth, when a newer upstream version is reported by check-updates.sh

Environment:
  CODEX_AUTH_PACKAGE defaults to the installed codex-auth package name,
  falling back to @loongphy/codex-auth.
  CODEX_AUTH_NPM_TAG defaults to latest.
  CODEX_AUTH_REPO_SLUG defaults to Loongphy/codex-auth.
  NPM_VIEW_TIMEOUT defaults to 20 seconds in the delegated update check.
  NPM_FETCH_TIMEOUT_MS defaults to 60000 milliseconds.

Notes:
  This script updates global npm packages. It does not change ~/.codex account
  snapshots or the active ~/.codex/auth.json file.
EOF
}

log() {
  printf '%s\n' "$*"
}

warn() {
  printf 'WARN: %s\n' "$*" >&2
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

have() {
  command -v "$1" >/dev/null 2>&1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      ;;
    --install-missing)
      INSTALL_MISSING=1
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
  shift
done

[[ -x "$CHECK_UPDATES" ]] || die "missing checker: $CHECK_UPDATES"
have jq || die "missing required command: jq"
have npm || die "missing required command: npm"

status_json="$("$CHECK_UPDATES" --json)"
package="$(jq -r '.codex_auth.package // ""' <<<"$status_json")"
npm_tag="$(jq -r '.codex_auth.npm_tag // "latest"' <<<"$status_json")"
local_version="$(jq -r '.codex_auth.local // ""' <<<"$status_json")"
npm_latest="$(jq -r '.codex_auth.npm_latest // ""' <<<"$status_json")"
github_latest_tag="$(jq -r '.codex_auth.github_latest_tag // ""' <<<"$status_json")"
status="$(jq -r '.codex_auth.status // "unknown"' <<<"$status_json")"

[[ -n "$package" ]] || die "unable to determine codex-auth npm package"

log "codex-auth upstream check"
log "  package:       $package"
log "  local:         ${local_version:-unknown}"
log "  npm $npm_tag:  ${npm_latest:-unknown}"
log "  github latest: ${github_latest_tag:-unknown}"
log "  status:        $status"

case "$status" in
  current|local_newer_than_upstream)
    log "No codex-auth update required."
    exit 0
    ;;
  update_available)
    ;;
  not_installed)
    if [[ "$INSTALL_MISSING" -eq 1 ]]; then
      log "codex-auth is not installed; installing because --install-missing was provided."
    else
      warn "codex-auth is not installed; rerun with --install-missing to install it."
      exit 0
    fi
    ;;
  local_only|unknown|version_mismatch)
    warn "codex-auth status is $status; refusing to update automatically."
    warn "Run scripts/check-updates.sh --json for details."
    exit 1
    ;;
  *)
    warn "unexpected codex-auth status: $status"
    exit 1
    ;;
esac

cmd=(npm --fetch-timeout "$NPM_FETCH_TIMEOUT_MS" install -g "${package}@${npm_tag}")
if [[ "$DRY_RUN" -eq 1 ]]; then
  printf '[dry-run] would run:'
  printf ' %q' "${cmd[@]}"
  printf '\n'
  exit 0
fi

log "Updating codex-auth with npm..."
"${cmd[@]}"

if have codex-auth; then
  log "Updated: $(codex-auth --version 2>/dev/null || printf 'codex-auth version unknown')"
else
  warn "npm completed, but codex-auth is still not on PATH."
fi
