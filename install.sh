#!/usr/bin/env bash
# dsh-purge 1.1.71-rc2.1 一键安装（macOS / Linux）
# 用法： curl -fsSL <raw 地址> | bash
set -euo pipefail

PLUGIN_VERSION="1.1.71-rc2.1"
HOST_VERSION="0.2.1-rc.2"
PKG="https://github.com/evan545295555-hash/Evans-repo/releases/download/v${PLUGIN_VERSION}/dsh-purge-${PLUGIN_VERSION}.tgz"
DSH_HOME_DIR="${DSH_HOME:-$HOME/.dsh}"

say() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
ok()  { printf '\033[1;32mOK  \033[0m %s\n' "$*"; }
warn(){ printf '\033[1;33m!!  \033[0m %s\n' "$*"; }
die() { printf '\033[1;31mERR \033[0m %s\n' "$*" >&2; exit 1; }

say "dsh-purge ${PLUGIN_VERSION} 安装器（macOS / Linux）"

# ── 1) Node ────────────────────────────────────────────────
command -v node >/dev/null 2>&1 || die "没检测到 Node.js。先装它：https://nodejs.org"
NODE_MAJOR="$(node -p 'process.versions.node.split(".")[0]')"
[ "$NODE_MAJOR" -ge 18 ] || die "Node 版本太低（$(node -v)），需要 18 以上"
ok "Node $(node -v)"

# ── 2) 宿主 ────────────────────────────────────────────────
need_host=1
if command -v dsh >/dev/null 2>&1; then
  cur="$(dsh --version 2>/dev/null | tr -d '[:space:]' || true)"
  if [ "$cur" = "$HOST_VERSION" ]; then
    need_host=0
    ok "宿主 $cur"
  elif [ -n "$cur" ]; then
    warn "宿主版本 $cur，切换到 $HOST_VERSION"
  fi
fi
if [ "$need_host" -eq 1 ]; then
  say "安装 DeepSeek Harness ${HOST_VERSION}（约 830 MB，耐心等）"
  npm i -g "@deepseek-ai/dsh@${HOST_VERSION}" || die "宿主安装失败"
  ok "宿主已安装"
fi

# ── 3) profile 目录 ────────────────────────────────────────
PROFILE_DIR="$DSH_HOME_DIR/profiles/web"
mkdir -p "$PROFILE_DIR"
cd "$PROFILE_DIR"
say "profile: $PROFILE_DIR"

# ── 4) 最小 package.json ───────────────────────────────────
if [ ! -f package.json ]; then
  printf '{"name":"dsh-profile-web","private":true,"version":"0.0.0","dependencies":{}}\n' > package.json
  ok "已创建最小 package.json"
fi

# ── 5) 下载插件包 ──────────────────────────────────────────
TMP="${TMPDIR:-/tmp}/dsh-purge-${PLUGIN_VERSION}.tgz"
say "下载插件 ${PLUGIN_VERSION}"
curl -fsSL --retry 3 --retry-delay 3 -o "$TMP" "$PKG" || die "下载失败"
ok "已下载 $(du -h "$TMP" | cut -f1)"

# ── 6) npm 直装（绕开 dsh plugin，与 Windows 版同一套逻辑）──
say "安装插件到 profile"
npm install --save --ignore-scripts "$TMP" >/dev/null 2>&1 || die "npm install 失败"
[ -f node_modules/dsh-purge/package.json ] || die "包未就位：node_modules/dsh-purge 不存在"

# npm 会把临时文件路径写进 dependencies，临时文件清理后即失效。
# 换成稳定的 release URL。
npm pkg set "dependencies.dsh-purge=$PKG" >/dev/null 2>&1 || \
  warn "无法重写 dependencies，保留原值"
ok "插件已写入 node_modules"

# ── 7) 登记到 bundles ─────────────────────────────────────
say "登记到 profile bundles"
node node_modules/dsh-purge/scripts/ensure-profile-bundle.mjs || die "登记失败"

# ── 8) 文件级验证 ─────────────────────────────────────────
V="$(node -p "require('./node_modules/dsh-purge/package.json').version")"
[ "$V" = "$PLUGIN_VERSION" ] || die "版本不符：$V"

DEP="$(node -p "require('./package.json').dependencies['dsh-purge'] || ''")"
[ -n "$DEP" ] || die "profile package.json 未声明 dsh-purge 依赖"

grep -q "dsh-purge" cordis.patch.yml 2>/dev/null || die "cordis.patch.yml 未登记 dsh-purge"

for f in lib/identity.js lib/core.js client.js bin/dsh-purge.js; do
  [ -f "node_modules/dsh-purge/$f" ] || die "缺少文件：$f"
done

# ── 9) 更新地址校验 ───────────────────────────────────────
if [ -f node_modules/dsh-purge/lib/update.js ]; then
  REPO="$(grep -m1 '^const REPO = ' node_modules/dsh-purge/lib/update.js | sed 's/.*"\(.*\)".*/\1/')"
  case "$REPO" in
    *YuJunZhiXue*|*HunYiSage*) warn "update.js 仍指向第三方仓库：$REPO" ;;
    *) ok "更新源：$REPO" ;;
  esac
fi

echo
ok "安装完成：dsh-purge $V"
echo "   重启 DeepSeek Harness 生效"
echo "   启动： dsh web"
