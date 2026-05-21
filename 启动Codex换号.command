#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET_SCRIPT="$SCRIPT_DIR/codex-app-hot-switch.sh"
AUTH_SCRIPT="$SCRIPT_DIR/codex-auth-smart-switch.sh"
FREE_LOAD_SCRIPT="$SCRIPT_DIR/codex-auth-load-free.mjs"
REGISTRY_FILE="${CODEX_HOME:-$HOME/.codex}/accounts/registry.json"
RUN_LOG="$(mktemp -t codex-hot-switch.XXXXXX.log)"
PLAN_FILE="$(mktemp -t codex-hot-switch-plan.XXXXXX.json)"
POOL_PREVIEW_LIMIT="${POOL_PREVIEW_LIMIT:-0}"
PRO_EMAIL="${PRO_EMAIL:-}"

resolve_pro_email() {
  [[ -f "$REGISTRY_FILE" ]] || { printf '\n'; return; }
  if [[ -n "$PRO_EMAIL" ]]; then
    if jq -e --arg e "$PRO_EMAIL" '.accounts[] | select(.plan == "pro" and ((.email // "") | ascii_downcase) == ($e | ascii_downcase))' "$REGISTRY_FILE" >/dev/null 2>&1; then
      printf '%s\n' "$PRO_EMAIL"
      return
    fi
  fi
  jq -r '[.accounts[] | select(.plan == "pro")] | (.[0].email // "")' "$REGISTRY_FILE" 2>/dev/null
}

cleanup() {
  rm -f "$RUN_LOG" "$PLAN_FILE"
}

trap cleanup EXIT

if [[ -t 1 ]]; then
  C_RESET=$'\033[0m'
  C_TITLE=$'\033[1;36m'
  C_STEP=$'\033[1;34m'
  C_OK=$'\033[1;32m'
  C_WARN=$'\033[1;33m'
  C_ERR=$'\033[1;31m'
  C_DIM=$'\033[2m'
else
  C_RESET=''
  C_TITLE=''
  C_STEP=''
  C_OK=''
  C_WARN=''
  C_ERR=''
  C_DIM=''
fi

section() {
  printf '%s%s%s\n' "$C_STEP" "$1" "$C_RESET"
}

info() {
  printf '%s%s%s\n' "$C_DIM" "$1" "$C_RESET"
}

success() {
  printf '%s%s%s\n' "$C_OK" "$1" "$C_RESET"
}

warning() {
  printf '%s%s%s\n' "$C_WARN" "$1" "$C_RESET"
}

failure() {
  printf '%s%s%s\n' "$C_ERR" "$1" "$C_RESET"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    clear
    printf '%sCodex.app 换号启动器%s\n\n' "$C_TITLE" "$C_RESET"
    section "[1/3] 启动前检查"
    failure "缺少依赖命令：$1"
    echo
    read -r "?按回车关闭..."
    exit 1
  }
}

extract_line() {
  local prefix="$1"
  local value
  value="$(grep -m1 "^${prefix}" "$RUN_LOG" 2>/dev/null || true)"
  if [[ -n "$value" ]]; then
    printf '%s\n' "$value"
  fi
}

show_preloaded_summary() {
  [[ -f "$PLAN_FILE" ]] || return 0

  local plan_status
  plan_status="$(jq -r '.status // "unknown"' "$PLAN_FILE")"

  if [[ "$plan_status" == "ok" ]]; then
    local _next_weekly
    if [[ "$(jq -r 'if (.account | has("weekly_limit_present")) then (if .account.weekly_limit_present then 1 else 0 end) else 1 end' "$PLAN_FILE")" -eq 1 ]]; then
      _next_weekly="$(jq -r '.account.weekly_remaining // -1' "$PLAN_FILE")%"
    else
      _next_weekly="无周窗口"
    fi
    printf '下一候选: %s | %s | 5h %s%% | 周 %s\n' \
      "$(jq -r '.account.display_name // .account.email // "-"' "$PLAN_FILE")" \
      "$(jq -r '.account.plan // "-"' "$PLAN_FILE")" \
      "$(jq -r '.account.fiveh_remaining // -1' "$PLAN_FILE")" \
      "$_next_weekly"
  elif [[ "$plan_status" == "no_available" ]]; then
    warning "预加载完成：当前没有可用账号。"
  else
    warning "预加载结果异常：$plan_status"
  fi

  if [[ "$(jq -r 'has("pool") and (.pool | type == "object")' "$PLAN_FILE")" == "true" ]]; then
    local _available _total _fiveh _weekly _weekly_label _stale _fresh
    _available="$(jq -r '.pool.available_count // 0' "$PLAN_FILE")"
    _total="$(jq -r '.pool.total_accounts // 0' "$PLAN_FILE")"
    _fiveh="$(jq -r '.pool.overall_fiveh_remaining // 0' "$PLAN_FILE")"
    _weekly="$(jq -r '.pool.overall_weekly_remaining // -1' "$PLAN_FILE")"
    _stale="$(jq -r '.pool.stale_count // 0' "$PLAN_FILE")"
    _fresh="$(jq -r '.pool.fresh_count // 0' "$PLAN_FILE")"
    if [[ "$_weekly" =~ ^-?[0-9]+$ ]] && [[ "$_weekly" -ge 0 ]]; then
      _weekly_label="${_weekly}%"
    else
      _weekly_label="无周窗口"
    fi

    printf '账号池概览: 可用 %s/%s | 5h 整体剩余 %s%% | 周整体剩余 %s (基于 %s 个已刷新账号)\n' \
      "$_available" "$_total" "$_fiveh" "$_weekly_label" "$_fresh"
    if [[ "$_stale" -gt 0 ]]; then
      printf '  其中 %s 个账号未通过实时刷新，未计入整体平均\n' "$_stale"
    fi

    if [[ "$(jq -r '.pool.preview | length' "$PLAN_FILE")" -gt 0 ]]; then
      printf '可用列表:\n'
      jq -r --argjson limit "$POOL_PREVIEW_LIMIT" '
        (
          if $limit > 0 then
            .pool.preview[:$limit]
          else
            .pool.preview
          end
        )
        | to_entries[]
        | [
            ((.key + 1) | tostring),
            (.value.email // "-"),
            (.value.plan // "-") + (if (.value.source // "cache") != "api" then " (⚠️失效)" else "" end),
            ("5h " + ((.value.fiveh_remaining | tostring) + "%")),
            ("周 " + (if ((.value | has("weekly_limit_present")) and (.value.weekly_limit_present == false)) then "无周窗口" else ((.value.weekly_remaining | tostring) + "%") end))
          ]
        | @tsv
      ' "$PLAN_FILE" | column -t -s $'\t'
    elif [[ "$(jq -r '(.pool.unavailable_preview // []) | length' "$PLAN_FILE")" -gt 0 ]]; then
      printf '不可用诊断:\n'
      jq -r --argjson limit "$POOL_PREVIEW_LIMIT" '
        (
          if $limit > 0 then
            (.pool.unavailable_preview // [])[:$limit]
          else
            (.pool.unavailable_preview // [])
          end
        )
        | to_entries[]
        | [
            ((.key + 1) | tostring),
            (.value.email // "-"),
            (.value.plan // "-"),
            ("5h " + ((.value.fiveh_remaining | tostring) + "%")),
            ("周 " + (if ((.value | has("weekly_limit_present")) and (.value.weekly_limit_present == false)) then "无周窗口" else ((.value.weekly_remaining | tostring) + "%") end)),
            ("原因 " + (.value.reason // .value.source // "unknown"))
          ]
        | @tsv
      ' "$PLAN_FILE" | column -t -s $'\t'
    fi
  fi
}

preload_plan() {
  local tmp_plan="$PLAN_FILE.tmp"
  rm -f "$PLAN_FILE" "$tmp_plan"

  set +e
  SHOW_ALL_ACCOUNTS=1 "$AUTH_SCRIPT" --dry-run --json --verbose >"$tmp_plan"
  local preload_exit=$?
  set -e

  if [[ "$preload_exit" -ne 0 ]] || [[ ! -s "$tmp_plan" ]]; then
    rm -f "$tmp_plan"
    return 1
  fi

  mv "$tmp_plan" "$PLAN_FILE"
  return 0
}

preload_and_show() {
  if preload_plan; then
    success "账号池预加载完成"
    show_preloaded_summary
  else
    warning "账号池预加载失败，本轮将走实时选择。"
  fi
}

print_shortcuts() {
  echo
  printf '快捷指令:\n'
  printf '  回车 / s  普通换号并重启 Codex.app\n'
  printf '  p          强制切到 Pro 账号并重启 Codex.app\n'
  printf '  l          codex-auth login\n'
  printf '  d          codex-auth login --device-auth\n'
  printf '  a          codex-auth list --api\n'
  printf '  t          codex-auth status\n'
  printf '  c          codex-auth clean\n'
  printf '  f          扫描并导入有额度的 Free 账号\n'
  printf '  u          检查不可用账号，不删除\n'
  printf '  x          清理不可用账号，需要二次确认\n'
  printf '  r          重新预加载账号池\n'
  printf '  h          显示快捷指令\n'
  printf '  q          关闭\n'
}

wait_return() {
  echo
  read -r "?按回车返回启动器..."
}

run_logged_command() {
  local title="$1"
  shift

  clear
  printf '%sCodex.app 换号启动器%s\n\n' "$C_TITLE" "$C_RESET"
  section "$title"
  printf '执行命令:'
  printf ' %q' "$@"
  printf '\n\n'

  : >"$RUN_LOG"
  local start_ts end_ts elapsed cmd_exit
  start_ts="$(date +%s)"

  set +e
  "$@" 2>&1 | tee "$RUN_LOG"
  cmd_exit=$pipestatus[1]
  set -e

  end_ts="$(date +%s)"
  elapsed="$((end_ts - start_ts))"
  echo
  if [[ "$cmd_exit" -eq 0 ]]; then
    success "命令完成"
  else
    failure "命令失败，退出码：$cmd_exit"
  fi
  info "耗时：${elapsed}s"
  wait_return
  return "$cmd_exit"
}

show_home() {
  clear
  printf '%sCodex.app 换号启动器%s\n\n' "$C_TITLE" "$C_RESET"
  section "[1/3] 启动前检查"
  success "已找到主脚本"
  info "正在预加载账号池，请稍等。"
  echo
  preload_and_show
}

if [[ ! -x "$TARGET_SCRIPT" ]]; then
  clear
  printf '%sCodex.app 换号启动器%s\n\n' "$C_TITLE" "$C_RESET"
  section "[1/3] 启动前检查"
  failure "未找到可执行脚本：$TARGET_SCRIPT"
  echo
  read -r "?按回车关闭..."
  exit 1
fi

if [[ ! -x "$AUTH_SCRIPT" ]]; then
  clear
  printf '%sCodex.app 换号启动器%s\n\n' "$C_TITLE" "$C_RESET"
  section "[1/3] 启动前检查"
  failure "未找到账号预加载脚本：$AUTH_SCRIPT"
  echo
  read -r "?按回车关闭..."
  exit 1
fi

if [[ ! -x "$FREE_LOAD_SCRIPT" ]]; then
  clear
  printf '%sCodex.app 换号启动器%s\n\n' "$C_TITLE" "$C_RESET"
  section "[1/3] 启动前检查"
  failure "未找到 Free 加载脚本：$FREE_LOAD_SCRIPT"
  echo
  read -r "?按回车关闭..."
  exit 1
fi

require_cmd jq
require_cmd curl
require_cmd base64
require_cmd mktemp
require_cmd codex-auth
require_cmd node
require_cmd tee

show_home

PRO_EMAIL="$(resolve_pro_email)"

prompt_action() {
  print_shortcuts
  if [[ -n "$PRO_EMAIL" ]]; then
    printf '\n%s，Pro=%s: ' "$1" "$PRO_EMAIL"
  else
    printf '\n%s: ' "$1"
  fi
}

handle_shortcut() {
  local shortcut="$1"
  case "$shortcut" in
    h|help|'?')
      print_shortcuts
      wait_return
      return 0
      ;;
    r|refresh)
      show_home
      PRO_EMAIL="$(resolve_pro_email)"
      return 0
      ;;
    l|login)
      run_logged_command "[原生命令] codex-auth login" codex-auth login || true
      show_home
      PRO_EMAIL="$(resolve_pro_email)"
      return 0
      ;;
    d|device|device-auth)
      run_logged_command "[原生命令] codex-auth login --device-auth" codex-auth login --device-auth || true
      show_home
      PRO_EMAIL="$(resolve_pro_email)"
      return 0
      ;;
    a|list)
      run_logged_command "[原生命令] codex-auth list --api" codex-auth list --api || true
      show_home
      PRO_EMAIL="$(resolve_pro_email)"
      return 0
      ;;
    t|status)
      run_logged_command "[原生命令] codex-auth status" codex-auth status || true
      show_home
      PRO_EMAIL="$(resolve_pro_email)"
      return 0
      ;;
    c|clean)
      run_logged_command "[原生命令] codex-auth clean" codex-auth clean || true
      show_home
      PRO_EMAIL="$(resolve_pro_email)"
      return 0
      ;;
    f|free|load-free)
      run_logged_command "[维护命令] 扫描并导入 Free 账号" "$FREE_LOAD_SCRIPT" --yes || true
      show_home
      PRO_EMAIL="$(resolve_pro_email)"
      return 0
      ;;
    u|check)
      run_logged_command "[维护命令] 检查不可用账号" "$AUTH_SCRIPT" --cleanup-unusable --dry-run || true
      show_home
      PRO_EMAIL="$(resolve_pro_email)"
      return 0
      ;;
    x|cleanup)
      warning "这会删除已确认不可用账号的 registry 条目和 auth 文件。"
      read -r "?确认清理请输入 YES: " confirm_cleanup
      if [[ "$confirm_cleanup" == "YES" ]]; then
        run_logged_command "[维护命令] 清理不可用账号" "$AUTH_SCRIPT" --cleanup-unusable --yes || true
      else
        warning "已取消清理。"
        wait_return
      fi
      show_home
      PRO_EMAIL="$(resolve_pro_email)"
      return 0
      ;;
  esac

  return 1
}

while true; do
  echo
  prompt_action "输入快捷指令"
  read -r next_action
  action="${next_action:l}"
  if [[ "$action" == "q" || "$action" == "quit" || "$action" == "exit" ]]; then
    exit 0
  fi
  if handle_shortcut "$action"; then
    continue
  fi
  if [[ -z "$action" ]]; then
    action="s"
  fi
  if [[ "$action" != "s" && "$action" != "switch" && "$action" != "p" ]]; then
    warning "未知快捷指令：$action"
    wait_return
    continue
  fi
  if [[ "$action" == "p" ]] && [[ -z "$PRO_EMAIL" ]]; then
    warning "当前没有可用的 Pro 账号，已改走普通换号。"
    action="s"
  fi

  clear
  printf '%sCodex.app 换号启动器%s\n\n' "$C_TITLE" "$C_RESET"

  if [[ "$action" == "p" ]]; then
    section "[2/3] 正在切到 Pro 账号 ($PRO_EMAIL)"
  else
    section "[2/3] 正在执行换号"
  fi
  info "请稍等，这一步可能会持续几十秒。"
  echo

  : >"$RUN_LOG"
  start_ts="$(date +%s)"

  set +e
  if [[ "$action" == "p" ]]; then
    POOL_PREVIEW_LIMIT="$POOL_PREVIEW_LIMIT" "$TARGET_SCRIPT" --force-email "$PRO_EMAIL" >"$RUN_LOG" 2>&1
  elif [[ -s "$PLAN_FILE" ]]; then
    POOL_PREVIEW_LIMIT="$POOL_PREVIEW_LIMIT" "$TARGET_SCRIPT" --selection-plan "$PLAN_FILE" >"$RUN_LOG" 2>&1
  else
    POOL_PREVIEW_LIMIT="$POOL_PREVIEW_LIMIT" "$TARGET_SCRIPT" >"$RUN_LOG" 2>&1
  fi
  exit_code=$?
  set -e

  end_ts="$(date +%s)"
  elapsed="$((end_ts - start_ts))"

  echo
  section "[3/3] 执行结果"
  if [[ "$exit_code" -eq 0 ]]; then
    success "执行完成"
  else
    failure "执行失败，退出码：$exit_code"
  fi

  summary_lines=(
    "$(extract_line '目标账号:')"
    "$(extract_line '邮箱:')"
    "$(extract_line '套餐:')"
    "$(extract_line '5h 剩余:')"
    "$(extract_line '周额度剩余:')"
    "$(extract_line '额度来源:')"
    "$(extract_line '当前所有账号均无可用额度')"
    "$(extract_line '预加载候选未通过执行前校验')"
    "$(extract_line '生效策略:')"
    "$(extract_line 'Codex.app 已重启。')"
    "$(extract_line 'Codex.app 已启动。')"
    "$(extract_line '当前最优账号已经是活动账号')"
    "$(extract_line '只完成了账号切换')"
    "$(extract_line '账号已切换，但')"
    "$(extract_line '退出方式:')"
    "$(extract_line '旧主进程 PID:')"
    "$(extract_line '新主进程 PID:')"
    "$(extract_line '主进程 PID:')"
  )

  for line in "${summary_lines[@]}"; do
    if [[ -n "$line" ]]; then
      printf '%s\n' "$line"
    fi
  done

  info "耗时：${elapsed}s"

  if [[ "$exit_code" -ne 0 ]]; then
    warning "如果刚才窗口信息较多，建议向上翻看本轮输出定位原因。"
    if [[ -s "$RUN_LOG" ]]; then
      echo
      printf '失败摘要:\n'
      tail -n 6 "$RUN_LOG"
    fi
  fi

  echo
  section "[下一轮预加载]"
  info "正在预加载下一轮账号池。"
  echo
  preload_and_show

  PRO_EMAIL="$(resolve_pro_email)"
done
