#!/usr/bin/env bash
# dsh-purge 一键卸载（macOS / Linux，web profile）
# 用法： curl -fsSL https://raw.githubusercontent.com/evan545295555-hash/Evans-repo/main/uninstall.sh | bash
#
# 为什么需要它： dsh plugin --profile web remove dsh-purge 只是转发给 pnpm，
# 只删包和依赖，既不还原宿主补丁，也不清 profile 的 bundles / cordis.patch.yml
# 登记，残留会让宿主启动时挂载一个已不存在的 bundle。
set -euo pipefail

REPO_RAW="https://raw.githubusercontent.com/evan545295555-hash/Evans-repo/main"

say()  { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m✅\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m⚠️\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m❌\033[0m %s\n' "$*" >&2; exit 1; }

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

command -v node >/dev/null 2>&1 || die "没检测到 Node.js，无法执行卸载"

say "dsh-purge 卸载器（web profile）"
PROFILE_DIR="$(find_profile_dir)" || die "找不到 web profile 目录。请设置 DSH_HOME 后重试。"
ok "profile: $PROFILE_DIR"

# 1) 备份：只备份要动的两个文件，绝不删除原始配置
HOME_DIR="$(dirname "$(dirname "$PROFILE_DIR")")"
BACKUP_DIR="$HOME_DIR/backup-dsh-purge-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"
for f in package.json cordis.patch.yml; do
  if [ -f "$PROFILE_DIR/$f" ]; then cp -p "$PROFILE_DIR/$f" "$BACKUP_DIR/$f"; fi
done
ok "已备份到 $BACKUP_DIR"

# 2) 还原宿主补丁 + 清 package.json 登记（走插件自带的 uninstallPurge）
CLI="$PROFILE_DIR/node_modules/dsh-purge/bin/dsh-purge.js"
if [ -f "$CLI" ]; then
  say "还原补丁并移除 profile 登记"
  node "$CLI" --uninstall || die "补丁还原失败，未继续删除文件。备份在 $BACKUP_DIR"
  ok "补丁与 package.json 登记已处理"
else
  warn "没找到插件 CLI：$CLI，跳过补丁还原"
  warn "若之前点过 Apply，请先从界面 dsh-purge → Clean → Restore 还原宿主"
fi

# 3) 移除 npm 依赖（--uninstall 已清 package.json 时 pnpm 可能无操作，属正常）
say "移除插件包"
dsh plugin --profile web remove dsh-purge >/dev/null 2>&1 || warn "pnpm remove 未执行成功（包可能已被 --uninstall 清掉），继续做残留检查"

# 4) 精确清除 cordis.patch.yml 的 insert 块（只删逐行完全匹配的整块）
say "清除 profile 补丁登记"
TMPD="$(mktemp -d)"
trap 'rm -f "$TMPD/remove.mjs"; rmdir "$TMPD" 2>/dev/null || true' EXIT
curl -fsSL --max-time 30 "$REPO_RAW/scripts/remove-profile-insert.mjs" -o "$TMPD/remove.mjs" \
  || warn "清理脚本下载失败，跳过自动清理（下面会给出手动检查方式）"
if [ -f "$TMPD/remove.mjs" ]; then
  RESULT="$(node "$TMPD/remove.mjs" "$PROFILE_DIR" 2>/dev/null || true)"
  case "$RESULT" in
    *'"status":"removed"'*) ok "cordis.patch.yml 的 dsh-purge insert 已移除" ;;
    *'"status":"absent"'*|*'"status":"no-file"'*) ok "cordis.patch.yml 无需清理" ;;
    *'"status":"unrecognized"'*)
      warn "cordis.patch.yml 里有 dsh-purge 残留，但形态与安装器写入的不一致，未自动改动"
      warn "请手动检查（行号见上一条输出）；备份在 $BACKUP_DIR"
      ;;
    *) warn "清理结果无法解析：$RESULT" ;;
  esac
fi

# 5) 残留复检，不静默报成功
say "残留复检"
LEFT_PKG="$(node -e '
  const fs = require("node:fs");
  const p = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
  const b = (p.dsh && p.dsh.profile && p.dsh.profile.bundles) || [];
  const deps = p.dependencies || {};
  process.stdout.write(String(b.includes("dsh-purge") || Object.prototype.hasOwnProperty.call(deps, "dsh-purge") ? "1" : "0"));
' "$PROFILE_DIR/package.json" 2>/dev/null || printf '1')"
LEFT_YAML="0"
if [ -f "$PROFILE_DIR/cordis.patch.yml" ]; then
  if grep -qiE '^[[:space:]]*-?[[:space:]]*(id|name):[[:space:]]*dsh-purge' "$PROFILE_DIR/cordis.patch.yml"; then LEFT_YAML="1"; fi
fi
if [ "$LEFT_PKG" = "1" ] || [ "$LEFT_YAML" = "1" ]; then
  warn "仍检测到残留（package.json=$LEFT_PKG / cordis.patch.yml=$LEFT_YAML），本次不算干净卸载"
  warn "备份在 $BACKUP_DIR；请手动删除残留条目后重启 dsh web"
  exit 1
fi
ok "无残留"

echo
ok "卸载完成，重启 dsh web 生效"
echo "   备份： $BACKUP_DIR"
echo "   启动： dsh web"
