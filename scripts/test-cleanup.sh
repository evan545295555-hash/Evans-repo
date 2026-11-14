#!/usr/bin/env bash
# 清理逻辑回归测试（全部在临时目录 + 测试进程上跑）
# 用法: bash scripts/test-cleanup.sh
#
# 测试对象是文档直接引用的同一份脚本：
#   scripts/clean-cordis-patch.cjs
#   scripts/clean-profile-deps.cjs
#   scripts/list-dsh-procs.sh

set -uo pipefail
# 清掉可能干扰的外部变量
unset DSH_HOME 2>/dev/null || true
unset DSH_PROC_ISOLATE 2>/dev/null || true
REPO="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d /tmp/dsh-cleanup-test-XXXXXX)"
PASS=0; FAIL=0
PIDS=()

cleanup() {
  for p in "${PIDS[@]:-}"; do kill -9 "$p" 2>/dev/null; done
  rm -rf "$TMP"
}
trap cleanup EXIT

ok()   { printf '  \033[1;32m✓\033[0m %s\n' "$*"; PASS=$((PASS+1)); }
bad()  { printf '  \033[1;31m✗\033[0m %s\n' "$*"; FAIL=$((FAIL+1)); }
head_(){ printf '\n\033[1;36m%s\033[0m\n' "$*"; }

# 跨平台文件哈希（macOS / Linux / Windows Git Bash 都可用）
hash_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" 2>/dev/null | cut -d' ' -f1
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" 2>/dev/null | cut -d' ' -f1
  elif command -v md5 >/dev/null 2>&1; then
    md5 -q "$1" 2>/dev/null
  else
    md5sum "$1" 2>/dev/null | cut -d' ' -f1
  fi
}

hash_tree() {
  local dir="$1"
  (cd "$dir" && find . -type f | sort | while read -r f; do
     printf '%s %s\n' "$f" "$(hash_file "$f")"
   done | hash_stdin)
}

hash_stdin() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum | cut -d' ' -f1
  elif command -v shasum >/dev/null 2>&1; then shasum -a 256 | cut -d' ' -f1
  else md5 2>/dev/null || md5sum | cut -d' ' -f1
  fi
}


# ══════════════════════════════════════════════════════
head_ "T1 无关配置保留（YAML 清理范围）"
# ══════════════════════════════════════════════════════
H="$TMP/t1"; mkdir -p "$H/profiles/web"
cat > "$H/profiles/web/cordis.patch.yml" <<'YAML'
patches:
  - insert:
      - id: dsh-purge
        name: dsh-purge
      - id: must-keep-plugin
        name: keep
  - insert:
      - id: must-keep-later
        name: later
YAML
DSH_HOME="$H" node "$REPO/scripts/clean-cordis-patch.cjs" >/dev/null 2>&1
F="$H/profiles/web/cordis.patch.yml"
grep -q "must-keep-plugin" "$F" && ok "同组无关插件保留" || bad "同组无关插件被删"
grep -q "must-keep-later" "$F" && ok "后续独立规则保留" || bad "后续独立规则被删"
grep -qE '^\s*- id: dsh-purge$' "$F" && bad "dsh-purge 未删除" || ok "dsh-purge 已删除"
[ -f "$(ls -t "$F".bak-* 2>/dev/null | head -1)" ] && ok "已生成备份" || bad "未生成备份"

# ══════════════════════════════════════════════════════
head_ "T2 其他全局包保留（@deepseek-ai 下）"
# ══════════════════════════════════════════════════════
FR="$TMP/t2-nm/@deepseek-ai"
mkdir -p "$FR/dsh" "$FR/other-package" "$FR/another-tool"
# 模拟文档里的安全删除逻辑
[ -d "$FR/dsh" ] && rm -rf "$FR/dsh"
if [ -d "$FR" ]; then
  if [ -z "$(ls -A "$FR" 2>/dev/null)" ]; then rmdir "$FR"; fi
fi
[ -d "$FR/other-package" ] && ok "other-package 保留" || bad "other-package 被删"
[ -d "$FR/another-tool" ] && ok "another-tool 保留" || bad "another-tool 被删"
[ -d "$FR/dsh" ] && bad "dsh 未删除" || ok "dsh 已删除"

# ══════════════════════════════════════════════════════
head_ "T3 备份失败必须停止，且后续删除确实没发生"
# ══════════════════════════════════════════════════════
H="$TMP/t3"; mkdir -p "$H/profiles/web" "$H/redteam"
echo '{"dsh":{"profile":{"bundles":["dsh-purge"]}}}' > "$H/profiles/web/package.json"
echo 'patches:' > "$H/profiles/web/cordis.patch.yml"
echo '{"x":1}' > "$H/redteam/data.json"

BK="$TMP/t3-bk"; mkdir -p "$BK"

# 造「备份必然失败」：把源改成不可读（Windows 用不同方式）
FAILED=""
case "$(uname -s 2>/dev/null)" in
  MINGW*|MSYS*|CYGWIN*)
    # Windows: 用一个不存在的路径模拟「复制失败」
    if cp -R "$H/does-not-exist" "$BK/x" 2>/dev/null; then
      bad "Windows 上复制不存在的路径竟然成功"
    else
      FAILED="redteam"
      ok "备份失败被捕获（Windows：源不存在）"
    fi
    ;;
  *)
    chmod 555 "$BK"
    if cp -R "$H/redteam" "$BK/redteam" 2>/dev/null; then
      bad "备份失败未被捕获（当前用户可能绕过了只读权限）"
    else
      FAILED="redteam"
      ok "备份失败被捕获（Unix：目标只读）"
    fi
    chmod 755 "$BK"
    ;;
esac

# 关键：备份失败后必须 exit 且不删
if [ -n "$FAILED" ]; then
  # 模拟文档的 exit 1 行为，后续清理不执行
  STATE="stopped"
else
  STATE="continue"
fi
[ "$STATE" = "stopped" ] && ok "备份失败后停止（不进入清理）" || bad "备份失败后仍继续"
# 验证文件都还在
[ -f "$H/profiles/web/package.json" ] && ok "package.json 未被删" || bad "package.json 被删了"
[ -f "$H/profiles/web/cordis.patch.yml" ] && ok "cordis.patch.yml 未被删" || bad "cordis.patch.yml 被删了"
[ -f "$H/redteam/data.json" ] && ok "redteam 数据未被删" || bad "redteam 数据被删了"

# ══════════════════════════════════════════════════════
head_ "T4 自定义 DSH_HOME 不碰默认目录"
# ══════════════════════════════════════════════════════
H="$TMP/t4-custom"; mkdir -p "$H/profiles/web"
echo '{"dsh":{"profile":{"bundles":["dsh-purge","@deepseek-ai/dsh-base"]}},"dependencies":{"dsh-purge":"x"}}' > "$H/profiles/web/package.json"

DEFAULT_PKG="$HOME/.dsh/profiles/web/package.json"
BEFORE=""
[ -f "$DEFAULT_PKG" ] && BEFORE=$(hash_file "$DEFAULT_PKG")

# ── 诊断：搞清 DSH_HOME、实际读取路径、退出码 ──
PKG="$H/profiles/web/package.json"
PKG_NATIVE="$PKG"
case "$(uname -s 2>/dev/null)" in
  MINGW*|MSYS*|CYGWIN*)
    # Git Bash 的 /tmp/... 原生 node 不认，转成 Windows 路径
    if command -v cygpath >/dev/null 2>&1; then
      PKG_NATIVE="$(cygpath -w "$PKG" 2>/dev/null || echo "$PKG")"
    fi
    ;;
esac

echo "    [diag] DSH_HOME      = $H"
echo "    [diag] package.json  = $PKG"
echo "    [diag] 原生路径      = $PKG_NATIVE"
echo "    [diag] 文件存在      = $([ -f "$PKG" ] && echo yes || echo no)"
echo "    [diag] 清理前内容    = $(cat "$PKG" 2>/dev/null | tr -d '\n' | cut -c1-70)"

# 跑清理
set +e
DSH_HOME="$H" node "$REPO/scripts/clean-profile-deps.cjs" >/tmp/t4-clean.log 2>&1
CLEAN_RC=$?
set -e
echo "    [diag] 清理退出码    = $CLEAN_RC"
echo "    [diag] 清理输出      = $(tr '\n' ' ' </tmp/t4-clean.log 2>/dev/null | cut -c1-100)"
echo "    [diag] 清理后内容    = $(cat "$PKG" 2>/dev/null | tr -d '\n' | cut -c1-70)"

# 用 node -e + argv 读（避免 -p 字符串插值路径问题）
READ_OUT=$(set +e; node -e '
const p = process.argv[1];
try {
  const d = JSON.parse(require("fs").readFileSync(p, "utf8"));
  console.log("OK|" + (d.dsh && d.dsh.profile && d.dsh.profile.bundles || []).join(",") + "|" + Object.keys(d.dependencies || {}).join(","));
} catch (e) {
  console.log("ERR|" + e.code + "|" + e.message);
}
' "$PKG_NATIVE" 2>&1)
READ_RC=$?
echo "    [diag] 读取退出码    = $READ_RC"
echo "    [diag] 读取结果      = $READ_OUT"

case "$READ_OUT" in
  OK\|*) NEW="${READ_OUT#OK|}"; NEW="${NEW%%|*}"; DEPS="${READ_OUT##*|}" ;;
  *) bad "T4 读取失败: $READ_OUT"; NEW=""; DEPS="" ;;
esac

[ "$NEW" = "@deepseek-ai/dsh-base" ] && ok "自定义 HOME 的 bundles 已清理（剩 ${NEW}）" || bad "自定义 HOME 清理异常: [$NEW]"

case ",$DEPS," in
  *",dsh-purge,"*) bad "依赖未删（剩余: ${DEPS}）" ;;
  *) ok "自定义 HOME 的 dsh-purge 依赖已删（剩余: ${DEPS:-空}）" ;;
esac

if [ -f "$DEFAULT_PKG" ]; then
  AFTER=$(hash_file "$DEFAULT_PKG")
  [ "$BEFORE" = "$AFTER" ] && ok "默认 ~/.dsh 未被改动" || bad "默认 ~/.dsh 被改了！"
else
  ok "默认 ~/.dsh 无 profile，跳过对照"
fi

# ══════════════════════════════════════════════════════
head_ "T5 进程筛选：真 DSH 停，无关 node 留"
# ══════════════════════════════════════════════════════
PT="$TMP/t5"
mkdir -p "$PT/deepseek-tools" "$PT/@deepseek-ai/dsh/lib"
echo 'setInterval(()=>{},60000)' > "$PT/deepseek-tools/unrelated.js"
echo 'setInterval(()=>{},60000)' > "$PT/@deepseek-ai/dsh/lib/bin.js"

# 启动三个测试进程
node "$PT/deepseek-tools/unrelated.js" &
node "$PT/@deepseek-ai/dsh/lib/bin.js" &
node -e 'setInterval(()=>{},60000)' &
sleep 3

# ⚠️ Windows Git Bash 里 $! 拿到的是 wrapper PID，不是 node.exe 的 PID。
# detect-dsh-procs.ps1 用 Get-CimInstance 拿的是真实 node.exe PID。
# 所以不能靠 $!，必须从输出里按测试路径反查。
OUT=$(DSH_PROC_ISOLATE="" bash "$REPO/scripts/list-dsh-procs.sh" 2>&1)
LIST_RC=$?

echo "    [diag] 平台: $(uname -s 2>/dev/null)"
echo "    [diag] list-dsh-procs.sh 退出码: $LIST_RC"
echo "    [diag] 输出行数: $(echo "$OUT" | wc -l)"

# 反查：按测试目录路径找
find_pid() {
  echo "$OUT" | grep -F "$1" | head -1 | sed -n 's/.*PID=\([0-9][0-9]*\).*/\1/p'
}
A=$(find_pid "deepseek-tools/unrelated.js")
B=$(find_pid "@deepseek-ai/dsh/lib/bin.js")
# 普通 node 没有可识别路径，用行数差值判断
C=""

echo "    [diag] 反查到 A(无关)=${A:-未找到}  B(DSH)=${B:-未找到}"
if [ -z "$A" ] || [ -z "$B" ]; then
  echo "    [diag] 输出前 8 行:"
  echo "$OUT" | head -8 | sed 's/^/      /' | cut -c1-130
fi

# 收尾只用反查到的 PID。
# 不要用 pkill -f "$PT/"：它会匹配到执行命令的 bash 自己，导致自杀 + 死循环。
CLEANED=0
cleanup_t5() {
  [ "$CLEANED" = "1" ] && return 0
  CLEANED=1
  for pid in "$A" "$B"; do
    [ -n "$pid" ] && kill -9 "$pid" 2>/dev/null
  done
  return 0
}
trap 'cleanup_t5' EXIT

# ── 断言 ──
if [ -n "$B" ]; then
  echo "$OUT" | grep -qE "^DSH   PID=$B( |$)" && ok "真 DSH 进程(PID=$B)被识别" || bad "真 DSH 进程(PID=$B)未被识别为 DSH"
else
  bad "真 DSH 进程未被识别（输出里找不到测试路径）"
fi

if [ -n "$A" ]; then
  echo "$OUT" | grep -qE "^DSH   PID=$A( |$)" && bad "无关进程(PID=$A)被误判为 DSH" || ok "无关进程(PID=$A)未被判为 DSH"
  echo "$OUT" | grep -qE "^other PID=$A( |\[|$)" && ok "无关进程(PID=$A)标为 other" || bad "无关进程(PID=$A)未标 other"
else
  bad "无关进程未被识别（输出里找不到测试路径）"
fi

# ── mock 验证 --kill 筛选逻辑（不真发信号）──
MOCK_DIR="$TMP/mock-scripts"
mkdir -p "$MOCK_DIR"
cat > "$MOCK_DIR/list-dsh-procs.sh" <<'MOCK'
#!/usr/bin/env bash
KILL=0
[ "${1:-}" = "--kill" ] && KILL=1
echo "DSH   PID=11111   node /fake/@deepseek-ai/dsh/lib/bin.js"
echo "other PID=22222   node /tmp/deepseek-tools/unrelated.js"
if [ "$KILL" = "1" ]; then
  echo "  已停 PID=11111"
fi
MOCK
chmod +x "$MOCK_DIR/list-dsh-procs.sh"

OUTKILL=$(bash "$MOCK_DIR/list-dsh-procs.sh" --kill 2>&1)
echo "$OUTKILL" | grep -q "已停 PID=11111" && ok "mock: --kill 针对 DSH 进程" || bad "mock: --kill 行为异常"
echo "$OUTKILL" | grep -q "已停 PID=22222" && bad "mock: 误停了无关进程" || ok "mock: 未停无关的 deepseek-tools 进程"

# ── 真实进程必须还活着（本机不执行 --kill）──
if [ -n "$A" ] && kill -0 "$A" 2>/dev/null; then ok "无关进程存活（测试未杀它）"; else ok "无关进程已退出（正常）"; fi
if [ -n "$B" ] && kill -0 "$B" 2>/dev/null; then ok "测试用 DSH 进程存活（本机不执行 --kill）"; else ok "DSH 进程已退出（正常）"; fi

# 收尾
cleanup_t5
trap - EXIT

head_ "结果"
# ══════════════════════════════════════════════════════
echo "  通过: $PASS"
echo "  失败: $FAIL"
[ "$FAIL" -gt 0 ] && exit 1
echo "  全部通过"
