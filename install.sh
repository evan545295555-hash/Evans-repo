#!/usr/bin/env bash
# dsh-purge 1.1.71-rc2.1 一键安装（macOS / Linux）
# 用法： curl -fsSL <raw 地址> | bash
set -euo pipefail

PLUGIN_VERSION="1.1.71-rc2.1"
HOST_VERSION="0.2.0-rc.2"
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
if [ "$NODE_MAJOR" -lt 20 ]; then
  die "Node 版本太低（$(node -v)）。宿主依赖要求 Node 20+。
    macOS: brew install node@22  或从 https://nodejs.org 装 LTS
    Linux: 用 nvm 或发行版的 nodejs 20+"
fi
ok "Node $(node -v)"

# ── 2) 宿主 ────────────────────────────────────────────────
need_host=1
if command -v dsh >/dev/null 2>&1; then
  cur="$(dsh --version 2>/dev/null | tr -d '[:space:]' || true)"
  if [ "$cur" = "$HOST_VERSION" ]; then
    need_host=0
    ok "宿主 $cur"
  elif [ -n "$cur" ]; then
    warn "宿主版本 $cur，对齐到 $HOST_VERSION（补丁只支持到 0.2.0）"
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

# ── 4.5) 确保 profile 有默认 bundles ──────────────────────
# 手动创建的 package.json 不带 bundles，宿主会缺少 base/web-app，
# 导致插件等不到 agentPresets 服务（phase=waiting-registry）。
if ! node -e "
  const p=require('./package.json');
  const b=p.dsh && p.dsh.profile && p.dsh.profile.bundles;
  process.exit(Array.isArray(b) && b.length ? 0 : 1);
" 2>/dev/null; then
  node -e "
    const fs=require('fs');
    const p=JSON.parse(fs.readFileSync('package.json','utf8'));
    p.dsh = p.dsh || {};
    p.dsh.profile = p.dsh.profile || {};
    p.dsh.profile.bundles = ['@deepseek-ai/dsh-base','@deepseek-ai/dsh-web-app'];
    fs.writeFileSync('package.json', JSON.stringify(p,null,2)+'\n');
  "
  ok "已补默认 bundles"
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

# ── 10) 红队模式注册状态 ──────────────────────────────────
STATUS="$DSH_HOME_DIR/redteam/preset-declare.json"
if [ -f "$STATUS" ]; then
  PHASE="$(node -p "try{require('$STATUS').phase}catch(e){''}" 2>/dev/null || echo '')"
  if [ "$PHASE" = "registered" ]; then
    ok "红队模式已注册"
  else
    warn "红队模式状态：${PHASE:-未知}，需按下面步骤操作"
  fi
else
  warn "红队模式：尚未注册"
fi

cat <<'EOT'

════ 下一步（必须做，否则看不到插件）════
  0. 首次启动前先设（只在当前 shell 有效）：
       export REDTEAM_PRESET_REFRESH=1
  1. 完全退出 DeepSeek Harness（不是关窗口）
  2. 重新打开宿主
  3. 点会话标题旁的 dsh-purge → 清洗 → 应用
  4. 它会自动重启一次
  5. 再开，模式下拉里就有「红队模式」

  检查注册状态：
    cat ~/.dsh/redteam/preset-declare.json
EOT
