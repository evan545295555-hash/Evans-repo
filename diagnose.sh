#!/usr/bin/env bash
# dsh-purge 环境诊断（只读，不改任何东西）
# 用法：curl -fsSL <raw 地址> | bash

set -u

C_RESET='\033[0m'
C_CYAN='\033[1;36m'
C_GREEN='\033[1;32m'
C_RED='\033[1;31m'
C_YELLOW='\033[1;33m'
C_GRAY='\033[0;37m'

line()  { printf "${C_GRAY}%s${C_RESET}\n" "$(printf '%.0s=' {1..60})"; }
head_() { printf "\n${C_CYAN}%s${C_RESET}\n" "$1"; }
ok()    { printf "  ${C_GREEN}[OK]${C_RESET}   %s\n" "$1"; }
bad()   { printf "  ${C_RED}[FAIL]${C_RESET} %s\n" "$1"; }
warn()  { printf "  ${C_YELLOW}[WARN]${C_RESET} %s\n" "$1"; }
info()  { printf "  %s\n" "$1"; }

line
printf " dsh-purge 环境诊断（只读）\n"
printf "${C_GRAY} 本脚本不会修改任何文件${C_RESET}\n"
line

# ── 1. Node ─────────────────────────────────────────────
head_ "1. Node.js"
if command -v node >/dev/null 2>&1; then
  NV="$(node -v 2>&1)"
  info "版本: $NV"
  MAJOR="$(printf '%s' "$NV" | sed 's/^v//' | cut -d. -f1)"
  if [ "${MAJOR:-0}" -ge 20 ] 2>/dev/null; then
    ok "符合要求（需要 20+）"
  else
    bad "版本太低，需要 20+"
    info "升级: brew install node@22  或 https://nodejs.org"
  fi
  info "npm: $(npm -v 2>&1)"
else
  bad "未安装 Node.js"
  info "安装: brew install node  或 https://nodejs.org"
fi

# ── 2. 宿主 ─────────────────────────────────────────────
head_ "2. 宿主 (DeepSeek Harness)"
NPM_ROOT="$(npm root -g 2>/dev/null || true)"
info "npm 全局根: $NPM_ROOT"

HOST_VER=""
LS_OUT="$(npm ls -g @deepseek-ai/dsh --depth=0 2>&1 || true)"
HOST_VER="$(printf '%s' "$LS_OUT" | grep -oE '@deepseek-ai/dsh@[0-9][^ ]*' | head -1 | sed 's/.*@//')"

if [ -n "$HOST_VER" ]; then
  ok "已装: @deepseek-ai/dsh@$HOST_VER"
  case "$HOST_VER" in
    0.2.*) ok "版本兼容（0.2.x）" ;;
    *)     warn "非 0.2.x，插件可能不兼容" ;;
  esac
else
  bad "未安装宿主"
  info "安装: npm i -g @deepseek-ai/dsh@0.2.1-rc.2"
fi

# ── 3. 布局 ─────────────────────────────────────────────
head_ "3. 宿主依赖布局"
FLAT="$NPM_ROOT/@deepseek-ai/dsh-system-prompt/lib/index.js"
NESTED="$NPM_ROOT/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-system-prompt/lib/index.js"

if [ -f "$FLAT" ]; then
  ok "摊平布局（hoisted）"
elif [ -f "$NESTED" ]; then
  ok "嵌套布局（npm 全局默认，插件已兼容）"
else
  bad "两种布局都找不到 dsh-system-prompt"
  info "摊平: $FLAT"
  info "嵌套: $NESTED"
fi

# ── 4. dsh 命令 ─────────────────────────────────────────
head_ "4. dsh 命令"
DSH_PATH="$(command -v dsh 2>/dev/null || true)"
if [ -n "$DSH_PATH" ]; then
  info "路径: $DSH_PATH"
  case "$DSH_PATH" in
    "$NPM_ROOT"*) ok "来自 npm 全局（正确）" ;;
    *)            warn "不在 npm 全局目录，可能是别的安装" ;;
  esac
else
  bad "dsh 命令不存在"
fi

# ── 5. 插件 ─────────────────────────────────────────────
head_ "5. 插件 (dsh-purge)"
WEB="$HOME/.dsh/profiles/web"
PKG="$WEB/node_modules/dsh-purge"
if [ -d "$PKG" ]; then
  PV="$(node -p "require('$PKG/package.json').version" 2>/dev/null || echo '')"
  ok "已装: $PV"
  if [ "$PV" = "1.1.71-rc2.1" ]; then
    ok "版本正确"
  else
    warn "版本不是 1.1.71-rc2.1，可能缺修复"
  fi
else
  info "未安装"
fi

# ── 6. profile 配置 ─────────────────────────────────────
head_ "6. profile 配置"
PROF_PKG="$WEB/package.json"
if [ -f "$PROF_PKG" ]; then
  BUNDLES="$(node -p "try{require('$PROF_PKG').dsh.profile.bundles.join(',')}catch(e){''}" 2>/dev/null || true)"
  info "bundles: ${BUNDLES:-（空）}"
  case ",$BUNDLES," in
    *,dsh-purge,*)                    ok "dsh-purge 已登记" ;;
    *)                                info "dsh-purge 未登记（没装或已清）" ;;
  esac
  case ",$BUNDLES," in
    *,"@deepseek-ai/dsh-base",*)      ok "base 存在" ;;
    *)                                bad "缺 base" ;;
  esac
  case ",$BUNDLES," in
    *,"@deepseek-ai/dsh-web-app",*)   ok "web-app 存在" ;;
    *)                                bad "缺 web-app" ;;
  esac
else
  info "profile package.json 不存在（还没初始化）"
fi

PATCH="$WEB/cordis.patch.yml"
if [ -f "$PATCH" ]; then
  N="$(grep -c 'dsh-purge' "$PATCH" 2>/dev/null || echo 0)"
  info "patch.yml 里 dsh-purge 提及: $N"
else
  info "cordis.patch.yml 不存在"
fi

# ── 7. 红队模式 ─────────────────────────────────────────
head_ "7. 红队模式"
ST="$HOME/.dsh/redteam/preset-declare.json"
if [ -f "$ST" ]; then
  node -e "
const d=require('$ST');
console.log('  phase  :', d.phase);
console.log('  plugins:', d.plugins);
console.log('  broken :', String(d.broken).slice(0,120));
" 2>/dev/null || bad "解析失败"
  PHASE="$(node -p "try{require('$ST').phase}catch(e){''}" 2>/dev/null || true)"
  BROKEN="$(node -p "try{require('$ST').broken||''}catch(e){''}" 2>/dev/null || true)"
  case "$PHASE" in
    registered)        [ -z "$BROKEN" ] && ok "注册成功" || warn "有组件未启动，见 broken" ;;
    registered-broken) warn "有组件未启动，见 broken" ;;
    waiting-registry)  warn "等 registry，可能 bundles 缺项" ;;
    *)                 warn "未知状态: $PHASE" ;;
  esac
else
  info "未生成（插件还没加载过）"
fi

# ── 8. 残留检查 ─────────────────────────────────────────
head_ "8. 残留检查"
for p in \
  "$WEB/node_modules/dsh-purge-community" \
  "$WEB/node_modules/dsh-purge-panel" \
  "$HOME/.dsh/.agent-presets/redteam" \
  "$HOME/.dsh/dsh-purge-community" \
  "$HOME/.dsh/dsh-purge"; do
  [ -e "$p" ] && info "$p : 存在"
done

# ── 9. 总结 ─────────────────────────────────────────────
line
printf " 诊断完成，未修改任何文件\n"
printf "${C_YELLOW} 请把以上完整输出截图发出来${C_RESET}\n"
line
