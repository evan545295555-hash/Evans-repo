#!/usr/bin/env node
// 安装脚本的静态检查（CI 与本地共用）
// 用法: node scripts/check-scripts.mjs

import fs from "node:fs";
import path from "node:path";
import process from "node:process";

const root = process.cwd();
let failures = 0;

function fail(msg) {
  console.error(`FAIL ${msg}`);
  failures++;
}
function ok(msg) {
  console.log(`OK   ${msg}`);
}
function read(name) {
  const p = path.join(root, name);
  if (!fs.existsSync(p)) return null;
  return fs.readFileSync(p, "utf8");
}

// ── 1. 变量紧跟中文（C.UTF-8 下 bash 会当成变量名的一部分）──────────
console.log("\n[1] 变量紧跟中文检查");
for (const name of ["install.sh", "diagnose.sh", "scripts/test-recovery.sh"]) {
  const t = read(name);
  if (!t) {
    console.log(`  ${name} 不存在，跳过`);
    continue;
  }
  let hits = 0;
  t.split("\n").forEach((line, i) => {
    const re = /\$([A-Za-z_][A-Za-z0-9_]*)([^\x00-\x7F])/g;
    let m;
    while ((m = re.exec(line)) !== null) {
      fail(`${name}:${i + 1}  $${m[1]} 后紧跟 '${m[2]}'  →  ${line.trim().slice(0, 70)}`);
      hits++;
    }
  });
  if (hits === 0) ok(`${name} 无裸变量紧跟中文`);
}

// ── 2. install 脚本不得无条件 --force 重装宿主 ──────────────────────
console.log("\n[2] 禁止 --force 重装宿主");
const forcePatterns = [
  /dsh@[^\s"']*[^\r\n]{0,50}--force/,
  /npm i -g\s+"?@deepseek-ai\/dsh[^\r\n]{0,50}--force/,
];
for (const name of ["install.sh", "install.ps1"]) {
  const t = read(name);
  if (!t) continue;
  let hits = 0;
  t.split("\n").forEach((line, i) => {
    if (line.trim().startsWith("#")) return;
    for (const re of forcePatterns) {
      if (re.test(line)) {
        fail(`${name}:${i + 1}  含 --force 重装宿主  →  ${line.trim().slice(0, 70)}`);
        hits++;
      }
    }
  });
  if (hits === 0) ok(`${name} 无 --force 重装`);
}

// ── 3. diagnose 脚本必须纯只读 ─────────────────────────────────────
console.log("\n[3] diagnose 脚本纯只读");
// 只匹配真正的写操作；排除 2>/dev/null、>/dev/null、>&1 等
const readonlyBanned = [
  ["diagnose.ps1", /Remove-Item|Set-Content|New-Item|Out-File|Add-Content/],
  ["diagnose.sh", [
    /\brm\s+(-[a-zA-Z]+\s+)*[^\s>]/,        // rm 后面跟路径
    /(?<![0-9&])>(?!>)(?!&)(?!\s*\/dev\/null)/, // 重定向到非 /dev/null
    /\btee\s/,                                 // tee
    /\bmv\s+\S/,                              // mv
    /\bcp\s+-?\w*\s+\S/,                      // cp
    /\bmkdir\s/,                              // mkdir
    /\btouch\s/,                              // touch
  ]],
];
for (const [name, matcher] of readonlyBanned) {
  const t = read(name);
  if (!t) continue;
  const res = Array.isArray(matcher) ? matcher : [matcher];
  let hits = 0;
  t.split("\n").forEach((line, i) => {
    if (line.trim().startsWith("#")) return;
    for (const re of res) {
      re.lastIndex = 0;
      if (re.test(line)) {
        fail(`${name}:${i + 1}  疑似写操作  →  ${line.trim().slice(0, 70)}`);
        hits++;
        break;
      }
    }
  });
  if (hits === 0) ok(`${name} 纯只读`);
}

// ── 4. 关键结构存在 ────────────────────────────────────────────────
console.log("\n[4] 关键结构");
const sh = read("install.sh");
if (sh) {
  sh.includes("native_ok") ? ok("install.sh 有 native_ok") : fail("install.sh 缺 native_ok");
  sh.includes("prebuilds") ? ok("install.sh 兼容 prebuilds 布局") : fail("install.sh 缺 prebuilds 检测");
  sh.includes("conpty") ? ok("install.sh 兼容 Windows conpty.node") : fail("install.sh 缺 conpty 检测（Windows 上会误判未编译）");
  sh.includes("allow-scripts") ? ok("install.sh 有 allow-scripts") : fail("install.sh 缺 allow-scripts");
  const m = sh.match(/HOST_VERSION="([^"]+)"/);
  m ? ok(`install.sh HOST_VERSION=${m[1]}`) : fail("install.sh 缺 HOST_VERSION");
}
const ps = read("install.ps1");
if (ps) {
  ps.includes("Test-NativeOk") ? ok("install.ps1 有 Test-NativeOk") : fail("install.ps1 缺 Test-NativeOk");
  ps.includes("prebuilds") ? ok("install.ps1 兼容 prebuilds 布局") : fail("install.ps1 缺 prebuilds 检测");
  ps.includes("conpty") ? ok("install.ps1 兼容 Windows conpty.node") : fail("install.ps1 缺 conpty 检测（Windows 上会误判未编译）");
  ps.includes("allow-scripts") ? ok("install.ps1 有 allow-scripts") : fail("install.ps1 缺 allow-scripts");
  const m = ps.match(/\$HostVersion\s*=\s*"([^"]+)"/);
  m ? ok(`install.ps1 HostVersion=${m[1]}`) : fail("install.ps1 缺 HostVersion");
}

// ── 5. 两个脚本的宿主版本必须一致 ──────────────────────────────────
console.log("\n[5] 版本一致性");
if (sh && ps) {
  const a = sh.match(/HOST_VERSION="([^"]+)"/)?.[1];
  const b = ps.match(/\$HostVersion\s*=\s*"([^"]+)"/)?.[1];
  if (a && b) {
    a === b
      ? ok(`宿主版本一致: ${a}`)
      : fail(`宿主版本不一致: sh=${a} ps1=${b}`);
  }
  const pa = sh.match(/PLUGIN_VERSION="([^"]+)"/)?.[1];
  const pb = ps.match(/\$PluginVersion\s*=\s*"([^"]+)"/)?.[1];
  if (pa && pb) {
    pa === pb
      ? ok(`插件版本一致: ${pa}`)
      : fail(`插件版本不一致: sh=${pa} ps1=${pb}`);
  }
  // package.json 里的版本也要一致
  const pkg = read("package.json");
  if (pkg && pa) {
    const v = JSON.parse(pkg).version;
    v === pa
      ? ok(`package.json 版本一致: ${v}`)
      : fail(`package.json 版本 ${v} ≠ 脚本 ${pa}`);
  }
}

console.log("");
if (failures > 0) {
  console.error(`\n共有 ${failures} 项失败\n`);
  process.exit(1);
}
console.log("全部通过\n");
