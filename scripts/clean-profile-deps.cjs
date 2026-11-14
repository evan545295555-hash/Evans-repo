#!/usr/bin/env node
/**
 * 精确清理 profile package.json 里的 dsh-purge 依赖与 bundles
 *
 * 用法:
 *   node scripts/clean-profile-deps.cjs [DSH_HOME]
 *
 * 只移除 PURGE_NAMES 里明确列出的包。
 * 不按「名称包含 purge」模糊匹配，避免误删 third-party-purge-tool 之类。
 */

const fs = require("fs");
const os = require("os");
const path = require("path");

const PURGE_NAMES = new Set(["dsh-purge", "dsh-purge-community", "dsh-purge-panel"]);

function main() {
  const home = process.argv[2] || process.env.DSH_HOME || path.join(os.homedir(), ".dsh");
  const target = path.join(home, "profiles", "web", "package.json");

  if (!fs.existsSync(target)) {
    console.log("profile package.json 不存在，跳过");
    return 0;
  }

  const raw = fs.readFileSync(target, "utf8");
  let d;
  try {
    d = JSON.parse(raw);
  } catch (e) {
    console.error(`package.json 解析失败: ${e.message}`);
    return 1;
  }

  let changed = false;

  if (d.dsh && d.dsh.profile && Array.isArray(d.dsh.profile.bundles)) {
    const kept = d.dsh.profile.bundles.filter((x) => !PURGE_NAMES.has(x));
    if (kept.length !== d.dsh.profile.bundles.length) {
      d.dsh.profile.bundles = kept;
      changed = true;
    }
  }

  if (d.dependencies && typeof d.dependencies === "object") {
    for (const k of Object.keys(d.dependencies)) {
      if (PURGE_NAMES.has(k)) {
        delete d.dependencies[k];
        changed = true;
      }
    }
  }

  if (!changed) {
    console.log("没有 dsh-purge 相关条目，文件未改动");
    return 0;
  }

  const bak = `${target}.bak-${Date.now()}`;
  fs.copyFileSync(target, bak);
  fs.writeFileSync(target, JSON.stringify(d, null, 2) + "\n");
  console.log("bundles:", (d.dsh && d.dsh.profile && d.dsh.profile.bundles || []).join(",") || "空");
  console.log(`备份: ${bak}`);
  return 0;
}

process.exit(main());
