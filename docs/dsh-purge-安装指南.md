# dsh-purge 全新安装指南

> 适用：从没装过 dsh，或已彻底清理干净
> 已装过 / 装坏了 → 看 [修复指南](https://github.com/evan545295555-hash/Evans-repo/blob/master/docs/dsh-purge-%E4%BF%AE%E5%A4%8D%E6%8C%87%E5%8D%97.md)

---

## 你需要什么

- Windows 10/11 或 macOS（Intel / Apple Silicon 都行）
- 能上网
- 约 1.5 GB 磁盘（宿主 830MB + 插件 2MB + 依赖）
- 15-25 分钟

---

## 第 0 步：打开终端

### Windows

```
Win 键 → 输入 powershell → 右键「Windows PowerShell」→「以管理员身份运行」→ 弹窗点「是」
```

窗口标题必须显示 **`管理员: Windows PowerShell`**。

**为什么要管理员**：这一步只是保守做法。判断依据是**实际写入位置**，不是「Node 装在哪」：

```
npm root -g          ← 看这个目录在不在需要提权的位置
```

| `npm root -g` 常见输出 | 通常是否需要管理员 |
|---|---|
| `C:\Program Files\nodejs\node_modules` | 需要（Program Files 受保护） |
| `C:\Users\<你>\AppData\Roaming\npm\node_modules` | 一般不需要 |
| `C:\Users\<你>\AppData\Local\...\node_modules` | 一般不需要 |
| 其他盘（`D:\...`、`E:\...`） | 看目录 ACL，可先试普通权限 |

**以上是常见例子，不是规则。** 真正判断依据：**实际安装目标是否可写**。不确定就用管理员，不会有副作用。

**不确定就用管理员**，不会有副作用。

### macOS

```
Command + 空格 → 输入「终端」→ 回车
```

---

## 第 1 步：检查 Node.js

```bash
node -v
```

### 结果判断

| 输出 | 下一步 |
|---|---|
| `v20.x` ~ `v26.x` | ✅ 跳到第 2 步 |
| `v18.x` 或更低 | 装新版（见下） |
| `'node' 不是内部或外部命令` / `command not found` | 装（见下） |

### 装 / 升级 Node

**Windows**
```powershell
winget install OpenJS.NodeJS.LTS
```

**macOS**
```bash
brew install node
```

### 装完必须做

```
1. 关掉所有终端窗口
2. 重新打开
3. node -v   ← 必须显示 v20 以上
```

---

## 第 2 步：Windows 额外一步（macOS 跳过）

```powershell
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
```

**会弹确认**：

```
是否要更改执行策略?
[Y] 是(Y)  [A] 全是(A)  [N] 否(N)  ...
```

**输入 `Y` 回车。**

**为什么要做**：Windows 的 `npm` 命令底层是 `npm.ps1`，被 PowerShell 默认策略拦住，不改的话后面每条 npm 命令都会报 `无法加载文件 ... 因为在此系统上禁止运行脚本`。

### 验证

```powershell
npm -v
```

出 `10.x` / `11.x` 版本号就好了。

---

## 第 3 步：安装

**下载 → 校验 → 执行，三步分开。** 不要用管道（`curl ... | bash`），下载失败时管道会静默返回成功，你会以为装上了实际什么都没发生。

### Windows

```powershell
$u = "https://raw.githubusercontent.com/evan545295555-hash/Evans-repo/7d2f3b20f51aba41b1fb3d6b5920c23c928039c8/install.ps1"
$f = "$env:TEMP\dsh-install.ps1"
Invoke-WebRequest -Uri $u -OutFile $f -UseBasicParsing
if ((Get-Item $f).Length -lt 1000) { throw "下载不完整，请重试" }
if (-not (Select-String -Path $f -Pattern "dsh-purge" -SimpleMatch -Quiet)) { throw "下载内容不对，请重试" }
& $f
```

### macOS

```bash
u="https://raw.githubusercontent.com/evan545295555-hash/Evans-repo/7d2f3b20f51aba41b1fb3d6b5920c23c928039c8/install.sh"
f="$(mktemp /tmp/dsh-install-XXXXXX.sh)"
trap 'rm -f "$f"' EXIT
curl -fsSL --retry 3 --retry-delay 2 -o "$f" "$u" || { echo "下载失败"; exit 1; }
[ -s "$f" ] || { echo "文件为空"; exit 1; }
[ "$(wc -c <"$f")" -ge 5000 ] || { echo "文件长度异常，可能不完整"; exit 1; }
head -1 "$f" | grep -q '^#!' || { echo "不是有效脚本"; exit 1; }
grep -q 'PLUGIN_VERSION' "$f" || { echo "内容不对"; exit 1; }
bash -n "$f" || { echo "脚本语法错误，可能下载不完整"; exit 1; }
bash "$f"
```

### 为什么要分三步

| 写法 | 下载 404 时 | 下载中途断开时 |
|---|---|---|
| `curl \| bash` | **静默退出 0**，你以为装上了 | 可能执行不完整脚本 |
| 先下载后执行 | 明确报「下载失败」 | curl 退出非 0，`.sh` 不执行 |

**四层防线，从强到弱**：

| 层 | 检查 | 拦得住什么 |
|---|---|---|
| 1 | `curl` 非 0 退出码 | 404、连接断开、超时 —— **最可靠** |
| 2 | `bash -n` 语法检查 | 下载中途截断（必然语法不完整） |
| 3 | 长度 ≥ 5000 字节 | 只收到响应头、极小文件 |
| 4 | `PLUGIN_VERSION` 关键字 | 拿到的是错误页面（HTML/404 页） |

**实测**：

```
3000 字节截断  → 第 3 层拦下
8000 字节截断  → 第 2 层拦下（unexpected EOF）
404 URL        → 第 1 层拦下
真脚本         → 全部通过
```

**这四层不是密码学校验。** 它们防的是「操作失误 / 网络故障」，不是「恶意投毒」。真要防投毒需要独立哈希，本轮未做（见文末说明）。

**这个区别已实测**：

```
旧写法（管道，404 URL）  → exit=0    ← 静默成功
新写法（先下载再校验）    → exit=1    ← 正确报错
```

### 关于固定版本

上面 URL 里的 `7d2f3b20f51aba41b1fb3d6b5920c23c928039c8` 是**固定提交**，不是 `master`。

- 好处：内容不会随时间变化，你装的和你看到的文档是同一份
- 代价：后续修复不会自动到你手上，需要重新按新文档执行

**如果你想用最新版**，把 URL 里的 `7d2f3b20f51aba41b1fb3d6b5920c23c928039c8` 换成 `master`，但仍建议保留「先下载再校验」的三步结构。

---

## 第 4 步：看懂安装输出

### 正常的输出长这样

**Windows**
```
==> dsh-purge 1.1.71-rc2.1 安装器（Windows）
OK  Node v24.16.0
OK  npm 策略 hoisted
OK  已装宿主 0.2.1-rc.2（兼容）        ← 已有宿主就跳过安装
OK  布局：嵌套（npm 全局默认，插件已兼容）
OK  原生模块已就绪                      ← 或「补跑原生模块构建…」后 OK
==> profile: C:\Users\xxx\.dsh\profiles\web
OK  已补齐缺失的 base / web-app
==> 下载插件 1.1.71-rc2.1
OK  已下载 2.1 MB
==> 安装插件到 profile
OK  插件已写入 node_modules
==> 登记到 profile bundles
OK  安装完成：dsh-purge 1.1.71-rc2.1

  ────────────────────────────────
   你给巴里啊啊点赞了吗？
  ────────────────────────────────
```

**macOS** 类似，只是 `OK  Node v26.13.0` 之类。

### 关键行对照

| 行 | 含义 |
|---|---|
| `OK Node v2x` | Node 合格 |
| `OK 已装宿主` | 复用现有宿主，没重装 |
| `==> 未检测到宿主，安装...` | 首次安装宿主，**要等 5-20 分钟** |
| `OK 原生模块已就绪` | node-pty 已编译，可直接用 |
| `==> 补跑原生模块构建` | 正在编译，**再等 30 秒 - 12 分钟** |
| `OK 安装完成` | **成功** |

### 出现这些就是失败

| 输出 | 怎么办 |
|---|---|
| `ERR 宿主安装失败` | 网络问题，重跑一次 |
| `ERR 下载失败` | 网络问题，重跑一次 |
| `ERR 版本不符` | 看修复指南 |
| `ERR node-pty 仍缺失` | 看修复指南的「原生模块」一节 |

---

## 第 5 步：启动

### Windows

```powershell
$env:REDTEAM_PRESET_REFRESH = "1"
dsh web
```

### macOS

```bash
export REDTEAM_PRESET_REFRESH=1
dsh web
```

**浏览器会自动打开 `http://127.0.0.1:3080/?token=...`**

### 如果浏览器没自动开

**复制终端里打印的 URL**（带 token 的那个）手动粘贴到浏览器。

### 如果报端口被占

```
Error: listen EADDRINUSE: address already in use 127.0.0.1:3080
```

说明有个旧的 `dsh web` 还在跑。换端口：

```bash
dsh web --port 3081
```

---

## 第 6 步：点「应用」（必须做）

**这是最后一步，也是最容易漏的一步。**

```
1. 界面上找到 dsh-purge（会话标题旁边，或左侧栏的 ＋ → Purge）
2. 点进去，停在「清洗」页
3. 点「应用」
4. 等它自动重启（约 10-30 秒）
```

### 为什么要手动点

**「应用」会改写宿主源码**（把破甲补丁写入 `dsh-system-prompt` 等文件），涉及文件写入 + 备份，必须由你确认。安装脚本不碰宿主源码。

---

## 第 7 步：验证（三件独立证据，缺一不可）

**先理解一件事**：`preset-declare.json` 是在**宿主启动、插件加载时**写入的，**不是你点「应用」时**。

所以它只能证明「插件加载成功」，**不能证明「应用写入了宿主」**。

三件事必须分别验证：

| 步 | 证明什么 | 证据在哪 |
|---|---|---|
| 1 | 装的是预期版本的**代码** | `package.json` 的 version |
| 2 | 本次启动**加载了插件** | `preset-declare.json` 的 `at` 是刚刚 |
| 3 | 点应用后**真的改写了宿主** | 宿主源码里出现 `[dsh-purge]` 标记 |

---

### 第 1 步：确认装的是 1.1.71-rc2.1

**Windows**
```powershell
node -p "require(process.env.USERPROFILE + '/.dsh/profiles/web/node_modules/dsh-purge/package.json').version"
```

**macOS**
```bash
node -p "require(require('os').homedir()+'/.dsh/profiles/web/node_modules/dsh-purge/package.json').version"
```

**必须输出 `1.1.71-rc2.1`。** 是 `1.1.71` 就回到第 3 步重装。

---

### 第 2 步：确认本次启动加载了插件

**先记下启动时间**，或者在启动后立刻跑下面这个。

**macOS / Linux**
```bash
f="$HOME/.dsh/redteam/preset-declare.json"
[ -f "$f" ] || { echo "❌ 文件不存在 → 插件没加载过"; exit 1; }
node -e '
const d = require(process.argv[1]);
const age = Math.floor((Date.now() - Date.parse(d.at)) / 1000);
console.log("  at     :", d.at);
console.log("  phase  :", d.phase);
console.log("  plugins:", d.plugins);
console.log("  broken :", String(d.broken));
console.log("  本次启动后经过:", age, "秒");
if (age > 600) { console.log("  ❌ 文件太旧，不是本次启动写的"); process.exit(1); }
if (d.phase !== "registered") { console.log("  ❌ phase 不是 registered:", d.phase); process.exit(1); }
if (d.broken) { console.log("  ❌ broken 不为空:", d.broken); process.exit(1); }
if (d.plugins !== 19) { console.log("  ⚠️ plugins =", d.plugins, "（正常是 19）"); }
console.log("  ✅ 本次启动已加载插件并注册成功");
' "$f"
```

**Windows**
```powershell
$f = "$env:USERPROFILE\.dsh\redteam\preset-declare.json"
if (-not (Test-Path $f)) { throw "文件不存在 → 插件没加载过" }
$d = Get-Content $f -Raw | ConvertFrom-Json
Write-Host "  at     : $($d.at)"
Write-Host "  phase  : $($d.phase)"
Write-Host "  plugins: $($d.plugins)"
Write-Host "  broken : $($d.broken)"
$age = [int]((Get-Date).ToUniversalTime() - [datetime]::Parse($d.at).ToUniversalTime()).TotalSeconds
Write-Host "  本次启动后经过: $age 秒"
if ($age -gt 600) { throw "文件太旧，不是本次启动写的" }
if ($d.phase -ne "registered") { throw "phase 不是 registered: $($d.phase)" }
if ($d.broken) { throw "broken 不为空: $($d.broken)" }
Write-Host "  ✅ 本次启动已加载插件并注册成功" -ForegroundColor Green
```

**为什么这一步够用**：`at` 在每次宿主启动时都会刷新。如果它距现在超过 10 分钟，说明你看的是上一次启动留下的文件。

**这一步不能证明什么**：不能证明你点过「应用」。继续第 3 步。

---

### 第 3 步：确认「应用」真的写进了宿主

**这才是「应用成功」的唯一直接证据。**

**前置条件**：已经点过「应用」（`dsh-purge → 清洗 → 应用`），并且宿主已自动重启完成。

**macOS / Linux**
```bash
node -e '
const { execSync } = require("child_process");
const fs = require("fs");
const path = require("path");

let root = "";
try { root = execSync("npm root -g", { encoding: "utf8" }).trim(); } catch (e) {
  console.log("  ❌ 读不到 npm root -g"); process.exit(1);
}

const cands = [
  path.join(root, "@deepseek-ai", "dsh-system-prompt", "lib", "index.js"),
  path.join(root, "@deepseek-ai", "dsh", "node_modules", "@deepseek-ai", "dsh-system-prompt", "lib", "index.js"),
  path.join(root, "dsh-system-prompt", "lib", "index.js"),
  path.join(root, "node_modules", "@deepseek-ai", "dsh-system-prompt", "lib", "index.js"),
];
let found = null;
for (const c of cands) { if (fs.existsSync(c)) { found = c; break; } }
if (!found) {
  console.log("  ❌ 四个候选路径都找不到 dsh-system-prompt");
  cands.forEach(c => console.log("    " + c));
  process.exit(1);
}
const text = fs.readFileSync(found, "utf8");
const n = (text.match(/\[dsh-purge\]/g) || []).length;
console.log("  宿主文件:", found);
console.log("  [dsh-purge] 标记:", n, "处");
if (n === 0) {
  console.log("  ❌ 没有标记 → 应用没生效，或根本没点应用");
  process.exit(1);
}
console.log("  ✅ 应用已写入宿主");
'
```

**Windows**
```powershell
$root = (npm root -g).Trim()
$cands = @(
    (Join-Path $root "@deepseek-ai\dsh-system-prompt\lib\index.js"),
    (Join-Path $root "@deepseek-ai\dsh\node_modules\@deepseek-ai\dsh-system-prompt\lib\index.js"),
    (Join-Path $root "dsh-system-prompt\lib\index.js"),
    (Join-Path $root "node_modules\@deepseek-ai\dsh-system-prompt\lib\index.js")
)
$found = $cands | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $found) {
    Write-Host "  ❌ 四个候选路径都找不到 dsh-system-prompt" -ForegroundColor Red
    $cands | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
    exit 1
}
$text = Get-Content $found -Raw
$n = ([regex]::Matches($text, '\[dsh-purge\]')).Count
Write-Host "  宿主文件: $found"
Write-Host "  [dsh-purge] 标记: $n 处"
if ($n -eq 0) {
    Write-Host "  ❌ 没有标记 → 应用没生效，或根本没点应用" -ForegroundColor Red
    exit 1
}
Write-Host "  ✅ 应用已写入宿主" -ForegroundColor Green
```

#### 期望输出

```
宿主文件: /opt/homebrew/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-system-prompt/lib/index.js
[dsh-purge] 标记: 6 处
✅ 应用已写入宿主
```

**标记数是 0 → 应用没成功。**

---

### 为什么不能用「10 分钟内的旧文件」判成功

**反例**（这是真实会发生的）：

```
t0      点应用，成功 → preset-declare.json 更新，at = t0
t0+60   你在做别的事
t0+80   重启宿主，这次插件崩了 → 但 preset-declare.json 没被更新
t0+140  你跑验收 → 文件年龄 = 140 秒 < 600 → 判定成功  ← 误判
```

**`at` 是「插件加载时间」，不是「应用成功时间」。两者没有任何关系。**

所以：
- 第 2 步的 `at` 只能证明「这次启动加载了插件」
- **必须靠第 3 步的宿主标记证明「应用生效」**

---

### 三步全过才算装好

```
第 1 步  版本 = 1.1.71-rc2.1                        ✅
第 2 步  preset-declare.json 是本次启动写的 + registered + broken=null  ✅
第 3 步  宿主源码里有 [dsh-purge] 标记               ✅
```

**任何一步不过，看 [修复指南](https://github.com/evan545295555-hash/Evans-repo/blob/master/docs/dsh-purge-%E4%BF%AE%E5%A4%8D%E6%8C%87%E5%8D%97.md)。**

## 安装完成后你能做什么

```
1. 会话模式下拉里出现「红队模式」
2. 左侧栏出现 Purge 面板（清洗 / 演练台 / 状态 / 维护）
3. 不同模型可以换不同提示词
```

---

## 常见问题

### Q1: `dsh web` 报 `Cannot find module ...node-pty...`

原生模块没编译。跑这个（30 秒 - 12 分钟）：

**Windows**
```powershell
npm i -g @deepseek-ai/dsh@0.2.1-rc.2 --allow-scripts=@deepseek-ai/dsh-subprocess-local,koffi,node-pty,@google/genai,protobufjs
```

**macOS**
```bash
npm i -g @deepseek-ai/dsh@0.2.1-rc.2 --allow-scripts=@deepseek-ai/dsh-subprocess-local,koffi,node-pty,@google/genai,protobufjs
```

### Q2: `irm` / `curl` 报连接失败

GitHub 网络问题，重跑一次。多次失败可以试镜像：

```powershell
$u = "https://ghfast.top/https://raw.githubusercontent.com/evan545295555-hash/Evans-repo/7d2f3b20f51aba41b1fb3d6b5920c23c928039c8/install.ps1"
$f = "$env:TEMP\dsh-install.ps1"
Invoke-WebRequest -Uri $u -OutFile $f -UseBasicParsing
if ((Get-Item $f).Length -lt 1000) { throw "下载不完整，请重试" }
& $f
```

```bash
u="https://ghfast.top/https://raw.githubusercontent.com/evan545295555-hash/Evans-repo/7d2f3b20f51aba41b1fb3d6b5920c23c928039c8/install.sh"
f="$(mktemp /tmp/dsh-install-XXXXXX.sh)"
trap 'rm -f "$f"' EXIT
curl -fsSL --retry 3 -o "$f" "$u" || { echo "下载失败"; exit 1; }
[ "$(wc -c <"$f")" -ge 5000 ] || { echo "文件长度异常"; exit 1; }
bash -n "$f" || { echo "脚本语法错误，可能下载不完整"; exit 1; }
bash "$f"
```

### Q3: 点「应用」报「清洗没有写进全部宿主」

插件版本不对（装了旧版 `1.1.71` 而不是 `1.1.71-rc2.1`）。

**查版本**
```bash
node -p "require(require('os').homedir()+'/.dsh/profiles/web/node_modules/dsh-purge/package.json').version"
```

**不是 `1.1.71-rc2.1` 就重跑第 3 步**（新版会自动清掉旧版再装）。

### Q4: dsh-purge 按钮完全不出现

| 原因 | 处理 |
|---|---|
| 用的是桌面版 App 而不是 `dsh web` | 改成命令行跑 `dsh web` |
| 装完没重启宿主 | `Ctrl+C` 停掉，重新 `dsh web` |
| 没设 `REDTEAM_PRESET_REFRESH=1` | 启动前先设 |

### Q5: 想先看看环境再装

有只读诊断脚本，不改任何东西：

**Windows**
```powershell
$u = "https://raw.githubusercontent.com/evan545295555-hash/Evans-repo/7d2f3b20f51aba41b1fb3d6b5920c23c928039c8/diagnose.ps1"
$f = "$env:TEMP\dsh-diagnose.ps1"
Invoke-WebRequest -Uri $u -OutFile $f -UseBasicParsing
if ((Get-Item $f).Length -lt 500) { throw "下载不完整，请重试" }
& $f
```

**macOS**
```bash
u="https://raw.githubusercontent.com/evan545295555-hash/Evans-repo/7d2f3b20f51aba41b1fb3d6b5920c23c928039c8/diagnose.sh"
f="$(mktemp /tmp/dsh-diagnose-XXXXXX.sh)"
curl -fsSL --retry 3 -o "$f" "$u" || { echo "下载失败"; exit 1; }
[ "$(wc -c <"$f")" -ge 3000 ] || { echo "文件长度异常"; exit 1; }
bash "$f"
```

输出 8 项检查（Node / 宿主 / 布局 / dsh 命令 / 插件 / profile 配置 / 红队模式 / 残留），每项标 `[OK]` / `[WARN]` / `[FAIL]`。

---

## 一页速查

```
第 0 步  管理员 PowerShell / 终端
第 1 步  node -v        → 必须 v20+
第 2 步  Set-ExecutionPolicy（仅 Windows）
第 3 步  irm / curl 安装脚本
第 4 步  看到 "OK 安装完成" = 成功
第 5 步  dsh web（带 REDTEAM_PRESET_REFRESH=1）
第 6 步  点 dsh-purge → 清洗 → 应用
第 7 步  查 preset-declare.json = registered / 19 / null
```

---

## 关键数字

| 项 | 正确值 |
|---|---|
| Node | `v20.x` 以上 |
| 宿主 | `@deepseek-ai/dsh@0.2.1-rc.2` |
| 插件 | `1.1.71-rc2.1` |
| 插件数 | `19` |
| phase | `registered` |
| broken | `null` |
| 端口 | `3080`（或自定义） |

---

**任何一步输出对不上，看 [修复指南](https://github.com/evan545295555-hash/Evans-repo/blob/master/docs/dsh-purge-%E4%BF%AE%E5%A4%8D%E6%8C%87%E5%8D%97.md)。**
