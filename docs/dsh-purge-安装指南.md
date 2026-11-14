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

| `npm root -g` 输出 | 是否需要管理员 |
|---|---|
| `C:\Program Files\nodejs\node_modules` | 需要（Program Files 受保护） |
| `C:\Users\你\AppData\Roaming\npm\node_modules` | 不需要 |
| 其他盘（`D:\...`） | 看目录权限，可先试普通权限 |

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
f="/tmp/dsh-install.sh"
curl -fsSL --retry 3 --retry-delay 2 -o "$f" "$u" || { echo "下载失败"; exit 1; }
[ -s "$f" ] || { echo "文件为空"; exit 1; }
[ "$(wc -c <"$f")" -ge 1000 ] || { echo "下载不完整"; exit 1; }
head -1 "$f" | grep -q '^#!' || { echo "不是有效脚本"; exit 1; }
grep -q dsh-purge "$f" || { echo "内容不对"; exit 1; }
bash "$f"
```

### 为什么要分三步

| 写法 | 下载 404 时 | 下载中断时 |
|---|---|---|
| `curl \| bash` | **静默退出 0**，你以为装上了 | 可能执行不完整脚本 |
| 先下载后执行 | 明确报「下载失败」 | 校验字节数拦下来 |

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

## 第 7 步：验证（手动三步，缺一不可）

**不要只看一个文件就说装好了。** 下面三步各自证明不同的事：

| 步 | 证明什么 | 不能证明什么 |
|---|---|---|
| 1 | 装的是预期版本的**代码** | 代码有没有被加载 |
| 2 | 本次启动的**页面**里有插件入口 | 点「应用」有没有生效 |
| 3 | 本次操作**真的产生了变化** | —— |

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

**必须输出 `1.1.71-rc2.1`。**

不是 `1.1.71`（旧版，缺修复）就回到第 3 步重装。

---

### 第 2 步：确认本次启动的页面有插件入口

**做**：

```
浏览器里（dsh web 刚打开的页面）
→ 看会话标题旁边有没有 dsh-purge
→ 或看左侧栏的 ＋ 里有没有 Purge
```

**通过标准**：能看到入口。

**注意**：截图只能证明「界面长这样」，**不能**证明第 3 步成功。截图留作记录即可。

**看不到入口**：
- 确认是用 `dsh web` 启动的，不是桌面版 App
- 确认启动前设了 `REDTEAM_PRESET_REFRESH=1`
- `Ctrl+C` 停掉，重新 `dsh web`

---

### 第 3 步：确认「应用」之后真的产生了变化

**这是最关键的一步，也是最容易被旧文件骗过去的一步。**

#### 先记下当前时间

**Windows**
```powershell
Get-Date -Format "yyyy-MM-ddTHH:mm:ss"
```

**macOS**
```bash
date -u +"%Y-%m-%dT%H:%M:%SZ"
```

#### 点「应用」

```
dsh-purge → 清洗 → 应用
```

**等它自动重启（10-30 秒）**

#### 然后立刻查状态文件

**Windows**
```powershell
$f = "$env:USERPROFILE\.dsh\redteam\preset-declare.json"
if (-not (Test-Path $f)) { throw "文件不存在 → 本次没生成" }
$d = Get-Content $f -Raw | ConvertFrom-Json
Write-Host "at     : $($d.at)"
Write-Host "phase  : $($d.phase)"
Write-Host "plugins: $($d.plugins)"
Write-Host "broken : $($d.broken)"
$age = [int]((Get-Date).ToUniversalTime() - [datetime]::Parse($d.at).ToUniversalTime()).TotalSeconds
Write-Host "文件年龄: $age 秒"
if ($age -gt 600) { Write-Host "❌ 文件太旧，不能证明本次成功" -ForegroundColor Red }
elseif ($d.phase -eq "registered" -and -not $d.broken) { Write-Host "✅ 本次生成且状态正确" -ForegroundColor Green }
else { Write-Host "❌ 本次生成但状态不对: phase=$($d.phase) broken=$($d.broken)" -ForegroundColor Red }
```

**macOS**
```bash
f="$HOME/.dsh/redteam/preset-declare.json"
[ -f "$f" ] || { echo "❌ 文件不存在 → 本次没生成"; exit 1; }
node -e '
const d = require(process.argv[1]);
const age = Math.floor((Date.now() - Date.parse(d.at)) / 1000);
console.log("at     :", d.at);
console.log("phase  :", d.phase);
console.log("plugins:", d.plugins);
console.log("broken :", String(d.broken));
console.log("文件年龄:", age, "秒");
if (age > 600) { console.log("❌ 文件太旧，不能证明本次成功"); process.exit(1); }
if (d.phase === "registered" && !d.broken) { console.log("✅ 本次生成且状态正确"); }
else { console.log("❌ 本次生成但状态不对"); process.exit(1); }
' "$f"
```

#### 通过标准

```
✅ 文件存在
✅ at 时间是刚刚（10 分钟内）
✅ phase = registered
✅ broken = null
✅ plugins = 19
```

#### 这就是「旧文件骗人」的实际例子

```
昨天留下的文件：
  {"phase":"registered","plugins":19,"broken":null,"at":"2026-11-13T10:44:28Z"}

只看内容 → 判定成功   ← 误判！本次根本没启动成功
看 at 时间 → 年龄 86400 秒 → 拒绝  ← 正确
```

**所以第 3 步必须看 `at` 时间，不能只看 `phase`。**

---

### 三步全过才算装好

```
第 1 步  版本 = 1.1.71-rc2.1          ✅
第 2 步  本次页面有插件入口            ✅
第 3 步  at 是刚刚 + phase=registered + broken=null  ✅
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
f="/tmp/dsh-install.sh"
curl -fsSL --retry 3 -o "$f" "$u" || { echo "下载失败"; exit 1; }
[ "$(wc -c <"$f")" -ge 1000 ] || { echo "下载不完整"; exit 1; }
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
f="/tmp/dsh-diagnose.sh"
curl -fsSL --retry 3 -o "$f" "$u" || { echo "下载失败"; exit 1; }
[ "$(wc -c <"$f")" -ge 500 ] || { echo "下载不完整"; exit 1; }
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
