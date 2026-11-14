#!/usr/bin/env bash
# dsh-purge 1.1.71-rc2.1 一键安装（macOS / Linux）
# 用法（推荐，能发现下载失败）：
#   curl -fsSL -o /tmp/dsh-install.sh <raw 地址> && bash /tmp/dsh-install.sh
# 用法（旧写法，下载失败可能静默成功，不推荐）：
#   curl -fsSL <raw 地址> | bash
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
if [ "$NODE_MAJOR" -lt 20 ]; then
  die "Node 版本太低（$(node -v)）。宿主依赖要求 Node 20+。
    macOS: brew install node@22  或从 https://nodejs.org 装 LTS
    Linux: 用 nvm 或发行版的 nodejs 20+"
fi
ok "Node $(node -v)"

# ── 1.5) npm 策略（仅提示）─────────────────────────────────
# install-strategy=hoisted 只对本地项目生效，全局安装永远嵌套。
# 这里不再强制修改，避免让用户误以为改了就有用。
STRATEGY="$(npm config get install-strategy 2>/dev/null | tr -d '[:space:]' || true)"
if [ "$STRATEGY" = "hoisted" ]; then
  ok "npm 策略 hoisted"
else
  printf '\033[0;37m  提示: npm install-strategy=%s（对全局安装无影响，可忽略）\033[0m\n' "${STRATEGY:-未设置}"
fi

# ── 2) 宿主 ────────────────────────────────────────────────
need_host=1
INSTALLED="$(npm ls -g @deepseek-ai/dsh --depth=0 2>/dev/null | grep -oE '@deepseek-ai/dsh@[0-9][^ ]*' | head -1 | sed 's/.*@//' || true)"
if [ -n "$INSTALLED" ]; then
  # 实测 0.2.0-rc.2 与 0.2.1-rc.2 都能完整应用，任意 0.2.x 保留
  need_host=0
  ok "宿主 ${INSTALLED}（兼容）"
  case "$INSTALLED" in
    0.2.*) ;;
    *) warn "宿主是 ${INSTALLED}，本插件面向 0.2.x；如遇异常再升级" ;;
  esac
elif command -v dsh >/dev/null 2>&1; then
  cur="$(dsh --version 2>/dev/null | tr -d '[:space:]' || true)"
  if [ -n "$cur" ]; then
    need_host=0
    ok "宿主 $cur"
  fi
fi
if [ "$need_host" -eq 1 ]; then
  say "安装 DeepSeek Harness ${HOST_VERSION}（约 830 MB，耐心等）"
  npm i -g "@deepseek-ai/dsh@${HOST_VERSION}" || die "宿主安装失败"
  ok "宿主已安装"
fi

# ── 2.5) 布局检查（仅提示，不阻断）─────────────────────────
# npm 全局安装默认把依赖嵌套在 <pkg>/node_modules/ 下，这是设计行为；
# install-strategy=hoisted 只对本地项目生效，全局安装不遵守。
# 插件本身已兼容两种布局（hostCleanMarkersPresent 有四个候选路径），
# 所以这里只提示，不重装、不退出。
NPM_ROOT="$(npm root -g)"
FLAT_PATH="$NPM_ROOT/@deepseek-ai/dsh-system-prompt/lib/index.js"
NESTED_PATH="$NPM_ROOT/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-system-prompt/lib/index.js"
if [ -f "$FLAT_PATH" ]; then
  ok "布局：摊平（hoisted）"
elif [ -f "$NESTED_PATH" ]; then
  ok "布局：嵌套（npm 全局默认，插件已兼容）"
else
  warn "未找到 dsh-system-prompt，插件可能检测不到宿主"
  printf '\033[0;37m    摊平: %s\n    嵌套: %s\033[0m\n' "$FLAT_PATH" "$NESTED_PATH"
fi

# ── 2.6) 原生模块构建（自动，无需用户手动）──────────────────
# npm 11 默认拦截 install/postinstall 脚本，node-pty / koffi 等原生模块
# 不编译会导致 dsh web 启动失败：Cannot find module .../pty.node
HOST_VER_FOR_REBUILD="${INSTALLED:-$HOST_VERSION}"
native_ok() {
  # 原生模块文件名因平台而异：
  #   Linux / macOS : pty.node
  #   Windows       : conpty.node 和 conpty_console_list.node
  local dirs=(
    "$NPM_ROOT/@deepseek-ai/dsh/node_modules/node-pty"
    "$NPM_ROOT/@deepseek-ai/node-pty"
    "$NPM_ROOT/node-pty"
  )
  for d in "${dirs[@]}"; do
    # 老结构：build/Release/
    [ -f "$d/build/Release/pty.node" ] && return 0
    [ -f "$d/build/Release/conpty.node" ] && return 0
    # node-pty 1.2+：prebuilds/<platform>-<arch>/
    if [ -d "$d/prebuilds" ]; then
      for f in "$d"/prebuilds/*/pty.node "$d"/prebuilds/*/conpty.node; do
        [ -f "$f" ] && return 0
      done
    fi
  done
  return 1
}

if native_ok; then
  ok "原生模块已就绪"
else
  say "补跑原生模块构建（node-pty / koffi / protobufjs，约 30 秒）"
  npm i -g "@deepseek-ai/dsh@${HOST_VER_FOR_REBUILD}" \
    --allow-scripts=@deepseek-ai/dsh-subprocess-local,koffi,node-pty,@google/genai,protobufjs \
    >/dev/null 2>&1 || true
  if native_ok; then
    ok "原生模块已编译"
  else
    warn "node-pty 仍缺失，dsh web 可能起不来"
    printf '\033[0;37m    手动补跑:\n    npm i -g @deepseek-ai/dsh@%s --allow-scripts=@deepseek-ai/dsh-subprocess-local,koffi,node-pty,@google/genai,protobufjs\033[0m\n' "$HOST_VER_FOR_REBUILD"
  fi
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

# ── 4.5) 确保 base 与 web-app 一定在 bundles 里 ────────────
# 只补「bundles 为空」是不够的：用户装过别的插件、或手改过配置后，
# bundles 可能有值但缺 base/web-app，宿主就等不到 agentPresets 服务
# （表现为 preset-declare.json 的 phase=waiting-registry）。
BUNDLE_FIX="$(node -e "
const fs=require('fs');
const p=JSON.parse(fs.readFileSync('package.json','utf8'));
p.dsh=p.dsh||{}; p.dsh.profile=p.dsh.profile||{};
let b=Array.isArray(p.dsh.profile.bundles)?p.dsh.profile.bundles.slice():[];
let changed=false;
for (const need of ['@deepseek-ai/dsh-base','@deepseek-ai/dsh-web-app']) {
  if (!b.includes(need)) { b.unshift(need); changed=true; }
}
if (changed) {
  p.dsh.profile.bundles=b;
  fs.writeFileSync('package.json', JSON.stringify(p,null,2)+'\n');
  console.log('fixed');
}
" 2>/dev/null || echo "")"
if [ "$BUNDLE_FIX" = "fixed" ]; then
  ok "已补齐缺失的 base / web-app"
else
  ok "bundles 已含 base / web-app"
fi

# ── 5) 下载插件包 ──────────────────────────────────────────
TMP="${TMPDIR:-/tmp}/dsh-purge-${PLUGIN_VERSION}.tgz"
say "下载插件 ${PLUGIN_VERSION}"
curl -fsSL --retry 3 --retry-delay 3 -o "$TMP" "$PKG" || die "下载失败"
ok "已下载 $(du -h "$TMP" | cut -f1)"

# ── 6) npm 直装（绕开 dsh plugin，与 Windows 版同一套逻辑）──
say "安装插件到 profile"

# 升级旧版必须先删包：package-lock.json 里已有 dsh-purge 记录时，
# npm 会认为 "already satisfied" 而跳过重装（--force 也无效，实测仍是旧版）。
PLUGIN_INSTALLED_VER="$(node -p "try{require('$PROFILE_DIR/node_modules/dsh-purge/package.json').version}catch(e){''}" 2>/dev/null || echo "")"
if [ -n "$PLUGIN_INSTALLED_VER" ] && [ "$PLUGIN_INSTALLED_VER" != "$PLUGIN_VERSION" ]; then
  say "检测到已装 ${PLUGIN_INSTALLED_VER}，先移除再装 ${PLUGIN_VERSION}"
  rm -rf "$PROFILE_DIR/node_modules/dsh-purge"
fi

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

  ────────────────────────────────
   你给巴里啊啊点赞了吗？
  ────────────────────────────────
EOT
