#!/usr/bin/env bash
# 列出 node 进程，标注哪些是当前这套 DSH
# 用法: bash scripts/list-dsh-procs.sh [--kill]
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
KILL=0
[ "${1:-}" = "--kill" ] && KILL=1

# 只有显式设置 DSH_PROC_ISOLATE 时才做前缀隔离
# 不用 DSH_HOME：那是宿主自己设的，会导致真实进程被误标为"其他实例"
DSH_PREFIX="${DSH_PROC_ISOLATE:-}"

# Git Bash 的 ps 不支持 -eo；Windows 上改用 PowerShell
is_windows() {
  case "$(uname -s 2>/dev/null)" in
    MINGW*|MSYS*|CYGWIN*) return 0 ;;
  esac
  return 1
}

emit_procs() {
  if is_windows; then
    local ps1="$SCRIPT_DIR/detect-dsh-procs.ps1"
    if [ ! -f "$ps1" ]; then
      printf 'QUERY_FAIL|找不到 %s\n' "$ps1"
      return 0
    fi

    # Git Bash 的 /d/a/... 路径 PowerShell -File 不认，必须转成 D:\a\...
    local WPS1="$ps1"
    if command -v cygpath >/dev/null 2>&1; then
      WPS1="$(cygpath -w "$ps1" 2>/dev/null)" || WPS1="$ps1"
      [ -z "$WPS1" ] && WPS1="$ps1"
    fi

    local SELF OUT RC
    for SELF in powershell pwsh powershell.exe; do
      if command -v "$SELF" >/dev/null 2>&1; then
        # 不要 2>/dev/null：PowerShell 的错误要能看见，否则排查时一片空白
        OUT="$("$SELF" -NoProfile -ExecutionPolicy Bypass -File "$WPS1" 2>&1)"
        RC=$?
        if [ "$RC" -ne 0 ]; then
          printf 'QUERY_FAIL|PowerShell 退出码 %s: %s\n' "$RC" "$(printf '%s' "$OUT" | head -3 | tr '\n' ' ')"
          return 0
        fi
        if [ -z "$OUT" ]; then
          printf 'QUERY_FAIL|PowerShell 无输出（路径: %s）\n' "$WPS1"
          return 0
        fi
        printf '%s\n' "$OUT" | tr -d '\r'
        return 0
      fi
    done
    printf 'QUERY_FAIL|找不到 powershell / pwsh\n'
    return 0
  fi
  # Unix：ps 输出 "  1234 command..."，转成 "1234|other|command..."
  ps -eo pid=,command= 2>/dev/null | sed -n 's/^ *\([0-9][0-9]*\) */\1|other|/p'
}

emit_procs | while read -r line; do
  # 统一格式：
  #   pid|DSH|cmd | pid|other|cmd | pid|APP|cmd
  #   QUERY_FAIL|reason | QUERY_OK_NO_MATCH|...
  case "$line" in
    QUERY_FAIL\|*)
      printf 'QUERY_FAIL %s\n' "${line#QUERY_FAIL|}"
      continue
      ;;
    QUERY_OK_NO_MATCH*)
      printf 'QUERY_OK_NO_MATCH\n'
      continue
      ;;
  esac

  pid="${line%%|*}"
  rest="${line#*|}"
  kind="${rest%%|*}"
  cmd="${rest#*|}"

  case "$kind" in
    DSH)
      is_dsh=1
      ;;
    APP)
      printf 'DSH   PID=%-7s %s  [桌面版 App]\n' "$pid" "$cmd"
      echo "$pid" >> /tmp/.dsh-pids-$$
      continue
      ;;
    other)
      is_dsh=0
      ;;
    *)
      # 非 Windows 的 pid|cmd 格式，回退
      cmd="$rest"
      is_dsh=0
      ;;
  esac
  [ -z "$pid" ] && continue
  case "$cmd" in
    *list-dsh-procs*) continue ;;
  esac
  is_dsh=0
  case "$cmd" in
    *"@deepseek-ai/dsh/lib/bin.js"*)  is_dsh=1 ;;
    */bin/dsh\ web*)                 is_dsh=1 ;;
    */bin/dsh\ serve*)               is_dsh=1 ;;
    "dsh web"*|"dsh serve"*)         is_dsh=1 ;;
    *"DeepSeek Harness.app/Contents/MacOS/"*) is_dsh=1 ;;
  esac

  # DSH_HOME 隔离：只认命令行里出现该路径的进程
  if [ "$is_dsh" = "1" ] && [ -n "$DSH_PREFIX" ]; then
    case "$cmd" in
      *"$DSH_PREFIX"*) ;;
      *) is_dsh=2 ;;   # 2 = 是 DSH 但不是这个 DSH_HOME 的
    esac
  fi
  short=$(printf '%s' "$cmd" | cut -c1-160)
  if [ "$is_dsh" = "1" ]; then
    printf 'DSH   PID=%-7s %s\n' "$pid" "$short"
    echo "$pid" >> /tmp/.dsh-pids-$$
  elif [ "$is_dsh" = "2" ]; then
    printf 'other PID=%-7s %s  [其他 DSH_HOME，不动]\n' "$pid" "$short"
  else
    case "$cmd" in
      *node*) printf 'other PID=%-7s %s\n' "$pid" "$short" ;;
    esac
  fi
done

if [ "$KILL" = "1" ] && [ -f "/tmp/.dsh-pids-$$" ]; then
  echo ""
  echo "=== 停止 DSH 进程 ==="
  while read -r pid; do kill "$pid" 2>/dev/null && echo "  已停 PID=$pid"; done < "/tmp/.dsh-pids-$$"
  sleep 2
  while read -r pid; do kill -9 "$pid" 2>/dev/null; done < "/tmp/.dsh-pids-$$" 2>/dev/null
fi
[ -f "/tmp/.dsh-pids-$$" ] && rm -f "/tmp/.dsh-pids-$$"
if [ "$KILL" = "0" ]; then
  echo ""
  echo "以上标 DSH 的是本次要停的；标 other 的不动。"
  echo "确认无误后加 --kill 参数执行停止。"
fi
