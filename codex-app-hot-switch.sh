#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SWITCH_SCRIPT="$SCRIPT_DIR/codex-auth-smart-switch.sh"
RELAUNCH_SCRIPT="$SCRIPT_DIR/codex-app-relaunch.sh"
CODEX_HOME_DIR="${CODEX_HOME:-$HOME/.codex}"
ACCOUNTS_DIR="$CODEX_HOME_DIR/accounts"
LOCK_DIR="$ACCOUNTS_DIR/.codex-app-hot-switch.lock"
LOCK_HELD=0

DRY_RUN=0
VERBOSE=0
INCLUDE_ACTIVE=0
MODE="relaunch"
SELECTION_PLAN=""
FORCE_EMAIL=""
EXCLUDE_PLANS=()

usage() {
  cat <<'EOF'
Usage:
  codex-app-hot-switch.sh [--dry-run] [--verbose] [--include-active]
                           [--switch-only | --relaunch]

Behavior:
  - Select the best available account
  - Switch ~/.codex/auth.json to that account
  - Default strategy: relaunch Codex.app cleanly so the new auth is picked up
  - A preload selection plan is only a hint. If that target fails the final
    live check, fall back to a full real-time selection before relaunching.
EOF
}

cleanup() {
  rm -rf "${tmp_dir:-}"
  if [[ "$LOCK_HELD" -eq 1 ]]; then
    rm -rf "$LOCK_DIR"
  fi
}

acquire_lock() {
  local existing_pid

  mkdir -p "$ACCOUNTS_DIR"
  if mkdir "$LOCK_DIR" 2>/dev/null; then
    LOCK_HELD=1
    printf '%s\n' "$$" >"$LOCK_DIR/pid"
    return 0
  fi

  existing_pid="$(cat "$LOCK_DIR/pid" 2>/dev/null || true)"
  if [[ "$existing_pid" =~ ^[0-9]+$ ]] && kill -0 "$existing_pid" >/dev/null 2>&1; then
    printf '已有换号流程正在运行 (pid %s)，请等待上一轮完成。\n' "$existing_pid" >&2
    exit 1
  fi

  rm -rf "$LOCK_DIR"
  if mkdir "$LOCK_DIR" 2>/dev/null; then
    LOCK_HELD=1
    printf '%s\n' "$$" >"$LOCK_DIR/pid"
    return 0
  fi

  printf '无法创建换号锁：%s\n' "$LOCK_DIR" >&2
  exit 1
}

print_pool_summary() {
  local json_file="$1"
  if [[ "$(jq -r 'has("pool") and (.pool | type == "object")' "$json_file")" != "true" ]]; then
    return 0
  fi

  local total_accounts available_count overall_fiveh overall_weekly weekly_label preview_count
  total_accounts="$(jq -r '.pool.total_accounts // 0' "$json_file")"
  available_count="$(jq -r '.pool.available_count // 0' "$json_file")"
  overall_fiveh="$(jq -r '.pool.overall_fiveh_remaining // 0' "$json_file")"
  overall_weekly="$(jq -r '.pool.overall_weekly_remaining // -1' "$json_file")"
  if [[ "$overall_weekly" =~ ^-?[0-9]+$ ]] && [[ "$overall_weekly" -ge 0 ]]; then
    weekly_label="${overall_weekly}%"
  else
    weekly_label="无周窗口"
  fi

  printf '账号池概览: 可用 %s/%s | 5h 整体剩余 %s%% | 周整体剩余 %s\n' \
    "$available_count" "$total_accounts" "$overall_fiveh" "$weekly_label"

  preview_count="$(jq -r '.pool.preview | length' "$json_file")"
  if [[ "$preview_count" -gt 0 ]]; then
    printf '账号池可用预览:\n'
    jq -r '
      .pool.preview[]
      | [
          (.email // "-"),
          (.plan // "-") + (if .source != "api" then " (⚠️失效)" else "" end),
          ("5h=" + ((.fiveh_remaining | tostring) + "%")),
          ("weekly=" + (if (has("weekly_limit_present") and (.weekly_limit_present == false)) then "无周窗口" else ((.weekly_remaining | tostring) + "%") end)),
          ("available=" + (.available | tostring))
        ]
      | @tsv
    ' "$json_file" | column -t -s $'\t'
  else
    unavailable_count="$(jq -r '(.pool.unavailable_preview // []) | length' "$json_file")"
    if [[ "$unavailable_count" -gt 0 ]]; then
      printf '账号池不可用诊断:\n'
      jq -r '
        (.pool.unavailable_preview // [])[]
        | [
            (.email // "-"),
            (.plan // "-"),
            ("5h=" + ((.fiveh_remaining | tostring) + "%")),
            ("weekly=" + (if (has("weekly_limit_present") and (.weekly_limit_present == false)) then "无周窗口" else ((.weekly_remaining | tostring) + "%") end)),
            ("reason=" + (.reason // .source // "unknown"))
          ]
        | @tsv
      ' "$json_file" | column -t -s $'\t'
    fi
  fi
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
      INCLUDE_ACTIVE=1
      ;;
    --switch-only)
      MODE="switch-only"
      ;;
    --relaunch)
      MODE="relaunch"
      ;;
    --selection-plan)
      shift
      [[ $# -gt 0 ]] || {
        printf 'missing value for --selection-plan\n' >&2
        exit 1
      }
      SELECTION_PLAN="$1"
      ;;
    --force-email)
      shift
      [[ $# -gt 0 ]] || {
        printf 'missing value for --force-email\n' >&2
        exit 1
      }
      FORCE_EMAIL="$1"
      ;;
    --exclude-plan)
      shift
      [[ $# -gt 0 ]] || {
        printf 'missing value for --exclude-plan\n' >&2
        exit 1
      }
      EXCLUDE_PLANS+=("$1")
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

tmp_dir="$(mktemp -d)"
trap cleanup EXIT
acquire_lock

switch_json="$tmp_dir/switch.json"
recycle_json="$tmp_dir/recycle.json"
preload_fallback_reason=""

build_switch_args() {
  local include_plan="$1"

  switch_args=(--json)
  if [[ "$DRY_RUN" -eq 1 ]]; then
    switch_args+=(--dry-run)
  fi
  if [[ "$VERBOSE" -eq 1 ]]; then
    switch_args+=(--verbose)
  fi
  if [[ "$INCLUDE_ACTIVE" -eq 1 ]]; then
    switch_args+=(--include-active)
  fi
  if [[ "$include_plan" -eq 1 ]] && [[ -n "$SELECTION_PLAN" ]] && [[ -z "$FORCE_EMAIL" ]]; then
    switch_args+=(--use-plan "$SELECTION_PLAN")
  fi
  if [[ -n "$FORCE_EMAIL" ]]; then
    switch_args+=(--force-email "$FORCE_EMAIL")
  fi
  if [[ ${#EXCLUDE_PLANS[@]} -gt 0 ]] && [[ -z "$FORCE_EMAIL" ]]; then
    for p in "${EXCLUDE_PLANS[@]}"; do
      switch_args+=(--exclude-plan "$p")
    done
  fi
}

run_switch() {
  set +e
  "$SWITCH_SCRIPT" "${switch_args[@]}" >"$switch_json"
  set -e
}

build_switch_args 1
run_switch

switch_status="$(jq -r '.status // "failed"' "$switch_json" 2>/dev/null || printf 'failed')"
if [[ -n "$SELECTION_PLAN" ]] && [[ -z "$FORCE_EMAIL" ]]; then
  case "$switch_status" in
    stale_plan|target_unavailable|unusable_plan|excluded_plan)
      preload_fallback_reason="$switch_status"
      build_switch_args 0
      run_switch
      switch_status="$(jq -r '.status // "failed"' "$switch_json" 2>/dev/null || printf 'failed')"
      ;;
  esac
fi

if [[ "$switch_status" == "no_available" ]]; then
  printf '当前所有账号均无可用额度\n'
  print_pool_summary "$switch_json"
  exit 1
fi

if [[ "$switch_status" == "target_unavailable" ]]; then
  printf '指定账号当前不可用，未切换账号。\n'
  if [[ "$(jq -r 'has("account") and (.account | type == "object")' "$switch_json" 2>/dev/null)" == "true" ]]; then
    printf '目标账号: %s\n' "$(jq -r '.account.email // "-"' "$switch_json")"
    printf '额度来源: %s\n' "$(jq -r '.account.source // "-"' "$switch_json")"
    printf '5h 剩余: %s%%\n' "$(jq -r '.account.fiveh_remaining // -1' "$switch_json")"
    if [[ "$(jq -r 'if (.account | has("weekly_limit_present")) then (if .account.weekly_limit_present then 1 else 0 end) else 1 end' "$switch_json")" -eq 1 ]]; then
      printf '周额度剩余: %s%%\n' "$(jq -r '.account.weekly_remaining // -1' "$switch_json")"
    else
      printf '周额度剩余: 无周窗口\n'
    fi
  fi
  print_pool_summary "$switch_json"
  exit 1
fi

if [[ "$switch_status" != "ok" ]]; then
  printf '换号阶段失败。\n' >&2
  cat "$switch_json" >&2
  exit 1
fi

recycle_status="skipped"
case "$MODE" in
  switch-only)
    jq -cn '{status:"skipped"}' >"$recycle_json"
    ;;
  relaunch)
    recycle_args=(--json)
    if [[ "$DRY_RUN" -eq 1 ]]; then
      recycle_args+=(--dry-run)
    fi
    if [[ "$VERBOSE" -eq 1 ]]; then
      recycle_args+=(--verbose)
    fi
    if "$RELAUNCH_SCRIPT" "${recycle_args[@]}" >"$recycle_json"; then
      recycle_status="$(jq -r '.status' "$recycle_json")"
    else
      recycle_status="$(jq -r '.status // "failed"' "$recycle_json" 2>/dev/null || printf 'failed')"
    fi
    ;;
esac

display_name="$(jq -r '.account.display_name' "$switch_json")"
email="$(jq -r '.account.email' "$switch_json")"
plan="$(jq -r '.account.plan' "$switch_json")"
source="$(jq -r '.account.source' "$switch_json")"
fiveh_remaining="$(jq -r '.account.fiveh_remaining' "$switch_json")"
weekly_remaining="$(jq -r '.account.weekly_remaining' "$switch_json")"
weekly_limit_present="$(jq -r 'if (.account | has("weekly_limit_present")) then (if .account.weekly_limit_present then 1 else 0 end) else 1 end' "$switch_json")"

printf '目标账号: %s\n' "$display_name"
if [[ "$display_name" != "$email" ]]; then
  printf '邮箱: %s\n' "$email"
fi
printf '套餐: %s\n' "$plan"
printf '5h 剩余: %s%%\n' "$fiveh_remaining"
if [[ "$weekly_limit_present" -eq 1 ]]; then
  printf '周额度剩余: %s%%\n' "$weekly_remaining"
else
  printf '周额度剩余: 无周窗口\n'
fi
printf '额度来源: %s\n' "$source"
if [[ -n "$preload_fallback_reason" ]]; then
  printf '预加载候选未通过执行前校验，已改用实时选号。原因: %s\n' "$preload_fallback_reason"
fi
printf '生效策略: %s\n' "$MODE"
print_pool_summary "$switch_json"

final_exit=0
case "$recycle_status" in
  ok)
    if [[ "$(jq -r '.was_running' "$recycle_json")" == "true" ]]; then
      printf 'Codex.app 已重启。\n'
      printf '退出方式: %s\n' "$(jq -r '.quit_method // "unknown"' "$recycle_json")"
      printf '旧主进程 PID: %s\n' "$(jq -r '.old_main_pid' "$recycle_json")"
      printf '新主进程 PID: %s\n' "$(jq -r '.new_main_pid' "$recycle_json")"
    else
      printf 'Codex.app 已启动。\n'
      printf '主进程 PID: %s\n' "$(jq -r '.new_main_pid' "$recycle_json")"
    fi
    ;;
  dry_run)
    printf 'Dry run only，未真正重启 Codex.app。\n'
    ;;
  skipped)
    printf '只完成了账号切换，未对 Codex.app 做额外动作。\n'
    ;;
  app_not_running)
    printf 'Codex.app 当前未运行，只完成了账号切换。\n'
    ;;
  quit_timeout)
    printf '账号已确认，但 Codex.app 未能在预期时间内退出。\n'
    printf '退出方式: %s\n' "$(jq -r '.quit_method // "unknown"' "$recycle_json" 2>/dev/null || printf 'unknown')"
    printf '建议先手动关闭 Codex.app，再重新打开。\n'
    final_exit=1
    ;;
  launch_timeout)
    printf '账号已确认，但未在预期时间内确认 Codex.app 已重新启动。\n'
    printf '建议手动点开一次 Codex.app 验证新账号是否已生效。\n'
    final_exit=1
    ;;
  launch_failed)
    printf '账号已确认，但系统启动 Codex.app 的 open 命令失败。\n'
    printf '建议手动点开一次 Codex.app 验证新账号是否已生效。\n'
    final_exit=1
    ;;
  inside_codex_host)
    printf '账号已确认，但脚本正在 Codex.app 内部运行，已拒绝关闭当前会话。\n'
    printf '请从 Finder 双击启动器，或在系统终端里执行换号脚本。\n'
    final_exit=1
    ;;
  *)
    printf '账号已确认，但 Codex.app 的后续处理未确认成功。\n'
    printf '你可以手动重新打开 Codex.app，再发起下一条请求验证是否已走新账号。\n'
    final_exit=1
    ;;
esac

exit "$final_exit"
