#!/usr/bin/env bash
# 失败场景修复验证（本地，隔离 DSH_HOME）
# 目的：确认 install.sh 在「已装但坏了」的各种状态下能自愈
# 用法：bash scripts/test-recovery.sh

set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
BASE=/tmp/recovery-test
PASS=0
FAIL=0

ok()   { printf "  \033[1;32m✓\033[0m %s\n" "$*"; PASS=$((PASS+1)); }
bad()  { printf "  \033[1;31m✗\033[0m %s\n" "$*"; FAIL=$((FAIL+1)); }
info() { printf "    %s\n" "$*"; }
head_(){ printf "\n\033[1;36m%s\033[0m\n" "$*"; }

# 每个场景一个独立的 DSH_HOME
new_home() {
  local name="$1"
  local h="$BASE/$name"
  rm -rf "$h"; mkdir -p "$h"
  echo "$h"
}

run_install() {
  local h="$1"
  DSH_HOME="$h" bash "$REPO/install.sh" > "$h/install.log" 2>&1
  echo $?
}

verify_plugin() {
  local h="$1" expect_ver="$2" label="$3"
  local pkg="$h/profiles/web/node_modules/dsh-purge/package.json"
  if [ ! -f "$pkg" ]; then bad "$label: 插件不存在"; return; fi
  local v; v="$(node -p "require('$pkg').version" 2>/dev/null || echo "")"
  [ "$v" = "$expect_ver" ] && ok "$label: 版本 $v" || bad "$label: 版本 ${v}（期望 ${expect_ver}）"

  local dep; dep="$(node -p "try{require('$h/profiles/web/package.json').dependencies['dsh-purge']||''}catch(e){''}" 2>/dev/null || echo "")"
  [ -n "$dep" ] && ok "$label: 依赖已声明" || bad "$label: 依赖未声明"

  local bundles; bundles="$(node -p "try{require('$h/profiles/web/package.json').dsh.profile.bundles.join(',')}catch(e){''}" 2>/dev/null || echo "")"
  case ",$bundles," in
    *,dsh-purge,*) ok "$label: bundles 含 dsh-purge" ;;
    *)             bad "$label: bundles 缺 dsh-purge（${bundles}）" ;;
  esac
  case ",$bundles," in
    *,"@deepseek-ai/dsh-base",*)    ok "$label: bundles 含 base" ;;
    *)                              bad "$label: bundles 缺 base" ;;
  esac
  case ",$bundles," in
    *,"@deepseek-ai/dsh-web-app",*) ok "$label: bundles 含 web-app" ;;
    *)                              bad "$label: bundles 缺 web-app" ;;
  esac

  local hit; hit="$(grep -c 'dsh-purge' "$h/profiles/web/cordis.patch.yml" 2>/dev/null || echo 0)"
  [ "$hit" -ge 1 ] && ok "$label: patch 已登记（$hit 处）" || bad "$label: patch 未登记"
}

mkdir -p "$BASE"

# ══════════════════════════════════════════════════════════════
head_ "场景 A：全新环境（什么都没装）"
# ══════════════════════════════════════════════════════════════
H="$(new_home fresh)"
info "DSH_HOME=$H"
RC="$(run_install "$H")"
[ "$RC" = "0" ] && ok "install.sh 退出码 0" || { bad "install.sh 退出码 $RC"; tail -5 "$H/install.log" | info; }
verify_plugin "$H" "1.1.71-rc2.1" "A"

# ══════════════════════════════════════════════════════════════
head_ "场景 B：已装旧版插件（1.1.71，缺修复）"
# ══════════════════════════════════════════════════════════════
H="$(new_home oldver)"
run_install "$H" >/dev/null
# 伪装成旧版
node -e "
const fs=require('fs'),p='$H/profiles/web/node_modules/dsh-purge/package.json';
const d=JSON.parse(fs.readFileSync(p,'utf8')); d.version='1.1.71';
fs.writeFileSync(p, JSON.stringify(d,null,2));
" 2>/dev/null
OLD="$(node -p "require('$H/profiles/web/node_modules/dsh-purge/package.json').version" 2>/dev/null)"
info "伪造后版本: $OLD"
RC="$(run_install "$H")"
[ "$RC" = "0" ] && ok "重跑 install.sh 退出码 0" || bad "退出码 $RC"
verify_plugin "$H" "1.1.71-rc2.1" "B"

# ══════════════════════════════════════════════════════════════
head_ "场景 C：bundles 里有死引用 + 缺 base"
# ══════════════════════════════════════════════════════════════
H="$(new_home brokenbundle)"
run_install "$H" >/dev/null
# 破坏 bundles
node -e "
const fs=require('fs'),p='$H/profiles/web/package.json';
const d=JSON.parse(fs.readFileSync(p,'utf8'));
d.dsh.profile.bundles=['dsh-purge-community','nonexistent-pkg','dsh-purge'];
fs.writeFileSync(p, JSON.stringify(d,null,2));
" 2>/dev/null
info "破坏后 bundles: $(node -p "require('$H/profiles/web/package.json').dsh.profile.bundles.join(',')")"
RC="$(run_install "$H")"
[ "$RC" = "0" ] && ok "重跑 install.sh 退出码 0" || bad "退出码 $RC"
verify_plugin "$H" "1.1.71-rc2.1" "C"

# ══════════════════════════════════════════════════════════════
head_ "场景 D：cordis.patch.yml 里 dsh-purge 条目被删光"
# ══════════════════════════════════════════════════════════════
H="$(new_home nopatch)"
run_install "$H" >/dev/null
# 清空 patch 里的 dsh-purge
node -e "
const fs=require('fs'),p='$H/profiles/web/cordis.patch.yml';
let t=fs.readFileSync(p,'utf8');
t=t.split('\n').filter(l=>!l.includes('dsh-purge')).join('\n');
fs.writeFileSync(p,t);
" 2>/dev/null
info "清空后 patch 提及: $(grep -c 'dsh-purge' "$H/profiles/web/cordis.patch.yml" 2>/dev/null || echo 0)"
RC="$(run_install "$H")"
[ "$RC" = "0" ] && ok "重跑 install.sh 退出码 0" || bad "退出码 $RC"
verify_plugin "$H" "1.1.71-rc2.1" "D"

# ══════════════════════════════════════════════════════════════
head_ "场景 E：node_modules 里的包被删（目录残留）"
# ══════════════════════════════════════════════════════════════
H="$(new_home nopkg)"
run_install "$H" >/dev/null
rm -rf "$H/profiles/web/node_modules/dsh-purge"
info "已删除 node_modules/dsh-purge"
RC="$(run_install "$H")"
[ "$RC" = "0" ] && ok "重跑 install.sh 退出码 0" || bad "退出码 $RC"
verify_plugin "$H" "1.1.71-rc2.1" "E"

# ══════════════════════════════════════════════════════════════
head_ "场景 F：preset-declare.json 状态是 registered-broken"
# ══════════════════════════════════════════════════════════════
H="$(new_home brokenpreset)"
run_install "$H" >/dev/null
mkdir -p "$H/redteam"
cat > "$H/redteam/preset-declare.json" <<'JSON'
{"ok":false,"phase":"registered-broken","broken":"persona: never started","plugins":18}
JSON
info "已伪造 broken 状态"
RC="$(run_install "$H")"
[ "$RC" = "0" ] && ok "重跑 install.sh 退出码 0" || bad "退出码 $RC"
verify_plugin "$H" "1.1.71-rc2.1" "F"
info "（preset 是否修好需真人点「应用」，此处只验安装层面）"

# ══════════════════════════════════════════════════════════════
head_ "场景 G：重复安装三次（幂等性）"
# ══════════════════════════════════════════════════════════════
H="$(new_home idempotent)"
for i in 1 2 3; do
  RC="$(run_install "$H")"
  [ "$RC" = "0" ] && ok "第 $i 次安装退出码 0" || bad "第 $i 次退出码 $RC"
done
verify_plugin "$H" "1.1.71-rc2.1" "G"
BUNDLE_COUNT="$(node -p "require('$H/profiles/web/package.json').dsh.profile.bundles.filter(x=>x==='dsh-purge').length" 2>/dev/null || echo 0)"
[ "$BUNDLE_COUNT" = "1" ] && ok "G: dsh-purge 在 bundles 里只出现 1 次（无重复）" || bad "G: dsh-purge 出现 $BUNDLE_COUNT 次"
PATCH_COUNT="$(grep -c 'id: dsh-purge' "$H/profiles/web/cordis.patch.yml" 2>/dev/null || echo 0)"
[ "$PATCH_COUNT" -le 1 ] && ok "G: patch 里 id: dsh-purge 出现 $PATCH_COUNT 次" || bad "G: patch 重复 $PATCH_COUNT 次"

# ══════════════════════════════════════════════════════════════
head_ "结果"
# ══════════════════════════════════════════════════════════════
echo "  通过: $PASS"
echo "  失败: $FAIL"
echo
if [ "$FAIL" -gt 0 ]; then
  echo "  有失败，install.sh 需要修"
  exit 1
fi
echo "  全部通过"
