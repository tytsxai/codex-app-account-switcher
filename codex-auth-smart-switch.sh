#!/usr/bin/env bash
set -euo pipefail

CODEX_HOME_DIR="${CODEX_HOME:-$HOME/.codex}"
ACCOUNTS_DIR="$CODEX_HOME_DIR/accounts"
REGISTRY_FILE="$ACCOUNTS_DIR/registry.json"
ACTIVE_AUTH_FILE="$CODEX_HOME_DIR/auth.json"
INVALID_ARCHIVE_ROOT="${INVALID_ARCHIVE_ROOT:-$CODEX_HOME_DIR/accounts-invalid-archive}"

MIN_5H_REMAIN="${MIN_5H_REMAIN:-10}"
MIN_WEEKLY_REMAIN="${MIN_WEEKLY_REMAIN:-5}"
SKIP_ACTIVE="${SKIP_ACTIVE:-1}"
CURL_CONNECT_TIMEOUT="${CURL_CONNECT_TIMEOUT:-4}"
CURL_MAX_TIME="${CURL_MAX_TIME:-6}"
SHOW_ALL_ACCOUNTS="${SHOW_ALL_ACCOUNTS:-0}"
POOL_PREVIEW_LIMIT="${POOL_PREVIEW_LIMIT:-0}"
PLAN_WEIGHT_PLUS="${PLAN_WEIGHT_PLUS:-1}"
PLAN_WEIGHT_PRO="${PLAN_WEIGHT_PRO:-1}"
PLAN_WEIGHT_TEAM="${PLAN_WEIGHT_TEAM:-1}"
PLAN_WEIGHT_BUSINESS="${PLAN_WEIGHT_BUSINESS:-1}"
PLAN_WEIGHT_FREE="${PLAN_WEIGHT_FREE:-1}"
PLAN_WEIGHT_UNKNOWN="${PLAN_WEIGHT_UNKNOWN:-1}"
MAX_PARALLEL_REFRESH="${MAX_PARALLEL_REFRESH:-4}"
USABLE_PLANS="${USABLE_PLANS:-free,plus,pro,team,business}"

DRY_RUN=0
VERBOSE=0
JSON_OUTPUT=0
USE_PLAN=""
FORCE_EMAIL=""
EXCLUDE_PLANS=""
CLEANUP_INVALID=0
CLEANUP_UNUSABLE=0
CLEANUP_YES=0

usage() {
  cat <<'EOF'
Usage:
  codex-auth-smart-switch.sh [--dry-run] [--verbose] [--include-active] [--json]
                             [--use-plan <json-file>] [--force-email <email>]
                             [--exclude-plan <plan>]...
                             [--cleanup-invalid [--yes]]
                             [--cleanup-unusable [--yes]]

Behavior:
  - Refresh usage for each saved account via ChatGPT usage API when possible
  - Only accounts whose data was successfully refreshed via the API count as
    available; cached/stale data is never trusted for selection
  - Treat an account as available only when the 5h remaining percentage is
    above the configured threshold; if a weekly usage window exists, weekly
    remaining must also be above its threshold
  - Prefer Free accounts with live Codex quota first. Paid plans remain
    available fallback candidates and can still be forced with --force-email
  - --exclude-plan removes the given plan(s) from auto-selection only;
    the pool preview still shows them. Can be repeated or comma-separated.
    Ignored when --force-email is set.
  - --cleanup-invalid probes every account's refresh_token. Accounts whose
    refresh is rejected (HTTP 400/401) are listed as dead. With --yes (or
    when stdin is non-tty and --dry-run is not set) the dead entries are
    removed from registry and their auth files deleted; otherwise the
    script only reports the candidates and exits without changes. Cleanup
    archives are kept outside ~/.codex/accounts so codex-auth clean cannot
    remove them.
  - --cleanup-unusable also probes ChatGPT usage. Accounts whose auth is valid
    but whose live plan is not in USABLE_PLANS are listed as unusable and can
    be removed with --yes.
  - --use-plan is treated as a preload hint only. The target account is probed
    again before any file write so a stale preload cannot switch to an exhausted
    or downgraded account.

Config via env:
  MIN_5H_REMAIN=10
  MIN_WEEKLY_REMAIN=5
  SKIP_ACTIVE=1
  CURL_CONNECT_TIMEOUT=4
  CURL_MAX_TIME=6
  PLAN_WEIGHT_PLUS=1
  PLAN_WEIGHT_PRO=1
  PLAN_WEIGHT_TEAM=1
  PLAN_WEIGHT_BUSINESS=1
  PLAN_WEIGHT_FREE=1
  PLAN_WEIGHT_UNKNOWN=1
  USABLE_PLANS=free,plus,pro,team,business
  INVALID_ARCHIVE_ROOT=~/.codex/accounts-invalid-archive
EOF
}

debug() {
  if [[ "$VERBOSE" -eq 1 ]] && [[ "$JSON_OUTPUT" -eq 0 ]]; then
    printf '[debug] %s\n' "$*" >&2
  fi
}

emit_summary_json() {
  local status="$1"
  local changed="$2"
  local dry_run="$3"
  local active_key_before="$4"
  local active_key_after="$5"
  local selected_account_key="$6"
  local selected_auth_file="$7"
  local selected_usage_file="$8"
  local email="$9"
  local alias="${10}"
  local account_name="${11}"
  local display_name="${12}"
  local plan="${13}"
  local source="${14}"
  local fiveh_remaining="${15}"
  local weekly_remaining="${16}"
  local primary_reset_at="${17}"
  local weekly_reset_at="${18}"
  local weekly_limit_present="${19}"
  local pool_file="${20}"

  jq -cn \
    --arg status "$status" \
    --argjson changed "$changed" \
    --argjson dry_run "$dry_run" \
    --arg active_key_before "$active_key_before" \
    --arg active_key_after "$active_key_after" \
    --arg selected_account_key "$selected_account_key" \
    --arg selected_auth_file "$selected_auth_file" \
    --slurpfile selected_usage "$selected_usage_file" \
    --slurpfile pool "$pool_file" \
    --arg email "$email" \
    --arg alias "$alias" \
    --arg account_name "$account_name" \
    --arg display_name "$display_name" \
    --arg plan "$plan" \
    --arg source "$source" \
    --argjson fiveh_remaining "$fiveh_remaining" \
    --argjson weekly_remaining "$weekly_remaining" \
    --argjson primary_reset_at "$primary_reset_at" \
    --argjson weekly_reset_at "$weekly_reset_at" \
    --argjson weekly_limit_present "$weekly_limit_present" \
    '
      {
        status: $status,
        changed: ($changed == 1),
        dry_run: ($dry_run == 1),
        pool: ($pool[0] // {}),
        active_key_before: $active_key_before,
        active_key_after: $active_key_after,
        selected_account_key: $selected_account_key,
        selected_auth_file: $selected_auth_file,
        usage: ($selected_usage[0] // {}),
        account: {
          email: $email,
          alias: $alias,
          account_name: $account_name,
          display_name: $display_name,
          plan: $plan,
          source: $source,
          fiveh_remaining: $fiveh_remaining,
          weekly_remaining: $weekly_remaining,
          weekly_limit_present: ($weekly_limit_present == 1),
          primary_reset_at: $primary_reset_at,
          weekly_reset_at: $weekly_reset_at
        }
      }
    '
}

print_switch_summary() {
  local dry_run="$1"
  local display_name="$2"
  local email="$3"
  local plan="$4"
  local fiveh_remaining="$5"
  local primary_reset_at="$6"
  local weekly_remaining="$7"
  local weekly_reset_at="$8"
  local weekly_limit_present="$9"
  local source="${10}"
  local changed="${11}"

  if [[ "$dry_run" -eq 1 ]]; then
    printf 'Dry run only, no files changed.\n'
  elif [[ "$changed" -eq 1 ]]; then
    printf '已切换到可用账号。\n'
  else
    printf '当前最优账号已经是活动账号，未重复写入账号文件。\n'
  fi

  printf '账号: %s\n' "$display_name"
  if [[ "$display_name" != "$email" ]]; then
    printf '邮箱: %s\n' "$email"
  fi
  printf '套餐: %s\n' "$(plan_label "$plan")"
  printf '5h 剩余: %s%% (重置 %s)\n' "$fiveh_remaining" "$(format_epoch "$primary_reset_at")"
  if [[ "$weekly_limit_present" -eq 1 ]]; then
    printf '周额度剩余: %s%% (重置 %s)\n' "$weekly_remaining" "$(format_epoch "$weekly_reset_at")"
  else
    printf '周额度剩余: 无周窗口\n'
  fi
  printf '额度来源: %s\n' "$source"
}

auth_file_needs_update() {
  local target_auth_file="$1"
  [[ ! -f "$ACTIVE_AUTH_FILE" ]] || ! cmp -s "$target_auth_file" "$ACTIVE_AUTH_FILE"
}

install_active_auth_file() {
  local target_auth_file="$1"
  local active_auth_tmp

  active_auth_tmp="$CODEX_HOME_DIR/auth.json.tmp.$$"
  cp "$target_auth_file" "$active_auth_tmp"
  mv "$active_auth_tmp" "$ACTIVE_AUTH_FILE"

  if ! cmp -s "$target_auth_file" "$ACTIVE_AUTH_FILE"; then
    printf 'active auth file verification failed after write: %s\n' "$ACTIVE_AUTH_FILE" >&2
    exit 1
  fi
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'missing required command: %s\n' "$1" >&2
    exit 1
  }
}

format_epoch() {
  local epoch="${1:-0}"
  if [[ "$epoch" =~ ^[0-9]+$ ]] && [[ "$epoch" -gt 0 ]]; then
    if date -r "$epoch" '+%m-%d %H:%M' >/dev/null 2>&1; then
      date -r "$epoch" '+%m-%d %H:%M'
    else
      date -d "@$epoch" '+%m-%d %H:%M'
    fi
  else
    printf '-'
  fi
}

plan_label() {
  case "${1:-}" in
    free) printf 'Free' ;;
    pro) printf 'Pro' ;;
    plus) printf 'Plus' ;;
    team|business) printf 'Business' ;;
    *) printf '%s' "${1:-Unknown}" ;;
  esac
}

account_file_for_key() {
  local account_key="$1"
  local encoded
  encoded="$(printf '%s' "$account_key" | base64 | tr -d '\n=')"
  printf '%s/%s.auth.json' "$ACCOUNTS_DIR" "$encoded"
}

safe_archive_name() {
  printf '%s' "${1:-unknown}" | sed 's/[^A-Za-z0-9._@-]/_/g' | cut -c1-160
}

archive_dead_accounts() {
  local cleanup_results_file="$1"
  local dead_json="$2"
  local archive_dir auth_dir

  archive_dir="$INVALID_ARCHIVE_ROOT/cleanup-$(date +%Y%m%d-%H%M%S)"
  auth_dir="$archive_dir/auth-files"
  mkdir -p "$auth_dir"

  cp "$REGISTRY_FILE" "$archive_dir/registry-before.json"
  jq -s '.' "$cleanup_results_file" >"$archive_dir/probe-results.json"
  jq '.' <<<"$dead_json" >"$archive_dir/dead-accounts.json"
  : >"$archive_dir/auth-file-manifest.jsonl"

  while IFS= read -r dead_record; do
    [[ -n "$dead_record" ]] || continue
    local dead_key email status auth_file archived_file safe_email
    dead_key="$(jq -r '.account_key' <<<"$dead_record")"
    email="$(jq -r '.email // ""' <<<"$dead_record")"
    status="$(jq -r '.status // ""' <<<"$dead_record")"
    auth_file="$(account_file_for_key "$dead_key")"
    archived_file=""

    if [[ -f "$auth_file" ]]; then
      safe_email="$(safe_archive_name "${email:-$dead_key}")"
      archived_file="$auth_dir/${safe_email}__$(basename "$auth_file")"
      cp "$auth_file" "$archived_file"
    fi

    jq -nc \
      --arg account_key "$dead_key" \
      --arg email "$email" \
      --arg status "$status" \
      --arg auth_file "$auth_file" \
      --arg archived_file "$archived_file" \
      '{account_key:$account_key,email:$email,status:$status,auth_file:$auth_file,archived_file:$archived_file}' \
      >>"$archive_dir/auth-file-manifest.jsonl"
  done < <(jq -c '.[]' <<<"$dead_json")

  cat >"$archive_dir/README.md" <<EOF
# Invalid Codex Accounts Cleanup

Archived at: $(date -u +%Y-%m-%dT%H:%M:%SZ)

This folder contains accounts removed from the active Codex account pool after live validation.

- registry-before.json: full registry snapshot before deletion
- probe-results.json: complete live probe result set
- dead-accounts.json: accounts selected for deletion
- auth-files/: auth snapshots copied before deletion
- auth-file-manifest.jsonl: mapping from account/email/status to archived auth file

Only accounts with deterministic invalid states are deleted automatically: auth_failed, missing_file,
no_refresh_token, or unusable_plan when --cleanup-unusable is used. Network and usage_failed states
are not deleted by this cleanup path.
EOF

  printf '%s\n' "$archive_dir"
}

wait_for_available_slot() {
  local max_parallel="$1"
  while [[ "$(jobs -pr | wc -l | tr -d ' ')" -ge "$max_parallel" ]]; do
    sleep 0.05
  done
}

collect_account_record() {
  local account_json="$1"
  local output_file="$2"

  local account_key email plan fallback_usage_json auth_file usage_payload
  account_key="$(jq -r '.account_key' <<<"$account_json")"
  email="$(jq -r '.email // ""' <<<"$account_json")"
  plan="$(jq -r '.plan // "unknown"' <<<"$account_json")"
  fallback_usage_json="$(jq -c '.last_usage // {}' <<<"$account_json")"

  if [[ "$SKIP_ACTIVE" -eq 1 ]] && [[ "$account_key" == "$active_key" ]]; then
    debug "skip current active account: $email"
    return 0
  fi

  auth_file="$(account_file_for_key "$account_key")"
  if [[ ! -f "$auth_file" ]]; then
    debug "skip missing auth snapshot: $email"
    return 0
  fi

  usage_payload="$(fetch_usage_json "$auth_file" "$fallback_usage_json" "$plan")"

  local tmp_out="$output_file.tmp"
  if jq -cn \
    --argjson account "$account_json" \
    --argjson payload "$usage_payload" \
    --arg auth_file "$auth_file" \
    '
      ($payload.usage // {}) as $usage
      | ($usage.primary.used_percent // -1) as $primary_used
      | ($usage.secondary.used_percent // -1) as $secondary_used
      | (($usage.plan_type // $account.plan // "unknown") | ascii_downcase) as $effective_plan
      | $account + {
          source: ($payload.source // "cache"),
          auth_file: $auth_file,
          usage: $usage,
          effective_plan: $effective_plan,
          fiveh_remaining: (if $primary_used >= 0 then 100 - ($primary_used | floor) else -1 end),
          weekly_remaining: (if $secondary_used >= 0 then 100 - ($secondary_used | floor) else -1 end),
          weekly_limit_present: ($usage.secondary.present // false),
          primary_reset_at: ($usage.primary.resets_at // 0),
          weekly_reset_at: ($usage.secondary.resets_at // 0),
          last_usage_at: (if ($payload.source // "cache") == "api" then now | floor else ($account.last_usage_at // 0) end)
        }
    ' >"$tmp_out"; then
    mv "$tmp_out" "$output_file"
  else
    rm -f "$tmp_out"
  fi
}

refresh_access_token() {
  local auth_file="$1"
  local refresh_token response new_access new_id new_refresh tmp
  refresh_token="$(jq -r '.tokens.refresh_token // empty' "$auth_file" 2>/dev/null || true)"
  [[ -n "$refresh_token" ]] || return 1

  response="$(
    curl -fsS \
      --connect-timeout "$CURL_CONNECT_TIMEOUT" \
      --max-time "$CURL_MAX_TIME" \
      'https://auth.openai.com/oauth/token' \
      -H 'Content-Type: application/json' \
      -d "$(jq -nc --arg rt "$refresh_token" --arg cid "app_EMoamEEZ73f0CkXaXp7hrann" \
        '{grant_type:"refresh_token",refresh_token:$rt,client_id:$cid,scope:"openid profile email offline_access"}')" \
      2>/dev/null || true
  )"
  [[ -n "$response" ]] || return 1

  new_access="$(jq -r '.access_token // empty' <<<"$response" 2>/dev/null || true)"
  new_id="$(jq -r '.id_token // empty' <<<"$response" 2>/dev/null || true)"
  new_refresh="$(jq -r '.refresh_token // empty' <<<"$response" 2>/dev/null || true)"
  [[ -n "$new_access" ]] || return 1

  tmp="$auth_file.tmp.$$"
  if jq \
    --arg access "$new_access" \
    --arg id_t "$new_id" \
    --arg refresh "$new_refresh" \
    '.tokens.access_token = $access
     | (if $id_t != "" then .tokens.id_token = $id_t else . end)
     | (if $refresh != "" then .tokens.refresh_token = $refresh else . end)' \
    "$auth_file" >"$tmp" 2>/dev/null; then
    mv "$tmp" "$auth_file"
  else
    rm -f "$tmp"
    return 1
  fi

  if [[ -n "${active_key:-}" ]] && [[ "$auth_file" == "$(account_file_for_key "$active_key")" ]]; then
    local active_tmp="$ACTIVE_AUTH_FILE.tmp.$$"
    if cp "$auth_file" "$active_tmp" 2>/dev/null; then
      mv "$active_tmp" "$ACTIVE_AUTH_FILE" 2>/dev/null || rm -f "$active_tmp"
    else
      rm -f "$active_tmp"
    fi
  fi

  printf '%s\n' "$new_access"
  return 0
}

fetch_usage_json() {
  local auth_file="$1"
  local fallback_usage_json="$2"
  local fallback_plan="$3"
  local access_token response refreshed=0 refresh_failed=0 source

  access_token="$(jq -r '.tokens.access_token // empty' "$auth_file" 2>/dev/null || true)"

  if [[ -z "$access_token" ]]; then
    refreshed=1
    access_token="$(refresh_access_token "$auth_file" 2>/dev/null || true)"
    [[ -n "$access_token" ]] || refresh_failed=1
  fi

  while [[ -n "$access_token" ]]; do
    response="$(
      curl -fsS \
        --connect-timeout "$CURL_CONNECT_TIMEOUT" \
        --max-time "$CURL_MAX_TIME" \
        'https://chatgpt.com/backend-api/wham/usage' \
        -H "Authorization: Bearer $access_token" \
        -H 'Accept: application/json' \
        -H 'Content-Type: application/json' \
        2>/dev/null || true
    )"

    if [[ -n "$response" ]] && jq -e '.rate_limit.primary_window.used_percent != null' >/dev/null 2>&1 <<<"$response"; then
      jq -c --arg fallback_plan "$fallback_plan" '
        ((.plan_type // $fallback_plan // "unknown") | ascii_downcase) as $plan_type
        | (.rate_limit.secondary_window // null) as $secondary
        |
        {
          source: "api",
          usage: {
            primary: {
              used_percent: (.rate_limit.primary_window.used_percent | floor),
              window_minutes: ((.rate_limit.primary_window.limit_window_seconds // 18000) / 60 | floor),
              resets_at: (.rate_limit.primary_window.reset_at // 0)
            },
            secondary: {
              used_percent: (
                if $secondary.used_percent != null then
                  ($secondary.used_percent | floor)
                else
                  null
                end
              ),
              window_minutes: (
                if $secondary != null then
                  (($secondary.limit_window_seconds // 604800) / 60) | floor
                else
                  null
                end
              ),
              resets_at: ($secondary.reset_at // 0),
              present: ($secondary != null)
            },
            credits: (.credits // null),
            plan_type: $plan_type
          }
        }
      ' <<<"$response"
      return 0
    fi

    [[ "$refreshed" -eq 0 ]] || break
    refreshed=1
    access_token="$(refresh_access_token "$auth_file" 2>/dev/null || true)"
    if [[ -z "$access_token" ]]; then
      refresh_failed=1
      break
    fi
  done

  if [[ "$refresh_failed" -eq 1 ]]; then
    source="auth_failed"
  elif [[ "$refreshed" -eq 1 ]]; then
    source="api_failed"
  else
    source="cache"
  fi

  jq -cn --argjson usage "$fallback_usage_json" --arg src "$source" '{source:$src, usage:$usage}'
}

probe_refresh_status() {
  local auth_file="$1"
  local refresh_token body_file body http new_access new_id new_refresh tmp
  refresh_token="$(jq -r '.tokens.refresh_token // empty' "$auth_file" 2>/dev/null)"
  if [[ -z "$refresh_token" ]]; then
    printf 'no_refresh_token'
    return
  fi

  body_file="$(mktemp -t codex-probe.XXXXXX)"
  http="$(curl -sS -o "$body_file" -w '%{http_code}' \
    --connect-timeout "$CURL_CONNECT_TIMEOUT" \
    --max-time "$CURL_MAX_TIME" \
    'https://auth.openai.com/oauth/token' \
    -H 'Content-Type: application/json' \
    -d "$(jq -nc --arg rt "$refresh_token" --arg cid "app_EMoamEEZ73f0CkXaXp7hrann" \
      '{grant_type:"refresh_token",refresh_token:$rt,client_id:$cid,scope:"openid profile email offline_access"}')" \
    2>/dev/null)" || http="000"
  body="$(cat "$body_file" 2>/dev/null)"
  rm -f "$body_file"

  if [[ "$http" == "200" ]]; then
    if ! jq -e '.access_token' <<<"$body" >/dev/null 2>&1; then
      printf 'bad_response'
      return
    fi
    new_access="$(jq -r '.access_token // empty' <<<"$body")"
    new_id="$(jq -r '.id_token // empty' <<<"$body")"
    new_refresh="$(jq -r '.refresh_token // empty' <<<"$body")"
    tmp="$auth_file.tmp.$$"
    if jq \
      --arg access "$new_access" \
      --arg id_t "$new_id" \
      --arg refresh "$new_refresh" \
      '.tokens.access_token = $access
       | (if $id_t != "" then .tokens.id_token = $id_t else . end)
       | (if $refresh != "" then .tokens.refresh_token = $refresh else . end)' \
      "$auth_file" >"$tmp" 2>/dev/null; then
      mv "$tmp" "$auth_file"
      if [[ -n "${active_key:-}" ]] && [[ "$auth_file" == "$(account_file_for_key "$active_key")" ]]; then
        local active_tmp="$ACTIVE_AUTH_FILE.tmp.$$"
        if cp "$auth_file" "$active_tmp" 2>/dev/null; then
          mv "$active_tmp" "$ACTIVE_AUTH_FILE" 2>/dev/null || rm -f "$active_tmp"
        else
          rm -f "$active_tmp"
        fi
      fi
    else
      rm -f "$tmp"
    fi
    printf 'ok'
    return
  fi

  if [[ "$http" == "400" ]] || [[ "$http" == "401" ]] || [[ "$http" == "403" ]]; then
    printf 'auth_failed'
    return
  fi

  if [[ "$http" == "000" ]]; then
    printf 'network'
    return
  fi

  printf 'http_%s' "$http"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      ;;
    --verbose)
      VERBOSE=1
      ;;
    --include-active)
      SKIP_ACTIVE=0
      ;;
    --json)
      JSON_OUTPUT=1
      ;;
    --use-plan)
      shift
      [[ $# -gt 0 ]] || {
        printf 'missing value for --use-plan\n' >&2
        exit 1
      }
      USE_PLAN="$1"
      ;;
    --force-email)
      shift
      [[ $# -gt 0 ]] || {
        printf 'missing value for --force-email\n' >&2
        exit 1
      }
      FORCE_EMAIL="$1"
      SKIP_ACTIVE=0
      ;;
    --exclude-plan)
      shift
      [[ $# -gt 0 ]] || {
        printf 'missing value for --exclude-plan\n' >&2
        exit 1
      }
      if [[ -n "$EXCLUDE_PLANS" ]]; then
        EXCLUDE_PLANS="$EXCLUDE_PLANS,$1"
      else
        EXCLUDE_PLANS="$1"
      fi
      ;;
    --cleanup-invalid)
      CLEANUP_INVALID=1
      ;;
    --cleanup-unusable)
      CLEANUP_INVALID=1
      CLEANUP_UNUSABLE=1
      ;;
    --yes|-y)
      CLEANUP_YES=1
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

require_cmd jq
require_cmd curl
require_cmd base64
require_cmd mktemp
require_cmd cmp

if [[ -n "$FORCE_EMAIL" ]] && [[ -n "$USE_PLAN" ]]; then
  printf '--force-email 与 --use-plan 不能同时使用\n' >&2
  exit 1
fi

[[ -f "$REGISTRY_FILE" ]] || {
  printf 'registry not found: %s\n' "$REGISTRY_FILE" >&2
  exit 1
}

if [[ ! -f "$ACTIVE_AUTH_FILE" ]]; then
  bootstrap_active_key="$(jq -r '.active_account_key // ""' "$REGISTRY_FILE" 2>/dev/null || true)"
  if [[ -n "$bootstrap_active_key" ]]; then
    bootstrap_auth_file="$(account_file_for_key "$bootstrap_active_key")"
    if [[ -f "$bootstrap_auth_file" ]]; then
      cp "$bootstrap_auth_file" "$ACTIVE_AUTH_FILE"
    fi
  fi
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

accounts_jsonl="$tmp_dir/accounts.jsonl"
ranked_json="$tmp_dir/ranked.json"
selected_json="$tmp_dir/selected.json"
summary_json="$tmp_dir/summary.json"
pool_json="$tmp_dir/pool.json"

active_key="$(jq -r '.active_account_key // ""' "$REGISTRY_FILE")"
now_s="$(date +%s)"
now_ms="$((now_s * 1000))"

debug "active key: $active_key"
debug "thresholds: 5h>${MIN_5H_REMAIN}%, weekly>${MIN_WEEKLY_REMAIN}%"
if [[ ! "$MAX_PARALLEL_REFRESH" =~ ^[0-9]+$ ]] || [[ "$MAX_PARALLEL_REFRESH" -lt 1 ]]; then
  MAX_PARALLEL_REFRESH=4
fi
debug "max parallel refresh: $MAX_PARALLEL_REFRESH"

if [[ "$CLEANUP_INVALID" -eq 1 ]]; then
  cleanup_results="$tmp_dir/cleanup-results.jsonl"
  : >"$cleanup_results"

  while IFS= read -r account; do
    account_key="$(jq -r '.account_key' <<<"$account")"
    email="$(jq -r '.email // ""' <<<"$account")"
    auth_file="$(account_file_for_key "$account_key")"

    if [[ ! -f "$auth_file" ]]; then
      jq -nc --arg key "$account_key" --arg email "$email" --arg status "missing_file" \
        '{account_key:$key, email:$email, status:$status}' >>"$cleanup_results"
      continue
    fi

    status="$(probe_refresh_status "$auth_file")"
    live_plan=""
    usage_source=""
    if [[ "$status" == "ok" ]] && [[ "$CLEANUP_UNUSABLE" -eq 1 ]]; then
      fallback_plan="$(jq -r '.plan // "unknown"' <<<"$account")"
      fallback_usage_json="$(jq -c '.last_usage // {}' <<<"$account")"
      usage_payload="$(fetch_usage_json "$auth_file" "$fallback_usage_json" "$fallback_plan")"
      usage_source="$(jq -r '.source // "cache"' <<<"$usage_payload")"
      live_plan="$(jq -r --arg fallback "$fallback_plan" '(.usage.plan_type // $fallback // "unknown") | ascii_downcase' <<<"$usage_payload")"

      if [[ "$usage_source" != "api" ]]; then
        status="usage_failed"
      elif ! jq -ne --arg plan "$live_plan" --arg usable "$USABLE_PLANS" '
        ($usable | ascii_downcase | split(",") | map(gsub("^\\s+|\\s+$"; "")) | map(select(length > 0))) as $plans
        | ($plans | index($plan)) != null
      ' >/dev/null; then
        status="unusable_plan:${live_plan}"
      fi
    fi

    jq -nc --arg key "$account_key" --arg email "$email" --arg status "$status" --arg plan "$live_plan" --arg source "$usage_source" \
      '{account_key:$key, email:$email, status:$status, live_plan:$plan, usage_source:$source}' >>"$cleanup_results"
  done < <(jq -c '.accounts[]' "$REGISTRY_FILE")

  dead_keys_json="$(jq -s --argjson cleanup_unusable "$CLEANUP_UNUSABLE" '
    [
      .[]
      | select(
          .status == "auth_failed"
          or .status == "missing_file"
          or .status == "no_refresh_token"
          or (($cleanup_unusable == 1) and (.status | startswith("unusable_plan:")))
        )
    ]
  ' "$cleanup_results")"
  ok_count="$(jq -s 'map(select(.status == "ok")) | length' "$cleanup_results")"
  network_count="$(jq -s 'map(select(.status == "network" or .status == "usage_failed" or (.status | startswith("http_")))) | length' "$cleanup_results")"
  dead_count="$(jq 'length' <<<"$dead_keys_json")"

  if [[ "$JSON_OUTPUT" -eq 1 ]]; then
    jq -s --argjson dead "$dead_keys_json" \
      --argjson dry_run "$DRY_RUN" \
      --argjson confirmed "$CLEANUP_YES" \
      '{
        status: "cleanup_invalid",
        dry_run: ($dry_run == 1),
        confirmed: ($confirmed == 1),
        ok_count: (map(select(.status == "ok")) | length),
        dead_count: ($dead | length),
        network_count: (map(select(.status == "network" or .status == "usage_failed" or (.status | startswith("http_")))) | length),
        results: .,
        dead: $dead
      }' "$cleanup_results"
  else
    printf '账号探测结果 (共 %s 个):\n' "$(jq -s 'length' "$cleanup_results")"
    jq -rs '
      sort_by(
        if .status == "ok" then 0
        elif .status == "auth_failed" or (.status | startswith("unusable_plan:")) then 1
        elif .status == "missing_file" or .status == "no_refresh_token" then 2
        elif .status == "network" or .status == "usage_failed" then 3
        else 4 end
      )
      | .[]
      | "  [\(.status)]\t\(.email // .account_key)"
    ' "$cleanup_results" | column -t -s $'\t'
    printf '\n汇总: ok=%s | dead=%s | 网络/未知=%s\n' "$ok_count" "$dead_count" "$network_count"
  fi

  cleanup_residue() {
    if command -v codex-auth >/dev/null 2>&1; then
      codex-auth clean >/dev/null 2>&1 || true
    fi
  }

  if [[ "$dead_count" -eq 0 ]]; then
    cleanup_residue
    [[ "$JSON_OUTPUT" -eq 1 ]] || printf '没有需要清理的失效账号。\n'
    exit 0
  fi

  if [[ "$DRY_RUN" -eq 1 ]] || [[ "$CLEANUP_YES" -eq 0 ]]; then
    if [[ "$JSON_OUTPUT" -eq 0 ]]; then
      printf '\n以下账号将被清理 (registry 条目 + auth 文件):\n'
      jq -rn --argjson dead "$dead_keys_json" '$dead[] | "  - \(.email // .account_key)  [\(.status)]"'
      if [[ "$DRY_RUN" -eq 1 ]]; then
        printf '\nDry run，未做任何修改。\n'
      else
        printf '\n如确认清理，请加 --yes 重新执行。\n'
      fi
    fi
    exit 0
  fi

  invalid_archive_dir="$(archive_dead_accounts "$cleanup_results" "$dead_keys_json")"

  while IFS= read -r dead_key; do
    [[ -n "$dead_key" ]] || continue
    auth_file="$(account_file_for_key "$dead_key")"
    [[ -f "$auth_file" ]] && rm -f "$auth_file"
  done < <(jq -r '.[].account_key' <<<"$dead_keys_json")

  registry_tmp="$tmp_dir/registry.json.tmp"
  jq --argjson dead "$dead_keys_json" \
    '($dead | map(.account_key)) as $dk
     | .accounts |= map(select(.account_key as $k | ($dk | index($k)) | not))
     | if (.active_account_key as $active | .accounts | any(.account_key == $active)) then
         .
       else
         .active_account_key = (.accounts[0].account_key // "")
       end' \
    "$REGISTRY_FILE" >"$registry_tmp" && mv "$registry_tmp" "$REGISTRY_FILE"

  cleanup_residue

  if [[ "$JSON_OUTPUT" -eq 0 ]]; then
    printf '\n失效账号归档: %s\n' "$invalid_archive_dir"
    printf '\n已清理 %s 个失效账号。\n' "$dead_count"
  fi
  exit 0
fi

if [[ -n "$USE_PLAN" ]]; then
  [[ -f "$USE_PLAN" ]] || {
    printf 'plan not found: %s\n' "$USE_PLAN" >&2
    exit 1
  }

  plan_status="$(jq -r '.status // "unknown"' "$USE_PLAN")"
  if [[ "$plan_status" == "no_available" ]]; then
    if [[ "$JSON_OUTPUT" -eq 1 ]]; then
      cat "$USE_PLAN"
    else
      printf '当前所有账号均无可用额度\n'
    fi
    exit 0
  fi

  [[ "$plan_status" == "ok" ]] || {
    printf 'invalid plan status: %s\n' "$plan_status" >&2
    exit 1
  }

  target_key="$(jq -r '.selected_account_key // ""' "$USE_PLAN")"
  target_auth_file="$(jq -r '.selected_auth_file // ""' "$USE_PLAN")"
  [[ -n "$target_key" ]] || {
    printf 'invalid plan: missing selected_account_key\n' >&2
    exit 1
  }
  [[ -f "$target_auth_file" ]] || {
    printf 'invalid plan auth file: %s\n' "$target_auth_file" >&2
    exit 1
  }

  target_email="$(jq -r '.account.email // ""' "$USE_PLAN")"
  target_alias="$(jq -r '.account.alias // ""' "$USE_PLAN")"
  target_account_name="$(jq -r '.account.account_name // ""' "$USE_PLAN")"
  display_name="$(jq -r '.account.display_name // .account.email // ""' "$USE_PLAN")"
  target_plan="$(jq -r '.account.plan // "unknown"' "$USE_PLAN")"
  target_fiveh="$(jq -r '.account.fiveh_remaining // -1' "$USE_PLAN")"
  target_weekly="$(jq -r '.account.weekly_remaining // -1' "$USE_PLAN")"
  target_weekly_limit_present="$(jq -r 'if (.account | has("weekly_limit_present")) then (if .account.weekly_limit_present then 1 else 0 end) else 1 end' "$USE_PLAN")"
  target_primary_reset_at="$(jq -r '.account.primary_reset_at // 0' "$USE_PLAN")"
  target_weekly_reset_at="$(jq -r '.account.weekly_reset_at // 0' "$USE_PLAN")"
  target_source="$(jq -r '.account.source // "cache"' "$USE_PLAN")"
  jq '.pool // {}' "$USE_PLAN" >"$pool_json"

  if [[ "$target_source" != "api" ]]; then
    if [[ "$JSON_OUTPUT" -eq 1 ]]; then
      jq -cn \
        --slurpfile pool "$pool_json" \
        --arg src "$target_source" \
        '{status:"stale_plan", reason:"selected account source is not api", source:$src, pool: ($pool[0] // {})}'
    else
      printf '使用计划失败: 目标账号数据来源为 %s，非实时数据，已拒绝以避免切到失效账号。\n' "$target_source" >&2
    fi
    exit 1
  fi

  target_fallback_usage="$(jq -c '.usage // {}' "$USE_PLAN")"
  usage_payload="$(fetch_usage_json "$target_auth_file" "$target_fallback_usage" "$target_plan")"
  target_source="$(jq -r '.source // "cache"' <<<"$usage_payload")"

  if [[ "$target_source" != "api" ]]; then
    if [[ "$JSON_OUTPUT" -eq 1 ]]; then
      jq -cn \
        --slurpfile pool "$pool_json" \
        --arg src "$target_source" \
        '{status:"stale_plan", reason:"selected account failed live usage refresh before switch", source:$src, pool: ($pool[0] // {})}'
    else
      printf '使用计划失败: 目标账号执行前实时刷新失败 (%s)，已拒绝以避免切到失效账号。\n' "$target_source" >&2
    fi
    exit 1
  fi

  jq -cn \
    --argjson payload "$usage_payload" \
    --arg fallback_plan "$target_plan" \
    '
      ($payload.usage // {}) as $usage
      | ($usage.primary.used_percent // -1) as $primary_used
      | ($usage.secondary.used_percent // -1) as $secondary_used
      | {
          source: ($payload.source // "cache"),
          usage: $usage,
          effective_plan: (($usage.plan_type // $fallback_plan // "unknown") | ascii_downcase),
          fiveh_remaining: (if $primary_used >= 0 then 100 - ($primary_used | floor) else -1 end),
          weekly_remaining: (if $secondary_used >= 0 then 100 - ($secondary_used | floor) else -1 end),
          weekly_limit_present: ($usage.secondary.present // false),
          primary_reset_at: ($usage.primary.resets_at // 0),
          weekly_reset_at: ($usage.secondary.resets_at // 0)
        }
    ' >"$tmp_dir/target-live.json"

  target_plan="$(jq -r '.effective_plan // "unknown"' "$tmp_dir/target-live.json")"
  target_fiveh="$(jq -r '.fiveh_remaining // -1' "$tmp_dir/target-live.json")"
  target_weekly="$(jq -r '.weekly_remaining // -1' "$tmp_dir/target-live.json")"
  target_weekly_limit_present="$(jq -r 'if has("weekly_limit_present") then (if .weekly_limit_present then 1 else 0 end) else 1 end' "$tmp_dir/target-live.json")"
  target_primary_reset_at="$(jq -r '.primary_reset_at // 0' "$tmp_dir/target-live.json")"
  target_weekly_reset_at="$(jq -r '.weekly_reset_at // 0' "$tmp_dir/target-live.json")"
  jq '.usage // {}' "$tmp_dir/target-live.json" >"$tmp_dir/target-usage.json"

  if ! jq -ne --arg plan "$target_plan" --arg usable "$USABLE_PLANS" '
    ($usable | ascii_downcase | split(",") | map(gsub("^\\s+|\\s+$"; "")) | map(select(length > 0))) as $plans
    | ($plans | index($plan | ascii_downcase)) != null
  ' >/dev/null; then
    if [[ "$JSON_OUTPUT" -eq 1 ]]; then
      jq -cn \
        --slurpfile pool "$pool_json" \
        --arg plan "$target_plan" \
        '{status:"unusable_plan", reason:"selected account live plan is not usable", plan:$plan, pool: ($pool[0] // {})}'
    else
      printf '使用计划失败: 目标账号实时套餐为 %s，不在可用套餐内。\n' "$target_plan" >&2
    fi
    exit 1
  fi

  if [[ -n "$EXCLUDE_PLANS" ]] && jq -ne \
    --arg plan "$target_plan" \
    --arg excludes "$EXCLUDE_PLANS" \
    '
      (
        $excludes
        | ascii_downcase
        | split(",")
        | map(gsub("^\\s+|\\s+$"; ""))
        | map(select(length > 0))
      ) as $ex
      | ($ex | index($plan | ascii_downcase)) != null
    ' >/dev/null; then
    if [[ "$JSON_OUTPUT" -eq 1 ]]; then
      jq -cn \
        --slurpfile pool "$pool_json" \
        --arg plan "$target_plan" \
        '{status:"excluded_plan", plan:$plan, pool: ($pool[0] // {})}'
    else
      printf 'selection plan target plan is excluded: %s\n' "$target_plan" >&2
    fi
    exit 1
  fi

  if ! jq -ne \
    --argjson fiveh "$target_fiveh" \
    --argjson weekly "$target_weekly" \
    --argjson min5 "$MIN_5H_REMAIN" \
    --argjson minw "$MIN_WEEKLY_REMAIN" \
    --argjson weekly_limit_present "$target_weekly_limit_present" \
    '$fiveh >= $min5 and ((($weekly_limit_present == 1) and ($weekly >= $minw)) or ($weekly_limit_present == 0))' >/dev/null; then
    if [[ "$JSON_OUTPUT" -eq 1 ]]; then
      jq -cn \
        --slurpfile pool "$pool_json" \
        --arg email "$target_email" \
        --arg plan "$target_plan" \
        --argjson fiveh "$target_fiveh" \
        --argjson weekly "$target_weekly" \
        --argjson weekly_limit_present "$target_weekly_limit_present" \
        '{status:"target_unavailable", reason:"selected account fell below live usage thresholds", account:{email:$email, plan:$plan, fiveh_remaining:$fiveh, weekly_remaining:$weekly, weekly_limit_present:($weekly_limit_present == 1)}, pool: ($pool[0] // {})}'
    else
      if [[ "$target_weekly_limit_present" -eq 1 ]]; then
        printf '使用计划失败: 目标账号实时额度不足，5h=%s%%，周=%s%%。\n' "$target_fiveh" "$target_weekly" >&2
      else
        printf '使用计划失败: 目标账号实时额度不足，5h=%s%%，周=无周窗口。\n' "$target_fiveh" >&2
      fi
    fi
    exit 1
  fi

  changed=0
  if [[ "$target_key" != "$active_key" ]] || auth_file_needs_update "$target_auth_file"; then
    changed=1
  fi

  if [[ "$DRY_RUN" -eq 0 ]] && [[ "$changed" -eq 1 ]]; then
    install_active_auth_file "$target_auth_file"

    registry_tmp="$tmp_dir/registry.json.tmp"
    jq \
      --arg target_key "$target_key" \
      --argjson now_s "$now_s" \
      --argjson now_ms "$now_ms" \
      --slurpfile target_usage "$tmp_dir/target-usage.json" \
      '
        .active_account_key = $target_key
        | .active_account_activated_at_ms = $now_ms
        | .accounts |= map(
            if .account_key == $target_key then
              .last_used_at = $now_s
              | .last_usage = ($target_usage[0] // .last_usage)
              | .last_usage_at = $now_s
            else
              .
            end
          )
      ' "$REGISTRY_FILE" >"$registry_tmp"

    mv "$registry_tmp" "$REGISTRY_FILE"
  fi

  emit_summary_json \
    "ok" \
    "$changed" \
    "$DRY_RUN" \
    "$active_key" \
    "$target_key" \
    "$target_key" \
    "$target_auth_file" \
    "$tmp_dir/target-usage.json" \
    "$target_email" \
    "$target_alias" \
    "$target_account_name" \
    "$display_name" \
    "$target_plan" \
    "$target_source" \
    "$target_fiveh" \
    "$target_weekly" \
    "$target_primary_reset_at" \
    "$target_weekly_reset_at" \
    "$target_weekly_limit_present" \
    "$pool_json" >"$summary_json"

  if [[ "$JSON_OUTPUT" -eq 1 ]]; then
    cat "$summary_json"
  else
    print_switch_summary \
      "$DRY_RUN" \
      "$display_name" \
      "$target_email" \
      "$target_plan" \
      "$target_fiveh" \
      "$target_primary_reset_at" \
      "$target_weekly" \
      "$target_weekly_reset_at" \
      "$target_weekly_limit_present" \
      "$target_source" \
      "$changed"
  fi
  exit 0
fi

accounts_input="$tmp_dir/accounts-input.jsonl"
account_results_dir="$tmp_dir/account-results"
mkdir -p "$account_results_dir"
if [[ -n "$FORCE_EMAIL" ]]; then
  jq -c --arg email "$FORCE_EMAIL" '.accounts[] | select((.email // "") | ascii_downcase == ($email | ascii_downcase))' "$REGISTRY_FILE" >"$accounts_input"
  if [[ ! -s "$accounts_input" ]]; then
    if [[ "$JSON_OUTPUT" -eq 1 ]]; then
      jq -cn --arg email "$FORCE_EMAIL" '{status:"not_found", email:$email}'
    else
      printf '未在 registry 中找到邮箱为 %s 的账号\n' "$FORCE_EMAIL" >&2
    fi
    exit 1
  fi
else
  jq -c '.accounts[]' "$REGISTRY_FILE" >"$accounts_input"
fi

task_index=0
while IFS= read -r account; do
  task_index=$((task_index + 1))
  wait_for_available_slot "$MAX_PARALLEL_REFRESH"
  collect_account_record "$account" "$account_results_dir/$task_index.json" &
done <"$accounts_input"
wait

: >"$accounts_jsonl"
find "$account_results_dir" -type f -name '*.json' -size +0c -exec cat {} + >>"$accounts_jsonl"

if [[ ! -s "$accounts_jsonl" ]]; then
  if [[ "$JSON_OUTPUT" -eq 1 ]]; then
    jq -cn '{status:"no_available"}'
  else
    printf '当前所有账号均无可用额度\n'
  fi
  exit 0
fi

jq -s \
  --argjson min5 "$MIN_5H_REMAIN" \
  --argjson minw "$MIN_WEEKLY_REMAIN" \
  --arg usable "$USABLE_PLANS" \
  '
    def usable_plans:
      (
        $usable
        | ascii_downcase
        | split(",")
        | map(gsub("^\\s+|\\s+$"; ""))
        | map(select(length > 0))
      );

    def plan_name:
      ((.effective_plan // .plan // "unknown") | ascii_downcase);

    def plan_usable:
      plan_name as $plan
      | (usable_plans | index($plan)) != null;

    def weekly_limit_present:
      (
        if has("weekly_limit_present") then
          .weekly_limit_present
        elif (.usage.secondary | type) == "object" and (.usage.secondary | has("present")) then
          .usage.secondary.present
        else
          false
        end
      ) == true;

    def weekly_available:
      (weekly_limit_present | not) or ((.weekly_remaining // -1) >= $minw);

    map(
      . + {
        available: (
          ((.source // "cache") == "api") and
          plan_usable and
          (.fiveh_remaining >= $min5) and
          weekly_available
        ),
        plan_bucket: (
          if ((.effective_plan // .plan // "") | ascii_downcase) == "free" then 0
          else 1
          end
        ),
        combined_priority: (-((.weekly_remaining // -1) + (.fiveh_remaining // -1))),
        weekly_priority: (-(.weekly_remaining // -1)),
        fiveh_priority: (-(.fiveh_remaining // -1)),
        freshness_priority: (-(.last_usage_at // 0))
      }
    )
    | sort_by([
      (.available | not),
      .plan_bucket,
      .combined_priority,
      .weekly_priority,
      .fiveh_priority,
      .freshness_priority
    ])
  ' "$accounts_jsonl" >"$ranked_json"

jq \
  --argjson preview_limit "$POOL_PREVIEW_LIMIT" \
  --argjson plus_weight "$PLAN_WEIGHT_PLUS" \
  --argjson pro_weight "$PLAN_WEIGHT_PRO" \
  --argjson team_weight "$PLAN_WEIGHT_TEAM" \
  --argjson business_weight "$PLAN_WEIGHT_BUSINESS" \
  --argjson free_weight "$PLAN_WEIGHT_FREE" \
  --argjson unknown_weight "$PLAN_WEIGHT_UNKNOWN" \
  --arg excludes "$EXCLUDE_PLANS" \
  --arg usable "$USABLE_PLANS" \
  --argjson min5 "$MIN_5H_REMAIN" \
  --argjson minw "$MIN_WEEKLY_REMAIN" \
  '
    def excluded_plans:
      (
        $excludes
        | ascii_downcase
        | split(",")
        | map(gsub("^\\s+|\\s+$"; ""))
        | map(select(length > 0))
      );

    def usable_plans:
      (
        $usable
        | ascii_downcase
        | split(",")
        | map(gsub("^\\s+|\\s+$"; ""))
        | map(select(length > 0))
      );

    def plan_name:
      ((.effective_plan // .plan // "unknown") | ascii_downcase);

    def plan_excluded:
      plan_name as $plan
      | (excluded_plans | index($plan)) != null;

    def plan_usable:
      plan_name as $plan
      | (usable_plans | index($plan)) != null;

    def plan_weight:
      plan_name as $plan
      | if $plan == "free" then $free_weight
        elif $plan == "pro" then $pro_weight
        elif $plan == "plus" then $plus_weight
        elif $plan == "team" then $team_weight
        elif $plan == "business" then $business_weight
        else $unknown_weight
        end;

    def weekly_limit_present:
      (
        if has("weekly_limit_present") then
          .weekly_limit_present
        elif (.usage.secondary | type) == "object" and (.usage.secondary | has("present")) then
          .usage.secondary.present
        else
          false
        end
      ) == true;

    def remaining_or_zero($field):
      if (.[$field] // -1) > 0 then .[$field] else 0 end;

    def weighted_remaining($field):
      map((plan_weight) * (remaining_or_zero($field))) | add // 0;

    def total_capacity_weight:
      map(plan_weight) | add // 0;

    def is_fresh:
      ((.source // "cache") == "api");

    def unavailable_reason:
      if (is_fresh | not) then
        (.source // "not_refreshed")
      elif (plan_usable | not) then
        "unusable_plan"
      elif ((.fiveh_remaining // -1) < $min5) then
        "low_5h"
      elif weekly_limit_present and ((.weekly_remaining // -1) < $minw) then
        "low_weekly"
      else
        "unknown"
      end;

    def preview_fields:
      {
        email: (.email // "-"),
        plan: (.effective_plan // .plan // "-"),
        fiveh_remaining: (.fiveh_remaining // -1),
        weekly_remaining: (.weekly_remaining // -1),
        weekly_limit_present: weekly_limit_present,
        source: (.source // "cache"),
        available: (.available // false),
        reason: (if (.available // false) then "available" else unavailable_reason end)
      };

    def apply_preview_limit:
      if $preview_limit > 0 then
        .[:$preview_limit]
      else
        .
      end;

    map(select(plan_excluded | not)) as $eligible
    | ($eligible | map(select(is_fresh))) as $fresh
    | {
      total_accounts: ($eligible | length),
      available_count: ($eligible | map(select(.available)) | length),
      unavailable_count: ($eligible | map(select(.available | not)) | length),
      stale_count: ($eligible | map(select(is_fresh | not)) | length),
      fresh_count: ($fresh | length),
      excluded_count: (length - ($eligible | length)),
      capacity_weight_total: ($eligible | total_capacity_weight),
      weight_profile: {
        plus: $plus_weight,
        pro: $pro_weight,
        team: $team_weight,
        business: $business_weight,
        free: $free_weight,
        unknown: $unknown_weight
      },
      total_fiveh_remaining_points: (
        $fresh |
        map(if (.fiveh_remaining // -1) > 0 then .fiveh_remaining else 0 end)
        | add // 0
      ),
      total_weekly_remaining_points: (
        $fresh |
        map(select(weekly_limit_present)) |
        map(if (.weekly_remaining // -1) > 0 then .weekly_remaining else 0 end)
        | add // 0
      ),
      overall_fiveh_remaining: (
        if ($fresh | total_capacity_weight) > 0 then
          ($fresh | weighted_remaining("fiveh_remaining")) / ($fresh | total_capacity_weight) | floor
        else
          0
        end
      ),
      overall_weekly_remaining: (
        ($fresh | map(select(weekly_limit_present))) as $weekly_limited
        | if ($weekly_limited | total_capacity_weight) > 0 then
          ($weekly_limited | weighted_remaining("weekly_remaining")) / ($weekly_limited | total_capacity_weight) | floor
        else
          -1
        end
      ),
      preview: (
        $eligible
        | map(select(.available))
        | apply_preview_limit
        | map(preview_fields)
      ),
      unavailable_preview: (
        $eligible
        | map(select(.available | not))
        | apply_preview_limit
        | map(preview_fields)
      )
    }
  ' "$ranked_json" >"$pool_json"

if [[ -n "$FORCE_EMAIL" ]]; then
  jq 'map(select(.available)) | .[0] // null' "$ranked_json" >"$selected_json"
else
  jq --arg excludes "$EXCLUDE_PLANS" '
    (
      $excludes
      | ascii_downcase
      | split(",")
      | map(gsub("^\\s+|\\s+$"; ""))
      | map(select(length > 0))
    ) as $ex
    | map(select(.available))
    | map(select(
        (((.effective_plan // .plan // "") | ascii_downcase)) as $p
        | ($ex | index($p)) == null
      ))
    | .[0]
  ' "$ranked_json" >"$selected_json"
fi

if [[ "$(jq -r 'if . == null then "null" else .account_key end' "$selected_json")" == "null" ]]; then
  if [[ "$JSON_OUTPUT" -eq 1 ]]; then
    if [[ -n "$FORCE_EMAIL" ]]; then
      jq -cn --slurpfile pool "$pool_json" --slurpfile ranked "$ranked_json" \
        '{status:"target_unavailable", account: ($ranked[0][0] // null), pool: ($pool[0] // {})}'
    else
      jq -cn --slurpfile pool "$pool_json" '{status:"no_available", pool: ($pool[0] // {})}'
    fi
  else
    if [[ -n "$FORCE_EMAIL" ]]; then
      printf '指定账号当前不可用：%s\n' "$FORCE_EMAIL"
    else
      printf '当前所有账号均无可用额度\n'
    fi
    if [[ "$VERBOSE" -eq 1 ]]; then
      jq -r '
        .[]
        | [
            (.email // "-"),
            (.effective_plan // .plan // "-"),
            ("5h=" + ((.fiveh_remaining|tostring) + "%")),
            ("weekly=" + (if (has("weekly_limit_present") and (.weekly_limit_present == false)) then "无周窗口" else ((.weekly_remaining|tostring) + "%") end)),
            ("source=" + (.source // "-"))
          ]
        | @tsv
      ' "$ranked_json" | column -t -s $'\t'
    fi
  fi
  exit 0
fi

target_key="$(jq -r '.account_key' "$selected_json")"
target_email="$(jq -r '.email // ""' "$selected_json")"
target_alias="$(jq -r '.alias // ""' "$selected_json")"
target_account_name="$(jq -r '.account_name // ""' "$selected_json")"
target_plan="$(jq -r '.effective_plan // .plan // "unknown"' "$selected_json")"
target_fiveh="$(jq -r '.fiveh_remaining // -1' "$selected_json")"
target_weekly="$(jq -r '.weekly_remaining // -1' "$selected_json")"
target_weekly_limit_present="$(jq -r 'if has("weekly_limit_present") then (if .weekly_limit_present then 1 else 0 end) else 1 end' "$selected_json")"
target_primary_reset_at="$(jq -r '.primary_reset_at // 0' "$selected_json")"
target_weekly_reset_at="$(jq -r '.weekly_reset_at // 0' "$selected_json")"
target_source="$(jq -r '.source // "cache"' "$selected_json")"
target_auth_file="$(jq -r '.auth_file' "$selected_json")"

display_name="$target_email"
if [[ -n "$target_alias" ]]; then
  display_name="$target_alias"
elif [[ -n "$target_account_name" ]]; then
  display_name="$target_account_name"
fi

changed=0
if [[ "$target_key" != "$active_key" ]] || auth_file_needs_update "$target_auth_file"; then
  changed=1
fi

target_usage_file="$tmp_dir/target-usage.json"
jq '.usage' "$selected_json" >"$target_usage_file"

if [[ "$DRY_RUN" -eq 0 ]] && [[ "$changed" -eq 1 ]]; then
  install_active_auth_file "$target_auth_file"

  registry_tmp="$tmp_dir/registry.json.tmp"
  jq \
    --arg target_key "$target_key" \
    --argjson now_s "$now_s" \
    --argjson now_ms "$now_ms" \
    --slurpfile target_usage "$target_usage_file" \
    '
      .active_account_key = $target_key
      | .active_account_activated_at_ms = $now_ms
      | .accounts |= map(
          if .account_key == $target_key then
            .last_used_at = $now_s
            | .last_usage = ($target_usage[0] // .last_usage)
            | .last_usage_at = $now_s
          else
            .
          end
        )
    ' "$REGISTRY_FILE" >"$registry_tmp"

  mv "$registry_tmp" "$REGISTRY_FILE"
fi

emit_summary_json \
  "ok" \
  "$changed" \
  "$DRY_RUN" \
  "$active_key" \
  "$target_key" \
  "$target_key" \
  "$target_auth_file" \
  "$target_usage_file" \
  "$target_email" \
  "$target_alias" \
  "$target_account_name" \
  "$display_name" \
  "$target_plan" \
  "$target_source" \
  "$target_fiveh" \
  "$target_weekly" \
  "$target_primary_reset_at" \
  "$target_weekly_reset_at" \
  "$target_weekly_limit_present" \
  "$pool_json" >"$summary_json"

if [[ "$JSON_OUTPUT" -eq 1 ]]; then
  cat "$summary_json"
  exit 0
fi

print_switch_summary \
  "$DRY_RUN" \
  "$display_name" \
  "$target_email" \
  "$target_plan" \
  "$target_fiveh" \
  "$target_primary_reset_at" \
  "$target_weekly" \
  "$target_weekly_reset_at" \
  "$target_weekly_limit_present" \
  "$target_source" \
  "$changed"

if [[ "$VERBOSE" -eq 1 ]]; then
  if [[ "$SHOW_ALL_ACCOUNTS" -eq 1 ]]; then
    printf '\n账号情况总览:\n'
    jq -r '
      .[]
      | [
          (.email // "-"),
          (.effective_plan // .plan // "-"),
          ("5h=" + ((.fiveh_remaining|tostring) + "%")),
          ("weekly=" + (if (has("weekly_limit_present") and (.weekly_limit_present == false)) then "无周窗口" else ((.weekly_remaining|tostring) + "%") end)),
          ("source=" + (.source // "-")),
          ("available=" + (.available|tostring))
        ]
      | @tsv
    ' "$ranked_json" | column -t -s $'\t'
  else
    printf '\n候选排序 Top 8:\n'
    jq -r '
      .[:8][]
      | [
          (.email // "-"),
          (.effective_plan // .plan // "-"),
          ("5h=" + ((.fiveh_remaining|tostring) + "%")),
          ("weekly=" + (if (has("weekly_limit_present") and (.weekly_limit_present == false)) then "无周窗口" else ((.weekly_remaining|tostring) + "%") end)),
          ("source=" + (.source // "-")),
          ("available=" + (.available|tostring))
        ]
      | @tsv
    ' "$ranked_json" | column -t -s $'\t'
  fi
fi

printf '\n'
printf '如果你在用官方 Codex CLI，切换后建议重启 CLI 会话；Codex.app 这套桌面方案建议走正常重启生效。\n'
