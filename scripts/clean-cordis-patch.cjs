#!/usr/bin/env node
/**
 * 精确清理 cordis.patch.yml 里的 dsh-purge 条目
 *
 * 用法:
 *   node scripts/clean-cordis-patch.cjs [DSH_HOME]
 *
 * 只移除明确列出的插件 id 那一条及其子键，不碰其他插件。
 * 删完若 - insert: 块变空，整块移除。
 * 不会删除任何不在 PURGE_IDS 里的条目。
 */

const fs = require("fs");
const os = require("os");
const path = require("path");

const PURGE_IDS = new Set(["dsh-purge", "dsh-purge-community", "dsh-purge-panel"]);

function cleanYaml(text) {
  const lines = text.split(/\r?\n/);
  const out = [];
  let i = 0;
  let removed = 0;

  // 第一轮：删掉 - id: dsh-purge 及其子键
  while (i < lines.length) {
    const line = lines[i];
    const m = line.match(/^(\s*)- id:\s*(\S+)\s*$/);
    if (m && PURGE_IDS.has(m[2])) {
      const indent = m[1].length;
      removed++;
      i++;
      // 跳过后续子键（缩进比 indent 深）和空行
      while (i < lines.length) {
        const l = lines[i];
        if (l.trim() === "") { i++; continue; }
        if (l.match(/^(\s*)/)[1].length > indent) { i++; continue; }
        break;
      }
      continue;
    }
    out.push(line);
    i++;
  }

  // 第二轮：删掉变空的 - insert: 块
  const out2 = [];
  for (let k = 0; k < out.length; k++) {
    const line = out[k];
    if (/^\s*- insert:\s*$/.test(line)) {
      const indent = line.match(/^(\s*)/)[1].length;
      let j = k + 1;
      let hasChild = false;
      while (j < out.length) {
        const l = out[j];
        if (l.trim() === "") { j++; continue; }
        if (l.match(/^(\s*)/)[1].length <= indent) break;
        hasChild = true;
        j++;
      }
      if (!hasChild) { k = j - 1; continue; }
    }
    out2.push(line);
  }

  let result = out2.join("\n").replace(/\n{3,}/g, "\n\n");
  if (!result.endsWith("\n")) result += "\n";
  return { text: result, removed };
}

function main() {
  const home = process.argv[2] || process.env.DSH_HOME || path.join(os.homedir(), ".dsh");
  const target = path.join(home, "profiles", "web", "cordis.patch.yml");

  if (!fs.existsSync(target)) {
    console.log("cordis.patch.yml 不存在，跳过");
    return 0;
  }

  const before = fs.readFileSync(target, "utf8");
  const { text, removed } = cleanYaml(before);

  if (removed === 0) {
    console.log("没有 dsh-purge 条目，文件未改动");
    return 0;
  }

  const bak = `${target}.bak-${Date.now()}`;
  fs.copyFileSync(target, bak);
  fs.writeFileSync(target, text);
  console.log(`已移除 ${removed} 个条目`);
  console.log(`备份: ${bak}`);
  return 0;
}

process.exit(main());
