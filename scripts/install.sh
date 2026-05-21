#!/usr/bin/env bash
set -euo pipefail

REPO_SLUG="${REPO_SLUG:-tytsxai/codex-app-account-switcher}"
BRANCH="${BRANCH:-main}"
REPO_TARBALL_URL="${REPO_TARBALL_URL:-}"
INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/share/codex-app-account-switcher}"
BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"
DESKTOP_SHORTCUT=1
DRY_RUN=0
FROM_REMOTE=0

usage() {
  cat <<'EOF'
Usage:
  install.sh [--dry-run] [--install-dir <dir>] [--bin-dir <dir>] [--no-desktop-shortcut] [--from-remote]

Environment:
  REPO_SLUG=tytsxai/codex-app-account-switcher
  BRANCH=main
  REPO_TARBALL_URL=<optional explicit tarball URL>
  SOURCE_REVISION=<optional commit SHA for pre-downloaded source trees>
  INSTALL_DIR=~/.local/share/codex-app-account-switcher
  BIN_DIR=~/.local/bin
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

run() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf '[dry-run] %q' "$1"
    shift
    for arg in "$@"; do printf ' %q' "$arg"; done
    printf '\n'
  else
    "$@"
  fi
}

check_command() {
  local cmd="$1"
  local required="$2"
  if command -v "$cmd" >/dev/null 2>&1; then
    log "OK: $cmd -> $(command -v "$cmd")"
    return 0
  fi
  if [[ "$required" == "required" ]]; then
    die "missing required command: $cmd"
  fi
  warn "missing optional command: $cmd"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      ;;
    --install-dir)
      shift
      [[ $# -gt 0 ]] || die "missing value for --install-dir"
      INSTALL_DIR="$1"
      ;;
    --bin-dir)
      shift
      [[ $# -gt 0 ]] || die "missing value for --bin-dir"
      BIN_DIR="$1"
      ;;
    --no-desktop-shortcut)
      DESKTOP_SHORTCUT=0
      ;;
    --from-remote)
      FROM_REMOTE=1
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

[[ "$(uname -s)" == "Darwin" ]] || die "this installer targets macOS"
check_command jq required
check_command node required
check_command curl required
check_command tar required
check_command codex-auth optional
[[ -d /Applications/Codex.app ]] || warn "Codex.app not found at /Applications/Codex.app"

latest_revision() {
  curl -fsSL "https://api.github.com/repos/${REPO_SLUG}/commits/${BRANCH}" | jq -r '.sha // empty' 2>/dev/null || true
}

tmp_dir=""
cleanup() {
  [[ -z "$tmp_dir" ]] || rm -rf "$tmp_dir"
}
trap cleanup EXIT

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd 2>/dev/null || printf '')"
source_dir=""
source_revision="${SOURCE_REVISION:-}"

if [[ "$FROM_REMOTE" -eq 0 && -n "$script_dir" && -f "$script_dir/../codex-auth-smart-switch.sh" ]]; then
  source_dir="$(cd "$script_dir/.." && pwd)"
  if [[ -z "$source_revision" ]] && command -v git >/dev/null 2>&1 && git -C "$source_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    source_revision="$(git -C "$source_dir" rev-parse HEAD 2>/dev/null || true)"
  fi
  if [[ -z "$source_revision" ]]; then
    source_revision="$(latest_revision)"
  fi
else
  tmp_dir="$(mktemp -d)"
  archive="$tmp_dir/source.tar.gz"
  source_revision="$(latest_revision)"
  download_url="${REPO_TARBALL_URL:-https://codeload.github.com/${REPO_SLUG}/tar.gz/${source_revision:-refs/heads/${BRANCH}}}"
  log "Downloading $download_url"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "[dry-run] would download and extract release archive"
    source_dir="$tmp_dir/source"
    mkdir -p "$source_dir"
  else
    curl -fsSL "$download_url" -o "$archive"
    mkdir -p "$tmp_dir/source"
    tar -xzf "$archive" -C "$tmp_dir/source" --strip-components 1
    source_dir="$tmp_dir/source"
  fi
fi

files=(
  "check.sh"
  "codex-app-hot-switch.sh"
  "codex-app-relaunch.sh"
  "codex-auth-import-json.mjs"
  "codex-auth-load-free.mjs"
  "codex-auth-smart-switch.sh"
  "启动Codex换号.command"
  "README.md"
  "LICENSE"
)

if [[ "$DRY_RUN" -eq 0 ]]; then
  mkdir -p "$INSTALL_DIR" "$BIN_DIR"
  for file in "${files[@]}"; do
    [[ -f "$source_dir/$file" ]] || die "missing source file: $file"
    cp "$source_dir/$file" "$INSTALL_DIR/$file"
  done
  if [[ -f "$source_dir/VERSION" ]]; then
    cp "$source_dir/VERSION" "$INSTALL_DIR/VERSION"
  else
    printf '0.0.0-unknown\n' >"$INSTALL_DIR/VERSION"
  fi
  rm -rf "$INSTALL_DIR/docs" "$INSTALL_DIR/examples"
  rm -rf "$INSTALL_DIR/scripts"
  [[ -d "$source_dir/docs" ]] && cp -R "$source_dir/docs" "$INSTALL_DIR/docs"
  [[ -d "$source_dir/examples" ]] && cp -R "$source_dir/examples" "$INSTALL_DIR/examples"
  [[ -d "$source_dir/scripts" ]] && cp -R "$source_dir/scripts" "$INSTALL_DIR/scripts"
  chmod +x "$INSTALL_DIR"/*.sh "$INSTALL_DIR"/*.mjs "$INSTALL_DIR/启动Codex换号.command"
  [[ ! -d "$INSTALL_DIR/scripts" ]] || chmod +x "$INSTALL_DIR"/scripts/*.sh
  printf '%s\n' "${source_revision:-unknown}" >"$INSTALL_DIR/.install-revision"
  printf '%s\n' "$REPO_SLUG" >"$INSTALL_DIR/.install-source"
else
  log "[dry-run] would install files into $INSTALL_DIR"
  log "[dry-run] would create CLI wrapper in $BIN_DIR"
fi

wrapper="$BIN_DIR/codex-account-switch"
if [[ "$DRY_RUN" -eq 0 ]]; then
  cat >"$wrapper" <<EOF
#!/usr/bin/env bash
set -euo pipefail
APP_DIR="$INSTALL_DIR"
BIN_DIR="$BIN_DIR"
if [[ "\$#" -eq 0 ]]; then
  exec "\$APP_DIR/启动Codex换号.command"
fi
case "\${1:-}" in
  --self-update|self-update|update)
    shift
    exec "\$APP_DIR/scripts/install.sh" --from-remote --install-dir "\$APP_DIR" --bin-dir "\$BIN_DIR" "\$@"
    ;;
  --check-updates|check-updates)
    shift
    exec "\$APP_DIR/scripts/check-updates.sh" "\$@"
    ;;
  --version|-V)
    printf 'codex-app-account-switcher %s\n' "\$(cat "\$APP_DIR/VERSION" 2>/dev/null || printf unknown)"
    printf 'revision %s\n' "\$(cat "\$APP_DIR/.install-revision" 2>/dev/null || printf unknown)"
    exit 0
    ;;
esac
exec "\$APP_DIR/codex-app-hot-switch.sh" "\$@"
EOF
  chmod +x "$wrapper"
fi

if [[ "$DESKTOP_SHORTCUT" -eq 1 ]]; then
  desktop_launcher="$HOME/Desktop/启动Codex换号.command"
  if [[ "$DRY_RUN" -eq 0 ]]; then
    cat >"$desktop_launcher" <<EOF
#!/bin/zsh
exec "$INSTALL_DIR/启动Codex换号.command" "\$@"
EOF
    chmod +x "$desktop_launcher"
  else
    log "[dry-run] would create $desktop_launcher"
  fi
fi

log "Installed Codex.app Account Switcher"
log "CLI: $wrapper"
log "App files: $INSTALL_DIR"
