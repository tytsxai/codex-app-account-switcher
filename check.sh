#!/bin/bash
# 项目自检：发版前手动跑一次，等价于一条最小化 CI。
# 覆盖：bash 语法 / node 语法 / shellcheck（缺失则跳过）。
# 失败立即非零退出，方便接入 git hook 或手动 gating。

export LANG="${LANG:-en_US.UTF-8}"
export LC_ALL="${LC_ALL:-en_US.UTF-8}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR" || exit 1

C_OK=$'\033[32m'
C_WARN=$'\033[33m'
C_ERR=$'\033[31m'
C_DIM=$'\033[2m'
C_RESET=$'\033[0m'

fail=0
ran=0

log_ok()   { printf '%s[ OK ]%s %s\n'   "$C_OK"   "$C_RESET" "$1"; }
log_warn() { printf '%s[WARN]%s %s\n'   "$C_WARN" "$C_RESET" "$1"; }
log_err()  { printf '%s[FAIL]%s %s\n'   "$C_ERR"  "$C_RESET" "$1"; }
log_step() { printf '\n%s== %s ==%s\n' "$C_DIM"  "$1" "$C_RESET"; }

shell_files=()
while IFS= read -r f; do
  shell_files+=("$f")
done < <(find . -maxdepth 2 -type f \( -name '*.sh' -o -name '*.command' \) -not -path './.git/*' | sort)

mjs_files=()
while IFS= read -r f; do
  mjs_files+=("$f")
done < <(find . -maxdepth 2 -type f -name '*.mjs' -not -path './.git/*' | sort)

log_step "bash -n（shell 语法）"
for f in "${shell_files[@]}"; do
  ran=$((ran + 1))
  if bash -n "$f" 2>/tmp/check.err; then
    log_ok "$f"
  else
    log_err "$f"
    sed 's/^/    /' /tmp/check.err
    fail=$((fail + 1))
  fi
done
[ ${#shell_files[@]} -eq 0 ] && log_warn "未发现 .sh / .command 文件"

log_step "node --check（mjs 语法）"
if ! command -v node >/dev/null 2>&1; then
  log_warn "node 未安装，跳过 mjs 检查"
else
  for f in "${mjs_files[@]}"; do
    ran=$((ran + 1))
    if node --check "$f" 2>/tmp/check.err; then
      log_ok "$f"
    else
      log_err "$f"
      sed 's/^/    /' /tmp/check.err
      fail=$((fail + 1))
    fi
  done
  [ ${#mjs_files[@]} -eq 0 ] && log_warn "未发现 .mjs 文件"
fi

log_step "shellcheck（静态分析）"
if ! command -v shellcheck >/dev/null 2>&1; then
  log_warn "shellcheck 未安装，跳过（brew install shellcheck）"
else
  for f in "${shell_files[@]}"; do
    # .command 是 zsh 脚本，shellcheck 不支持，跳过
    case "$f" in
      *.command) log_warn "$f [zsh, shellcheck skip]"; continue ;;
    esac
    ran=$((ran + 1))
    if shellcheck -S warning "$f" >/tmp/check.err 2>&1; then
      log_ok "$f"
    else
      log_err "$f"
      sed 's/^/    /' /tmp/check.err
      fail=$((fail + 1))
    fi
  done
fi

log_step "依赖工具自检"
for tool in jq node; do
  if command -v "$tool" >/dev/null 2>&1; then
    log_ok "$tool: $(command -v "$tool")"
  else
    log_err "$tool 未安装（项目脚本强依赖）"
    fail=$((fail + 1))
  fi
done

log_step "公开仓库脱敏检查"
private_user="xiaomo"
invalid_suffix="invalid-sources"
refresh_reused_suffix="reused"
bad_token_suffix="invalidated"
secret_patterns=(
  'outlook\.de'
  'aka\.yeah'
  "/Users/${private_user}"
  "codex-auth账号文件/${invalid_suffix}"
  "refresh_token_${refresh_reused_suffix}"
  "token_${bad_token_suffix}"
  'eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}'
)

for pattern in "${secret_patterns[@]}"; do
  if rg -n --hidden --glob '!.git/**' --glob '!check.sh' --glob '!codex-auth账号文件/**' --glob '!*.DS_Store' "$pattern" . >/tmp/check.err 2>/dev/null; then
    log_err "疑似私有信息匹配: $pattern"
    sed 's/^/    /' /tmp/check.err
    fail=$((fail + 1))
  else
    log_ok "no match: $pattern"
  fi
done

echo
if [ "$fail" -eq 0 ]; then
  printf '%s全部通过%s（执行 %d 项检查）\n' "$C_OK" "$C_RESET" "$ran"
  exit 0
else
  printf '%s失败 %d 项%s（共执行 %d 项检查）\n' "$C_ERR" "$fail" "$C_RESET" "$ran"
  exit 1
fi
