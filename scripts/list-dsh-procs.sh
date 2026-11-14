#!/usr/bin/env bash
# 列出 node 进程，标注哪些是当前这套 DSH
# 用法: bash scripts/list-dsh-procs.sh [--kill]
KILL=0
[ "${1:-}" = "--kill" ] && KILL=1

# 只有显式设置 DSH_PROC_ISOLATE 时才做前缀隔离
# 不用 DSH_HOME：那是宿主自己设的，会导致真实进程被误标为"其他实例"
DSH_PREFIX="${DSH_PROC_ISOLATE:-}"

ps -eo pid=,command= 2>/dev/null | while read -r pid cmd; do
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
  short=$(printf '%s' "$cmd" | cut -c1-78)
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
