#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

make_registry() {
  local codex_home="$1"
  mkdir -p "$codex_home/accounts"
  printf '{"schema_version":1,"active_account_key":"","accounts":[]}\n' >"$codex_home/accounts/registry.json"
}

write_live_lock() {
  local lock_dir="$1"
  local pid="${2:-$$}"
  mkdir -p "$lock_dir"
  printf '%s\n' "$pid" >"$lock_dir/pid"
  {
    printf 'pid=%s\n' "$pid"
    printf 'owner=state-lock-fixture\n'
  } >"$lock_dir/owner"
}

assert_json_status() {
  local file="$1"
  local status="$2"
  jq -e --arg status "$status" '.status == $status' "$file" >/dev/null
}

codex_home="$tmp_dir/codex-home"
make_registry "$codex_home"
lock_dir="$codex_home/accounts/.codex-app-hot-switch.lock"

write_live_lock "$lock_dir" "$$"
if CODEX_HOME="$codex_home" "$ROOT_DIR/codex-auth-smart-switch.sh" --dry-run --json >"$tmp_dir/out.json" 2>"$tmp_dir/err"; then
  printf 'expected switcher to reject a live account-state lock\n' >&2
  exit 1
fi
grep -q '已有账号状态操作正在运行' "$tmp_dir/err"

rm -rf "$lock_dir"
write_live_lock "$lock_dir" "99999999"
CODEX_HOME="$codex_home" "$ROOT_DIR/codex-auth-smart-switch.sh" --dry-run --json >"$tmp_dir/out.json" 2>"$tmp_dir/err"
assert_json_status "$tmp_dir/out.json" "no_available"
[[ ! -d "$lock_dir" ]] || {
  printf 'expected stale switcher lock to be cleaned up\n' >&2
  exit 1
}

write_live_lock "$lock_dir" "$$"
CODEX_HOME="$codex_home" \
  CODEX_ACCOUNT_LOCK_HELD="$lock_dir" \
  "$ROOT_DIR/codex-auth-smart-switch.sh" --dry-run --json >"$tmp_dir/out.json" 2>"$tmp_dir/err"
assert_json_status "$tmp_dir/out.json" "no_available"
rm -rf "$lock_dir"

import_home="$tmp_dir/import-home"
mkdir -p "$import_home/accounts"
import_lock="$import_home/accounts/.codex-app-hot-switch.lock"
source_json="$tmp_dir/source.json"
printf '{"accounts":[]}\n' >"$source_json"

write_live_lock "$import_lock" "$$"
if CODEX_HOME="$import_home" node "$ROOT_DIR/codex-auth-import-json.mjs" --yes "$source_json" >"$tmp_dir/import-out.json" 2>"$tmp_dir/import-err"; then
  printf 'expected importer to reject a live account-state lock\n' >&2
  exit 1
fi
grep -q 'unable to acquire account state lock' "$tmp_dir/import-err"

CODEX_HOME="$import_home" node "$ROOT_DIR/codex-auth-import-json.mjs" --dry-run "$source_json" >"$tmp_dir/import-out.json"
jq -e '.status == "ok" and .dry_run == true and .imported_count == 0' "$tmp_dir/import-out.json" >/dev/null

refresh_only_source="$tmp_dir/refresh-only-source.json"
cat >"$refresh_only_source" <<'JSON'
{
  "email": "dry-run-refresh@example.invalid",
  "tokens": {
    "refresh_token": "fake-refresh-token"
  }
}
JSON
CODEX_HOME="$import_home" node "$ROOT_DIR/codex-auth-import-json.mjs" --dry-run "$refresh_only_source" >"$tmp_dir/import-out.json"
jq -e '
  .status == "ok"
  and .dry_run == true
  and .invalid_count == 1
  and .invalid[0].status == "dry_run_refresh_required"
' "$tmp_dir/import-out.json" >/dev/null

printf 'state lock fixtures passed\n'
