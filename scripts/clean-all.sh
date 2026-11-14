#!/usr/bin/env bash
# dsh-purge 完整清理（备份 → 停进程 → 清配置），一步不能跳
#
# 用法:
#   bash clean-all.sh            # 交互式，每步确认
#   bash clean-all.sh --dry-run  # 只显示会做什么
#   bash clean-all.sh --yes      # 非交互（CI 用）
#
# 设计要点：
#   - 备份失败立即退出，不会进入清理阶段
#   - 清理入口检查备份标记，备份不存在直接拒绝
#   - 只停 DSH 进程，不碰其他 node
#   - 只删明确列出的插件条目，不按名称模糊匹配

set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
DSH="${DSH_HOME:-$HOME/.dsh}"
DRY=0
YES=0
for a in "$@"; do
  case "$a" in
    --dry-run) DRY=1 ;;
    --yes)     YES=1 ;;
  esac
done

say()  { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32mOK  \033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!  \033[0m %s\n' "$*"; }
die()  { printf '\033[1;31mERR \033[0m %s\n' "$*" >&2; exit 1; }
gray() { printf '\033[0;37m     %s\033[0m\n' "$*"; }

confirm() {
  [ "$YES" = "1" ] && return 0
  [ "$DRY" = "1" ] && return 0
  printf '    继续？[y/N] '
  read -r ans
  [ "$ans" = "y" ] || [ "$ans" = "Y" ]
}

# ══════════════════════════════════════════════════════════
say "dsh-purge 完整清理"
gray "数据目录: $DSH"
[ "$DRY" = "1" ] && gray "模式: 预演（不会真的改任何东西）"
echo ""

[ -d "$DSH" ] || die "找不到数据目录: $DSH"

# ── 0. 列出 DSH 进程 ──────────────────────────────────────
say "0) 当前 DSH 进程"
if [ -x "$REPO/scripts/list-dsh-procs.sh" ]; then
  bash "$REPO/scripts/list-dsh-procs.sh" 2>/dev/null | sed 's/^/     /'
else
  warm_msg="找不到 list-dsh-procs.sh"
  gray "$warm_msg"
fi

# ── 1. 备份（失败即整个脚本退出）──────────────────────────
say "1) 备份数据"

BK="$HOME/dsh-backup-$(date +%Y%m%d-%H%M%S)"
REQUIRED="sessions skills redteam prompt-inject.md profiles/web/package.json profiles/web/cordis.patch.yml"

if [ "$DRY" = "1" ]; then
  gray "会备份到: $BK"
  for item in $REQUIRED; do
    [ -e "$DSH/$item" ] && gray "  $item" || gray "  ${item}（不存在，跳过）"
  done
  ok "预演：备份步骤"
else
  mkdir -p "$BK" || die "无法创建备份目录: $BK"

  FAILED=""
  for item in $REQUIRED; do
    src="$DSH/$item"
    if [ ! -e "$src" ]; then
      gray "跳过（不存在）: $item"
      continue
    fi
    dst="$BK/$item"
    mkdir -p "$(dirname "$dst")"
    if cp -R "$src" "$dst" 2>/dev/null; then
      ok "$item"
    else
      FAILED="$FAILED $item"
      printf '\033[1;31m  ✗ %s 复制失败\033[0m\n' "$item"
    fi
  done

  if [ -n "$FAILED" ]; then
    echo ""
    die "备份失败:$FAILED
    已停止，未做任何清理。修好权限或磁盘后重试。
    备份目录残留: $BK"
  fi

  # 写备份标记（清理阶段会检查）
  echo "$BK" > "$BK/.dsh-purge-backup-complete"
  ok "备份完成: $BK"
fi

# ── 2. 提示需要手动停的进程（本脚本不杀）────────────────
say "2) 需要你手动停掉的进程"
if [ "$DRY" = "1" ]; then
  gray "会列出 DSH 进程供你手动停"
else
  gray "本脚本不会杀任何进程。上面列出的 DSH 进程需要你手动停："
  gray ""
  gray "  方式 1（推荐）：退出桌面版 App，或在跑 dsh web 的终端按 Ctrl+C"
  gray "  方式 2（命令行）："
  if [ -x "$REPO/scripts/list-dsh-procs.sh" ]; then
    # 只列出 PID，给出 kill 命令让用户自己执行
    PIDS=$(bash "$REPO/scripts/list-dsh-procs.sh" 2>/dev/null | grep '^DSH' | sed 's/.*PID=\([0-9]*\).*/\1/' | tr '\n' ' ')
    if [ -n "$PIDS" ]; then
      gray "    kill $PIDS"
      gray ""
      gray "  （上面这条命令请你确认 PID 无误后自己执行）"
    else
      gray "    没有找到需要停的 DSH 进程"
    fi
  fi
  gray ""
  gray "停完后按回车继续（或 Ctrl+C 中止）："
  [ "$YES" = "1" ] || read -r _ans

  # 重新检查：目标 DSH 进程是否真的停了
  # 用户可能只按了回车没真去停，这里必须验证
  if [ -x "$REPO/scripts/list-dsh-procs.sh" ]; then
    REMAIN=$(bash "$REPO/scripts/list-dsh-procs.sh" 2>/dev/null | grep -c '^DSH ' || true)
    REMAIN=${REMAIN:-0}
    if [ "$REMAIN" -gt 0 ]; then
      echo ""
      die "还有 $REMAIN 个 DSH 进程在跑，清理已中止。

    请先停掉它们：
      - 退出桌面版 App
      - 或在跑 dsh web 的终端按 Ctrl+C
      - 或手动执行上面列出的 kill 命令

    停掉后重新运行本脚本。"
    fi
    ok "DSH 进程已全部停止"
  fi
fi

# ── 3. 检查备份标记（清理入口的守门）──────────────────────
say "3) 检查备份"
if [ "$DRY" = "1" ]; then
  gray "会检查备份标记文件是否存在"
else
  LATEST_BK="$(ls -td "$HOME"/dsh-backup-* 2>/dev/null | head -1)"
  if [ -z "$LATEST_BK" ] || [ ! -f "$LATEST_BK/.dsh-purge-backup-complete" ]; then
    die "找不到完整备份标记，拒绝清理。
    备份必须成功后才能清理。如果刚做过备份，
    检查 $HOME/dsh-backup-*/ 下是否有 .dsh-purge-backup-complete
    如果没有，说明备份没完成，请重新运行本脚本。"
  fi
  ok "备份已验证: $LATEST_BK"
fi

# ── 3.5. 预检所有清理操作（这是删任何东西之前的最后一道关）──
say "3.5) 预检清理操作"
if [ "$DRY" = "1" ]; then
  gray "会预检 cordis.patch.yml 结构、package.json 可解析性"
else
  PRECHECK_FAIL=0

  # 预检 YAML 结构
  if [ -f "$REPO/scripts/clean-cordis-patch.cjs" ] && [ -f "$DSH/profiles/web/cordis.patch.yml" ]; then
    if OUT=$(DSH_HOME="$DSH" node "$REPO/scripts/clean-cordis-patch.cjs" --check-only 2>&1); then
      gray "cordis.patch.yml: $OUT"
    else
      printf '\033[1;31m  ✗ cordis.patch.yml 预检失败\033[0m\n'
      echo "$OUT" | sed 's/^/      /'
      PRECHECK_FAIL=1
    fi
  fi

  # 预检 package.json 可解析
  if [ -f "$DSH/profiles/web/package.json" ]; then
    if node -e "JSON.parse(require('fs').readFileSync('$DSH/profiles/web/package.json','utf8'))" 2>/dev/null; then
      gray "package.json: 可解析"
    else
      printf '\033[1;31m  ✗ package.json 解析失败\033[0m\n'
      PRECHECK_FAIL=1
    fi
  fi

  if [ "$PRECHECK_FAIL" = "1" ]; then
    echo ""
    die "预检失败，未删除任何文件、未改动任何配置。

    请先手动修复上面报错的文件，或按错误提示手动编辑，
    然后重新运行本脚本。"
  fi
  ok "预检通过，可以安全清理"
fi

# ── 4. 清插件目录 ─────────────────────────────────────────
say "4) 删除插件目录"
W="$DSH/profiles/web/node_modules"
if [ "$DRY" = "1" ]; then
  for p in dsh-purge dsh-purge-community dsh-purge-panel; do
    [ -d "$W/$p" ] && gray "会删 $W/$p"
  done
else
  for p in dsh-purge dsh-purge-community dsh-purge-panel; do
    [ -d "$W/$p" ] && rm -rf "$W/$p" && ok "已删 $p"
  done
fi

# ── 5. 清 YAML ────────────────────────────────────────────
say "5) 清理 cordis.patch.yml"
if [ "$DRY" = "1" ]; then
  gray "会移除 - id: dsh-purge / -community / -panel 及其子键"
else
  if [ -f "$REPO/scripts/clean-cordis-patch.cjs" ]; then
    DSH_HOME="$DSH" node "$REPO/scripts/clean-cordis-patch.cjs" 2>&1 | sed 's/^/     /'
  else
    warn "找不到 clean-cordis-patch.cjs，跳过"
  fi
fi

# ── 6. 清 package.json ────────────────────────────────────
say "6) 清理 profile package.json"
if [ "$DRY" = "1" ]; then
  gray "会移除 dsh-purge / -community / -panel 的 bundles 和 dependencies"
else
  if [ -f "$REPO/scripts/clean-profile-deps.cjs" ]; then
    DSH_HOME="$DSH" node "$REPO/scripts/clean-profile-deps.cjs" 2>&1 | sed 's/^/     /'
  else
    warn "找不到 clean-profile-deps.cjs，跳过"
  fi
fi

# ── 7. 清预设与状态 ───────────────────────────────────────
say "7) 清理预设与状态"
if [ "$DRY" = "1" ]; then
  gray "会删 .agent-presets/redteam 和 redteam/preset-declare.json"
else
  rm -rf "$DSH/.agent-presets/redteam" 2>/dev/null && ok "已删 .agent-presets/redteam"
  rm -f "$DSH/redteam/preset-declare.json" 2>/dev/null && ok "已删 preset-declare.json"
fi

# ── 8. 验证 ───────────────────────────────────────────────
say "8) 验证清理结果"
if [ "$DRY" = "1" ]; then
  gray "预演结束"
else
  W="$DSH/profiles/web"
  [ -d "$W/node_modules/dsh-purge" ] && warn "插件目录仍在" || ok "插件目录已清"
  if [ -f "$W/cordis.patch.yml" ]; then
    N=0
    grep -q "dsh-purge" "$W/cordis.patch.yml" 2>/dev/null && N=1
    [ "$N" = "0" ] && ok "patch.yml 无残留" || warn "patch.yml 还有 dsh-purge"
  fi
  if [ -f "$W/package.json" ]; then
    B=$(node -p "try{require('$W/package.json').dsh.profile.bundles.filter(x=>x.includes('purge')).length}catch(e){0}" 2>/dev/null || echo 0)
    [ "$B" = "0" ] && ok "bundles 无 dsh-purge" || warn "bundles 还有 $B 个 dsh-purge"
  fi
fi

echo ""
say "完成"
gray "备份: $BK"
gray "如果需要恢复: cp -R $BK/* $DSH/"
