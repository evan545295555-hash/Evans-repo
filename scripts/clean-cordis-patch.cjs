#!/usr/bin/env node
/**
 * 精确清理 cordis.patch.yml 里的 dsh-purge 条目
 *
 * 用法:
 *   node scripts/clean-cordis-patch.cjs [DSH_HOME]
 *
 * 只移除明确列出的插件 id 那一条及其子键，不碰其他插件。
 *
 * 安全策略：
 *   - 结构无法安全解析时（tab 缩进、flow style、块标量内含匹配）→ 报错退出，不改文件
 *   - 清理后若仍有 dsh-purge 条目 → 报错退出，不改文件
 *   - 改动前自动备份
 *   - 文件字节不变时不留备份
 */

const fs = require("fs");
const os = require("os");
const path = require("path");

const PURGE_IDS = new Set(["dsh-purge", "dsh-purge-community", "dsh-purge-panel"]);

/**
 * 预检：判断这份 YAML 是否能用逐行方式安全清理
 * 返回 { ok: true } 或 { ok: false, reason }
 */
function precheck(text) {
  const lines = text.split(/\r?\n/);

  // 1. tab 缩进：YAML 不允许，逐行解析会出错
  for (let i = 0; i < lines.length; i++) {
    if (/^[ ]*\t/.test(lines[i])) {
      return { ok: false, reason: `第 ${i + 1} 行用 tab 缩进（YAML 不允许），无法安全解析` };
    }
  }

  // 2. flow style：- {id: dsh-purge} —— 逐行扫描看不到
  for (let i = 0; i < lines.length; i++) {
    if (/^\s*-\s*\{/.test(lines[i]) && /dsh-purge/.test(lines[i])) {
      return { ok: false, reason: `第 ${i + 1} 行是 flow style（- {id: dsh-purge}），逐行清理无法处理` };
    }
  }

  // 3. 块标量（| 或 >）内部含 - id: dsh-purge —— 那是文本不是配置
  let blockIndent = -1;
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];

    if (blockIndent >= 0) {
      const indent = line.match(/^(\s*)/)[1].length;
      if (line.trim() === "" || indent > blockIndent) {
        if (/- id:\s*dsh-purge/.test(line)) {
          return { ok: false, reason: `第 ${i + 1} 行在块标量（多行字符串）内部，是文本不是配置，清理会破坏它` };
        }
        continue;
      }
      blockIndent = -1;
    }

    const bs = line.match(/^(\s*)\S.*:\s*[|>][+-]?\s*$/);
    if (bs) {
      blockIndent = bs[1].length;
    }
  }

  return { ok: true };
}

function cleanYaml(text) {
  const lines = text.split(/\r?\n/);
  const out = [];
  let i = 0;
  let removed = 0;

  while (i < lines.length) {
    const line = lines[i];
    const m = line.match(/^(\s*)- id:\s*(\S+)\s*$/);
    if (m && PURGE_IDS.has(m[2])) {
      const indent = m[1].length;
      removed++;
      i++;
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

  // 删掉变空的 - insert: 块
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

/** 清理后验证：确认没有 dsh-purge 条目残留 */
function postcheck(text) {
  const lines = text.split(/\r?\n/);
  for (let i = 0; i < lines.length; i++) {
    const m = lines[i].match(/^\s*- id:\s*(\S+)\s*$/);
    if (m && PURGE_IDS.has(m[2])) {
      return { ok: false, reason: `清理后第 ${i + 1} 行仍有 - id: ${m[2]}，结构可能超出逐行清理支持范围` };
    }
  }
  // flow style 残留
  for (let i = 0; i < lines.length; i++) {
    if (/^\s*-\s*\{/.test(lines[i]) && /dsh-purge/.test(lines[i])) {
      return { ok: false, reason: `清理后第 ${i + 1} 行仍有 flow style 的 dsh-purge` };
    }
  }
  return { ok: true };
}

function main() {
  const args = process.argv.slice(2);
  const checkOnly = args.includes("--check-only");
  const homeArg = args.find((a) => !a.startsWith("--"));
  const home = homeArg || process.env.DSH_HOME || path.join(os.homedir(), ".dsh");
  const target = path.join(home, "profiles", "web", "cordis.patch.yml");

  if (!fs.existsSync(target)) {
    if (checkOnly) { console.log("cordis.patch.yml 不存在，无需清理"); return 0; }
    console.log("cordis.patch.yml 不存在，跳过");
    return 0;
  }

  const before = fs.readFileSync(target, "utf8");

  // 预检
  const pre = precheck(before);
  if (!pre.ok) {
    console.error(`ERR 无法安全清理：${pre.reason}`);
    console.error(`    原文件未改动: ${target}`);
    console.error(`    请手动编辑该文件，移除 dsh-purge 相关条目。`);
    return 1;
  }

  const { text, removed } = cleanYaml(before);

  if (checkOnly) {
    console.log(`预检通过（会移除 ${removed} 个条目）`);
    return 0;
  }

  if (removed === 0) {
    console.log("没有 dsh-purge 条目，文件未改动");
    return 0;
  }

  // 清理后验证
  const post = postcheck(text);
  if (!post.ok) {
    console.error(`ERR 清理不完整：${post.reason}`);
    console.error(`    原文件未改动: ${target}`);
    console.error(`    请手动编辑该文件。`);
    return 1;
  }

  const bak = `${target}.bak-${Date.now()}`;
  fs.copyFileSync(target, bak);
  fs.writeFileSync(target, text);
  console.log(`已移除 ${removed} 个条目`);
  console.log(`备份: ${bak}`);
  return 0;
}

process.exit(main());
