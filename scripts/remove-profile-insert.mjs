#!/usr/bin/env node
/**
 * 精确移除 profile/cordis.patch.yml 里安装器写入的 dsh-purge insert 块。
 *
 * lib/uninstall.js 的 --uninstall 会还原宿主补丁、清掉 package.json 的
 * dependencies/bundles，但不会碰 cordis.patch.yml 的本体 insert（#154 补的那段）。
 * 残留会让宿主启动时挂载一个已不存在的 bundle，表现为「起不来」。
 *
 * 安全边界：只删与 INSERT_BLOCK 逐行完全一致的一整块，不解析、不重写 YAML，
 * 不碰用户其它条目。形态对不上（用户改过 config / 手工加过行）就一律不动，
 * 只把残留行号报出来让人工处理。
 *
 * 用法： node scripts/remove-profile-insert.mjs <profile-dir> [--dry-run]
 * 输出： 单行 JSON，status ∈ no-file | absent | unrecognized | would-remove | removed
 */
import fs from "node:fs";
import path from "node:path";

const BLOCK = [
  "- insert:",
  "    - id: dsh-purge",
  "      name: dsh-purge",
  "      inject: [systemPrompt, tools]",
  "      config:",
  "        enabled: true",
  "        stripMnemon: true",
  "        capabilityProtocol: true",
  "        hooksDenyBypass: true",
];

const profileDir = process.argv[2];
const dryRun = process.argv.includes("--dry-run");
const fp = profileDir ? path.join(profileDir, "cordis.patch.yml") : "";
const emit = (obj) => process.stdout.write(`${JSON.stringify(obj)}\n`);

if (!profileDir || !fs.existsSync(fp)) {
  emit({ status: "no-file", path: fp });
  process.exit(0);
}

const original = fs.readFileSync(fp, "utf8");
const eol = original.includes("\r\n") ? "\r\n" : "\n";
const lines = original.split(/\r?\n/);
const norm = (s) => s.replace(/\s+$/, "");

// 残留定位（无论能否自动删都报出来）
const leftovers = [];
for (let i = 0; i < lines.length; i += 1) {
  if (/^\s*-?\s*(id|name):\s*dsh-purge(-main)?\s*$/.test(norm(lines[i]))) leftovers.push(i + 1);
}

// 找连续且逐行完全一致的整块
let start = -1;
for (let i = 0; i + BLOCK.length <= lines.length; i += 1) {
  let match = true;
  for (let j = 0; j < BLOCK.length; j += 1) {
    if (norm(lines[i + j]) !== BLOCK[j]) { match = false; break; }
  }
  if (match) { start = i; break; }
}

if (start < 0) {
  emit({
    status: leftovers.length ? "unrecognized" : "absent",
    path: fp,
    lines: leftovers,
  });
  process.exit(0);
}

const next = [...lines.slice(0, start), ...lines.slice(start + BLOCK.length)];
const cleaned = [];
for (const line of next) {
  if (line.trim() === "" && cleaned.length && cleaned[cleaned.length - 1].trim() === "") continue;
  cleaned.push(line);
}
// 删完若无任何数据行，写回宿主认得的空 flow 序列（不要留成空文档）
const hasData = cleaned.some((l) => {
  const t = l.trim();
  return t && !t.startsWith("#") && t !== "---";
});
const out = `${(hasData ? cleaned.join(eol) : "[]").replace(/\s+$/, "")}${eol}`;

if (dryRun) {
  emit({ status: "would-remove", path: fp, blockStart: start + 1 });
  process.exit(0);
}

fs.writeFileSync(fp, out, "utf8");
emit({ status: "removed", path: fp, blockStart: start + 1 });
