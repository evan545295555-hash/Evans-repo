#!/usr/bin/env bash
# dsh-purge 1.1.71-rc2.1 一键安装（macOS / Linux，仅 web profile）
# 用法： curl -fsSL https://raw.githubusercontent.com/evan545295555-hash/Evans-repo/main/install.sh | bash
set -euo pipefail

PLUGIN_VERSION="1.1.71-rc2.1"
HOST_VERSION="0.2.1-rc.2"
REPO_RAW="https://raw.githubusercontent.com/evan545295555-hash/Evans-repo/main"
PKG="https://github.com/evan545295555-hash/Evans-repo/releases/download/v${PLUGIN_VERSION}/dsh-purge-${PLUGIN_VERSION}.tgz"

say() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
ok()  { printf '\033[1;32m✅\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m❌\033[0m %s\n' "$*" >&2; exit 1; }

# 找真正在用的 web profile，不再硬编码 ~/.dsh：
# DSH_HOME → dsh 启动器旁边 → npm 全局根旁边 → 常见 home 目录
find_profile_dir() {
  local bin real base npmroot c d
  local cands=()
  if [ -n "${DSH_HOME:-}" ]; then cands+=("$DSH_HOME"); fi
  bin="$(command -v dsh 2>/dev/null || true)"
  if [ -n "$bin" ]; then
    real="$(node -e 'process.stdout.write(require("node:fs").realpathSync(process.argv[1]))' "$bin" 2>/dev/null || printf '%s' "$bin")"
    base="$(dirname "$real")"
    cands+=("$base/.dsh" "$(dirname "$base")/.dsh" "$(dirname "$(dirname "$base")")/.dsh")
  fi
  npmroot="$(npm root -g 2>/dev/null || true)"
  if [ -n "$npmroot" ]; then cands+=("$npmroot/.dsh" "$(dirname "$npmroot")/.dsh"); fi
  cands+=("$HOME/.dsh")
  cands+=("$HOME/Library/Application Support/DeepSeek Harness/dsh-home")
  cands+=("${XDG_DATA_HOME:-$HOME/.local/share}/DeepSeek Harness/dsh-home")
  for c in "${cands[@]}"; do
    d="$c/profiles/web"
    if [ -f "$d/package.json" ]; then printf '%s\n' "$d"; return 0; fi
  done
  return 1
}

say "dsh-purge ${PLUGIN_VERSION} 安装器（仅 web profile / dsh web）"
say "注意：本脚本会把宿主版本对齐到 ${HOST_VERSION}，其他版本会被覆盖重装"

# 1) Node + npm
command -v node >/dev/null 2>&1 || die "没检测到 Node.js。先装它：https://nodejs.org （选 LTS）"
command -v npm  >/dev/null 2>&1 || die "没检测到 npm。它随 Node.js 一起安装：https://nodejs.org"
NODE_MAJOR="$(node -p 'process.versions.node.split(".")[0]')"
[ "$NODE_MAJOR" -ge 18 ] || die "Node 版本太低（$(node -v)），需要 18 以上"
ok "Node $(node -v)"

# 2) 宿主（版本不符会覆盖重装，已在开头披露）
if ! command -v dsh >/dev/null 2>&1; then
  say "没装 DeepSeek Harness，正在安装 ${HOST_VERSION}（约 830 MB，耐心等）"
  npm i -g "@deepseek-ai/dsh@${HOST_VERSION}"
elif [ "$(dsh --version 2>/dev/null | tr -d '[:space:]')" != "$HOST_VERSION" ]; then
  say "宿主当前是 $(dsh --version 2>/dev/null)，将覆盖切换到 ${HOST_VERSION}（约 830 MB）"
  npm i -g "@deepseek-ai/dsh@${HOST_VERSION}"
fi
ok "宿主 $(dsh --version)"

# 3) 初始化并定位 web profile
dsh --profile web --dump-config >/dev/null 2>&1 || true
PROFILE_DIR="$(find_profile_dir)" || die "找不到 web profile 目录（已找 DSH_HOME / dsh 启动器旁边 / ~/.dsh）。请设置 DSH_HOME 后重试。"
ok "profile: $PROFILE_DIR"

# 4) 插件
say "下载并安装插件"
dsh plugin --profile web add --ignore-scripts "$PKG"

# 5) 登记
say "登记到 profile"
( cd "$PROFILE_DIR" && node node_modules/dsh-purge/scripts/ensure-profile-bundle.mjs ) || die "profile 登记脚本执行失败"

# 6) 验收：三层断言，不再依赖 dump-config 输出行首无缩进
[ -f "$PROFILE_DIR/node_modules/dsh-purge/package.json" ] || die "插件包未落地：$PROFILE_DIR/node_modules/dsh-purge"
node -e '
  const fs = require("node:fs");
  const p = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
  const b = p && p.dsh && p.dsh.profile && p.dsh.profile.bundles;
  if (!Array.isArray(b) || !b.includes("dsh-purge")) {
    console.error("profile 的 dsh.profile.bundles 里没有 dsh-purge");
    process.exit(1);
  }
' "$PROFILE_DIR/package.json" || die "profile 登记失败（bundles 未写入）"
DUMP="$(cd "$PROFILE_DIR" && dsh --profile web --dump-config 2>/dev/null || true)"
[ -n "$DUMP" ] || die "dsh --profile web --dump-config 无输出，无法确认挂载"
MOUNT_COUNT="$(printf '%s\n' "$DUMP" | grep -ciE '(^|[[:space:]])(id|name):[[:space:]]*dsh-purge([[:space:]]|$)' || true)"
[ "${MOUNT_COUNT:-0}" -ge 1 ] || die "配置里找不到 dsh-purge 挂载。诊断：cd '$PROFILE_DIR' && dsh --profile web --dump-config | head -40"
ok "挂载校验通过（匹配 ${MOUNT_COUNT} 处）"

echo
ok "安装完成，重启 DeepSeek Harness 生效"
echo "   启动： dsh web"
echo "   然后： 点标题旁 dsh-purge → Clean → Apply → 新开一个对话"
echo "   卸载： curl -fsSL ${REPO_RAW}/uninstall.sh | bash"
echo "          只跑 dsh plugin --profile web remove dsh-purge 会残留配置，别只跑那条"
