#!/usr/bin/env bash
set -euo pipefail

CODEX_APP_PATH="/Applications/Codex.app"
CODEX_APP_BIN="/Applications/Codex.app/Contents/MacOS/Codex"
CODEX_APP_BUNDLE_ID="${CODEX_APP_BUNDLE_ID:-com.openai.codex}"
WAIT_TIMEOUT="${WAIT_TIMEOUT:-30}"
WAIT_INTERVAL="${WAIT_INTERVAL:-0.25}"
GRACEFUL_WAIT_TIMEOUT="${GRACEFUL_WAIT_TIMEOUT:-10}"
TERM_WAIT_TIMEOUT="${TERM_WAIT_TIMEOUT:-8}"

DRY_RUN=0
VERBOSE=0
JSON_OUTPUT=0

usage() {
  cat <<'EOF'
Usage:
  codex-app-relaunch.sh [--dry-run] [--verbose] [--json]

Behavior:
  - If Codex.app is running, ask it to quit first
  - Fall back to TERM, then KILL only if the app refuses to exit
  - Wait for the current main process to exit
  - Launch /Applications/Codex.app again
  - Stop if Codex.app does not exit within the configured timeout
EOF
}

debug() {
  if [[ "$VERBOSE" -eq 1 ]] && [[ "$JSON_OUTPUT" -eq 0 ]]; then
    printf '[debug] %s\n' "$*" >&2
  fi
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'missing required command: %s\n' "$1" >&2
    exit 1
  }
}

find_main_pid() {
  ps -axo pid=,ppid=,command= | awk -v bin="$CODEX_APP_BIN" '
    {
      cmd = substr($0, index($0, $3))
      if (cmd == bin || index(cmd, bin " ") == 1) {
        print $1
        exit
      }
    }
  '
}

running_inside_codex_app() {
  local pid ppid command
  pid="$$"

  while [[ "$pid" =~ ^[0-9]+$ ]] && [[ "$pid" -gt 1 ]]; do
    read -r ppid command < <(ps -p "$pid" -o ppid=,command= 2>/dev/null || true)
    [[ -n "${ppid:-}" ]] || break

    if [[ "${command:-}" == "$CODEX_APP_BIN"* ]] ||
       [[ "${command:-}" == *"/Applications/Codex.app/Contents/Resources/codex app-server"* ]]; then
      return 0
    fi

    pid="$ppid"
  done

  return 1
}

now_epoch_ms() {
  local s ns
  read -r s ns < <(date +'%s %N' 2>/dev/null || date +'%s 000000000')
  ns="${ns:-000000000}"
  printf '%s%03d\n' "$s" "$((10#${ns:0:3}))"
}

sleep_interval() {
  sleep "$WAIT_INTERVAL"
}

wait_until_missing() {
  local pid="$1"
  local timeout="${2:-$WAIT_TIMEOUT}"
  local deadline_ms
  deadline_ms="$(( $(now_epoch_ms) + $(awk -v t="$timeout" 'BEGIN{printf "%d", t*1000}') ))"

  while kill -0 "$pid" >/dev/null 2>&1; do
    if [[ "$(now_epoch_ms)" -le "$deadline_ms" ]]; then
      sleep_interval
    else
      return 1
    fi
  done

  return 0
}

request_graceful_quit() {
  command -v osascript >/dev/null 2>&1 || return 1
  osascript -e "tell application id \"$CODEX_APP_BUNDLE_ID\" to quit" >/dev/null 2>&1
}

launch_codex_app() {
  open -b "$CODEX_APP_BUNDLE_ID" >/dev/null 2>&1 || open "$CODEX_APP_PATH" >/dev/null 2>&1
}

terminate_main_pid() {
  local pid="$1"

  quit_method="osascript"
  debug "requesting Codex.app graceful quit: pid $pid"
  if request_graceful_quit && wait_until_missing "$pid" "$GRACEFUL_WAIT_TIMEOUT"; then
    return 0
  fi

  quit_method="term"
  debug "sending TERM to Codex.app main process: pid $pid"
  kill -TERM "$pid" >/dev/null 2>&1 || true
  if wait_until_missing "$pid" "$TERM_WAIT_TIMEOUT"; then
    return 0
  fi

  quit_method="kill"
  debug "sending KILL to Codex.app main process: pid $pid"
  kill -KILL "$pid" >/dev/null 2>&1 || true
  wait_until_missing "$pid" "$WAIT_TIMEOUT"
}

wait_for_new_main_pid() {
  local exclude_pid="${1:-}"
  local deadline_ms
  deadline_ms="$(( $(now_epoch_ms) + $(awk -v t="$WAIT_TIMEOUT" 'BEGIN{printf "%d", t*1000}') ))"

  while :; do
    local pid
    pid="$(find_main_pid || true)"
    if [[ -n "$pid" ]] && [[ "$pid" != "$exclude_pid" ]]; then
      printf '%s\n' "$pid"
      return 0
    fi

    if [[ "$(now_epoch_ms)" -le "$deadline_ms" ]]; then
      sleep_interval
    else
      return 1
    fi
  done
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      ;;
    --verbose)
      VERBOSE=1
      ;;
    --json)
      JSON_OUTPUT=1
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

require_cmd ps
require_cmd open
require_cmd kill
require_cmd jq
require_cmd awk
require_cmd date

[[ -d "$CODEX_APP_PATH" ]] || {
  printf 'Codex.app not found: %s\n' "$CODEX_APP_PATH" >&2
  exit 1
}

old_main_pid="$(find_main_pid || true)"
was_running=0
if [[ -n "$old_main_pid" ]]; then
  was_running=1
fi

if [[ "$DRY_RUN" -eq 0 ]] && [[ "$was_running" -eq 1 ]] && running_inside_codex_app; then
  if [[ "$JSON_OUTPUT" -eq 1 ]]; then
    jq -cn \
      --arg old_main_pid "$old_main_pid" \
      '{
        status:"inside_codex_host",
        was_running:true,
        old_main_pid: ($old_main_pid | tonumber)
      }'
  else
    printf '当前脚本运行在 Codex.app 内部，为避免关闭正在执行的会话，已停止自动退出/重启。\n'
    printf '请从 Finder 双击启动器，或在系统终端里执行换号脚本。\n'
  fi
  exit 1
fi

if [[ "$DRY_RUN" -eq 1 ]]; then
  if [[ "$JSON_OUTPUT" -eq 1 ]]; then
    jq -cn \
      --arg old_main_pid "${old_main_pid:-0}" \
      --argjson was_running "$was_running" \
      '{
        status:"dry_run",
        was_running: ($was_running == 1),
        old_main_pid: ($old_main_pid | tonumber)
      }'
  else
    if [[ "$was_running" -eq 1 ]]; then
      printf 'Dry run only, no process changed.\n'
      printf '当前 Codex.app 主进程 PID: %s\n' "$old_main_pid"
    else
      printf 'Dry run only, Codex.app 当前未运行；真实执行时会直接启动它。\n'
    fi
  fi
  exit 0
fi

if [[ "$was_running" -eq 1 ]]; then
  if ! terminate_main_pid "$old_main_pid"; then
    if [[ "$JSON_OUTPUT" -eq 1 ]]; then
      jq -cn \
        --arg old_main_pid "$old_main_pid" \
        --arg quit_method "${quit_method:-unknown}" \
        '{
          status:"quit_timeout",
          old_main_pid: ($old_main_pid | tonumber),
          quit_method:$quit_method
        }'
    else
      printf 'Codex.app 主进程未在 %ss 内结束，已停止自动重启。\n' "$WAIT_TIMEOUT"
    fi
    exit 1
  fi
fi

debug "launching Codex.app"
if ! launch_codex_app; then
  if [[ "$JSON_OUTPUT" -eq 1 ]]; then
    jq -cn \
      --arg old_main_pid "${old_main_pid:-0}" \
      --argjson was_running "$was_running" \
      '{
        status:"launch_failed",
        was_running: ($was_running == 1),
        old_main_pid: ($old_main_pid | tonumber)
      }'
  else
    printf 'Codex.app 启动命令执行失败。\n'
  fi
  exit 1
fi

new_main_pid="$(wait_for_new_main_pid "${old_main_pid:-}" || true)"
if [[ -z "$new_main_pid" ]]; then
  if [[ "$JSON_OUTPUT" -eq 1 ]]; then
    jq -cn \
      --arg old_main_pid "${old_main_pid:-0}" \
      --argjson was_running "$was_running" \
      '{
        status:"launch_timeout",
        was_running: ($was_running == 1),
        old_main_pid: ($old_main_pid | tonumber)
      }'
  else
    printf 'Codex.app 已尝试启动，但未在 %ss 内确认到新主进程。\n' "$WAIT_TIMEOUT"
  fi
  exit 1
fi

if [[ "$JSON_OUTPUT" -eq 1 ]]; then
  jq -cn \
    --arg old_main_pid "${old_main_pid:-0}" \
    --arg new_main_pid "$new_main_pid" \
    --arg quit_method "${quit_method:-none}" \
    --argjson was_running "$was_running" \
    '{
      status:"ok",
      was_running: ($was_running == 1),
      old_main_pid: ($old_main_pid | tonumber),
      new_main_pid: ($new_main_pid | tonumber),
      quit_method: $quit_method
    }'
else
  if [[ "$was_running" -eq 1 ]]; then
    printf '已重启 Codex.app。\n'
    printf '退出方式: %s\n' "${quit_method:-clean}"
    printf '旧主进程 PID: %s\n' "$old_main_pid"
    printf '新主进程 PID: %s\n' "$new_main_pid"
  else
    printf 'Codex.app 已启动。\n'
    printf '主进程 PID: %s\n' "$new_main_pid"
  fi
fi
