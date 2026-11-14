# dsh-purge 修复指南

> 适用：装过 dsh-purge 但用不了、报错、或装了一半
> 从没装过 → 看 [安装指南](https://github.com/evan545295555-hash/Evans-repo/blob/master/docs/dsh-purge-%E5%AE%89%E8%A3%85%E6%8C%87%E5%8D%97.md)

---

## 先做这一步：跑诊断

**不要凭感觉修。先跑诊断，它会告诉你卡在哪。**

### Windows

```powershell
$u = "https://raw.githubusercontent.com/evan545295555-hash/Evans-repo/7d2f3b20f51aba41b1fb3d6b5920c23c928039c8/diagnose.ps1"
$f = "$env:TEMP\dsh-diagnose.ps1"
Invoke-WebRequest -Uri $u -OutFile $f -UseBasicParsing
if ((Get-Item $f).Length -lt 500) { throw "下载不完整，请重试" }
& $f
```

### macOS

```bash
u="https://raw.githubusercontent.com/evan545295555-hash/Evans-repo/7d2f3b20f51aba41b1fb3d6b5920c23c928039c8/diagnose.sh"
f="$(mktemp /tmp/dsh-diagnose-XXXXXX.sh)"
trap 'rm -f "$f"' EXIT
curl -fsSL --retry 3 -o "$f" "$u" || { echo "下载失败"; exit 1; }
[ "$(wc -c <"$f")" -ge 3000 ] || { echo "文件长度异常"; exit 1; }
bash "$f"
```

### 这是只读脚本

```
不改任何文件
不删任何东西
只输出 8 项检查结果
```

输出长这样：

```
============================================================
 dsh-purge 环境诊断（只读）
 本脚本不会修改任何文件
============================================================

1. Node.js
  版本: v24.16.0
  [OK]   符合要求（需要 20+）
  npm: 11.13.0

2. 宿主 (DeepSeek Harness)
  npm 全局根: C:\Users\xxx\AppData\Roaming\npm\node_modules
  [OK]   已装: @deepseek-ai/dsh@0.2.1-rc.2
  [OK]   版本兼容（0.2.x）

3. 宿主依赖布局
  [OK]   嵌套布局（npm 全局默认，插件已兼容）

4. dsh 命令
  路径: C:\Users\xxx\AppData\Roaming\npm\dsh.cmd
  [OK]   来自当前 Node 安装（正确）

5. 插件 (dsh-purge)
  [OK]   已装: 1.1.71-rc2.1
  [OK]   版本正确

6. profile 配置
  bundles: @deepseek-ai/dsh-base,@deepseek-ai/dsh-web-app,dsh-purge
  [OK]   dsh-purge 已登记
  [OK]   base 存在
  [OK]   web-app 存在
  patch.yml 里 dsh-purge 提及: 2

7. 红队模式
  phase  : registered
  plugins: 19
  broken : null
  [OK]   注册成功

8. 残留检查
  （没有任何输出 = 没有残留）
```

**全部 `[OK]` = 环境正常。** 有 `[FAIL]` 或 `[WARN]` 就看下面的对照表。

---

## 症状 → 修复对照表

| # | 诊断里看到的 | 你遇到的 | 跳到 |
|---|---|---|---|
| 1 | `5. 插件: 未安装` | 装完没有任何东西 | [情况 1](#情况-1插件没装成功) |
| 2 | `5. 插件: 1.1.71`（不是 rc2.1） | 点应用报「清洗没有写进全部宿主」 | [情况 2](#情况-2插件是旧版-1171) |
| 3 | `3. 布局: 两种都找不到` | 装完 dsh web 崩 | [情况 3](#情况-3宿主依赖缺失) |
| 4 | `6. bundles 缺 base 或 web-app` | `phase: waiting-registry` | [情况 4](#情况-4bundles-缺-baseweb-app) |
| 5 | `7. phase: registered-broken` | 红队模式里某些功能没有 | [情况 5](#情况-5phase-registered-broken) |
| 6 | `8. 残留检查` 有输出 | 装了两套、版本混乱 | [情况 6](#情况-6有多套残留) |
| 7 | 全部 FAIL，一片红 | 什么都不对 | [情况 7](#情况-7彻底重来) |

---

# 情况 1：插件没装成功

**诊断显示**：`5. 插件: 未安装`

## 先看 install 脚本的输出

如果你跑过 install 脚本但失败了，**把最后 10 行发出来**。常见几种：

| install 输出 | 原因 | 修复 |
|---|---|---|
| `ERR 下载失败` | GitHub 网络 | 重跑一次，或用镜像（见文末） |
| `ERR npm install 失败` | 网络 / 磁盘满 / 权限 | 重跑一次；检查磁盘空间 |
| `ERR 宿主安装失败` | 网络 | 重跑一次 |
| 无任何输出就退出 | PowerShell 执行策略 | 见「情况 0」 |

## 情况 0：PowerShell 执行策略（仅 Windows）

**症状**：

```
npm : 无法加载文件 C:\Program Files\nodejs\npm.ps1，
      因为在此系统上禁止运行脚本。
```

**修复**：

```powershell
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
```

**输入 `Y` 回车**，然后：

```powershell
npm -v
```

出版本号就好了。**然后重跑安装脚本。**

## 修复：重跑安装脚本

```powershell
# Windows
$u = "https://raw.githubusercontent.com/evan545295555-hash/Evans-repo/7d2f3b20f51aba41b1fb3d6b5920c23c928039c8/install.ps1"
$f = "$env:TEMP\dsh-install.ps1"
Invoke-WebRequest -Uri $u -OutFile $f -UseBasicParsing
if ((Get-Item $f).Length -lt 5000) { throw "文件长度异常，请重试" }
& $f
```

```bash
# macOS
u="https://raw.githubusercontent.com/evan545295555-hash/Evans-repo/7d2f3b20f51aba41b1fb3d6b5920c23c928039c8/install.sh"
f="$(mktemp /tmp/dsh-install-XXXXXX.sh)"
trap 'rm -f "$f"' EXIT
curl -fsSL --retry 3 -o "$f" "$u" || { echo "下载失败"; exit 1; }
[ "$(wc -c <"$f")" -ge 5000 ] || { echo "文件长度异常"; exit 1; }
bash -n "$f" || { echo "脚本语法错误，可能下载不完整"; exit 1; }
bash "$f"
```

## 验证

```powershell
# Windows
node -p "require(process.env.USERPROFILE+'/.dsh/profiles/web/node_modules/dsh-purge/package.json').version"
```

```bash
# macOS
node -p "require(require('os').homedir()+'/.dsh/profiles/web/node_modules/dsh-purge/package.json').version"
```

**必须输出 `1.1.71-rc2.1`**

---

# 情况 2：插件是旧版 1.1.71

**诊断显示**：`5. 插件: 1.1.71` / `[WARN] 版本不是 1.1.71-rc2.1，可能缺修复`

**症状**：点「应用」时报

```
清洗没有写进全部宿主，已取消重启
```

或

```
应用失败：取物失败
```

## 为什么会这样

旧版 `1.1.71` 检测宿主时只认一种目录布局（`@deepseek-ai/dsh-system-prompt`），但 npm 全局安装默认是嵌套布局（`@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-system-prompt`），旧版找不到就以为「没写进宿主」。

`1.1.71-rc2.1` 修了这个问题（4 个候选路径）。

## 修复：重跑安装脚本（新版会自动清掉旧版）

```powershell
# Windows
$u = "https://raw.githubusercontent.com/evan545295555-hash/Evans-repo/7d2f3b20f51aba41b1fb3d6b5920c23c928039c8/install.ps1"
$f = "$env:TEMP\dsh-install.ps1"
Invoke-WebRequest -Uri $u -OutFile $f -UseBasicParsing
if ((Get-Item $f).Length -lt 5000) { throw "文件长度异常，请重试" }
& $f
```

```bash
# macOS
u="https://raw.githubusercontent.com/evan545295555-hash/Evans-repo/7d2f3b20f51aba41b1fb3d6b5920c23c928039c8/install.sh"
f="$(mktemp /tmp/dsh-install-XXXXXX.sh)"
trap 'rm -f "$f"' EXIT
curl -fsSL --retry 3 -o "$f" "$u" || { echo "下载失败"; exit 1; }
[ "$(wc -c <"$f")" -ge 5000 ] || { echo "文件长度异常"; exit 1; }
bash -n "$f" || { echo "脚本语法错误，可能下载不完整"; exit 1; }
bash "$f"
```

**新版会输出这一行**：

```
==> 检测到已装 1.1.71，先移除再装 1.1.71-rc2.1
```

## 如果重跑后版本还是 1.1.71

**手动清掉再装**：

```powershell
# Windows
Remove-Item -Recurse -Force "$env:USERPROFILE\.dsh\profiles\web\node_modules\dsh-purge"
$u = "https://raw.githubusercontent.com/evan545295555-hash/Evans-repo/7d2f3b20f51aba41b1fb3d6b5920c23c928039c8/install.ps1"
$f = "$env:TEMP\dsh-install.ps1"
Invoke-WebRequest -Uri $u -OutFile $f -UseBasicParsing
if ((Get-Item $f).Length -lt 5000) { throw "文件长度异常，请重试" }
& $f
```

```bash
# macOS
rm -rf ~/.dsh/profiles/web/node_modules/dsh-purge
u="https://raw.githubusercontent.com/evan545295555-hash/Evans-repo/7d2f3b20f51aba41b1fb3d6b5920c23c928039c8/install.sh"
f="$(mktemp /tmp/dsh-install-XXXXXX.sh)"
trap 'rm -f "$f"' EXIT
curl -fsSL --retry 3 -o "$f" "$u" || { echo "下载失败"; exit 1; }
[ "$(wc -c <"$f")" -ge 5000 ] || { echo "文件长度异常"; exit 1; }
bash -n "$f" || { echo "脚本语法错误，可能下载不完整"; exit 1; }
bash "$f"
```

## 验证

```bash
node -p "require(require('os').homedir()+'/.dsh/profiles/web/node_modules/dsh-purge/package.json').version"
```

**必须是 `1.1.71-rc2.1`**

---

# 情况 3：宿主依赖缺失

**诊断显示**：`3. 宿主依赖布局` → `[FAIL] 两种布局都找不到 dsh-system-prompt`

**症状**：

```
dsh web 启动失败
Cannot find module '@deepseek-ai/dsh-system-prompt'
```

## 为什么会这样

宿主安装时被打断，或者被 `--force` 重装搞坏了依赖树（历史上我们的旧脚本会干这事，现已修）。

## 修复：重装宿主

### 第 1 步：停所有进程

```powershell
# 只停 DSH 相关进程，不碰其他 node 项目
$dshProcs = Get-CimInstance Win32_Process -Filter "Name='node.exe'" -EA SilentlyContinue |
    Where-Object { $_.CommandLine -match 'dsh|deepseek' }
foreach ($p in $dshProcs) {
    Write-Host "  停止 node PID=$($p.ProcessId)" -ForegroundColor Gray
    Stop-Process -Id $p.ProcessId -Force -EA SilentlyContinue
}
# 桌面版 App
Get-Process "*DeepSeek Harness*" -EA SilentlyContinue | Stop-Process -Force -EA SilentlyContinue
Start-Sleep 2
Write-Host "已停 DSH 相关进程" -ForegroundColor Green
Write-Host "  其他 node 进程未动。如需查看：" -ForegroundColor DarkGray
Get-Process node -EA SilentlyContinue | Select-Object Id, ProcessName | Format-Table -AutoSize | Out-String | Write-Host
```

```bash
# 只停 DSH 相关进程，不碰其他 node 项目
pkill -f "dsh web" 2>/dev/null
pkill -f "dsh serve" 2>/dev/null
pkill -f "DeepSeek Harness" 2>/dev/null
sleep 2
echo "已停 DSH 相关进程"
echo "  其他 node 进程未动。当前还在跑的："
ps aux | grep "[n]ode" | awk '{printf "    PID %s  %s\n", $2, substr($0, index($0,$11), 60)}' | head -5
```

### 第 2 步：卸载宿主

```bash
npm uninstall -g @deepseek-ai/dsh
```

### 第 3 步：手动清残留（npm 卸不干净）

**Windows**
```powershell
$R = npm root -g
# 只删 dsh 包本身，保留 @deepseek-ai 下的其他包
$pkgDir = Join-Path $R "@deepseek-ai\dsh"
if (Test-Path $pkgDir) {
    Remove-Item -Recurse -Force $pkgDir
    Write-Host "  已删 @deepseek-ai\dsh" -ForegroundColor Green
}
# 只有 @deepseek-ai 变空时才删整个目录
$aiDir = Join-Path $R "@deepseek-ai"
if (Test-Path $aiDir) {
    $left = @(Get-ChildItem $aiDir -Force -EA SilentlyContinue)
    if ($left.Count -eq 0) {
        Remove-Item -Recurse -Force $aiDir
        Write-Host "  @deepseek-ai 已空，一并删除" -ForegroundColor Green
    } else {
        Write-Host "  @deepseek-ai 下还有其他包，保留：" -ForegroundColor Yellow
        $left | Select-Object -ExpandProperty Name | ForEach-Object { Write-Host "    $_" -ForegroundColor Gray }
    }
}
# dsh.cmd 在 npm 全局前缀下（不是 node_modules 里）
$prefix = (npm prefix -g).Trim()
Write-Host "  npm 全局前缀: $prefix" -ForegroundColor DarkGray
foreach ($f in @("dsh","dsh.cmd","dsh.ps1")) {
    $p = Join-Path $prefix $f
    if (Test-Path $p) { Remove-Item -Force $p; Write-Host "  已删 $f" -ForegroundColor Green }
}
```

**macOS**
```bash
NPM_ROOT="$(npm root -g)"
if [ -n "$NPM_ROOT" ] && [ -d "$NPM_ROOT" ]; then
  # 只删 dsh 包本身，保留 @deepseek-ai 下的其他包
  [ -d "$NPM_ROOT/@deepseek-ai/dsh" ] && rm -rf "$NPM_ROOT/@deepseek-ai/dsh" && echo "  已删 @deepseek-ai/dsh"
  AI="$NPM_ROOT/@deepseek-ai"
  if [ -d "$AI" ]; then
    if [ -z "$(ls -A "$AI" 2>/dev/null)" ]; then
      rmdir "$AI" && echo "  @deepseek-ai 已空，一并删除"
    else
      echo "  @deepseek-ai 下还有其他包，保留："
      ls "$AI" | sed 's/^/    /'
    fi
  fi
  NPM_PREFIX="$(npm prefix -g)"
  echo "  npm 全局前缀: $NPM_PREFIX"
  rm -f "$NPM_PREFIX/bin/dsh" "$NPM_PREFIX/bin/dsh.js"
  echo "已清理"
fi
```

### 第 4 步：清缓存

```bash
npm cache clean --force
```

### 第 5 步：重装宿主（先不跑脚本，快）

```bash
npm i -g @deepseek-ai/dsh@0.2.1-rc.2 --ignore-scripts
```

**Windows 约 10-15 分钟，macOS 约 2 分钟。**

### 第 6 步：补跑原生模块构建

```bash
npm i -g @deepseek-ai/dsh@0.2.1-rc.2 --allow-scripts=@deepseek-ai/dsh-subprocess-local,koffi,node-pty,@google/genai,protobufjs
```

**Windows 约 10-12 分钟（要编译），macOS 约 30 秒（用预编译）。**

### 第 7 步：验证

**Windows**
```powershell
$R = npm root -g
Write-Host "嵌套 dsh-system-prompt: $(Test-Path "$R\@deepseek-ai\dsh\node_modules\@deepseek-ai\dsh-system-prompt\lib\index.js")"
Write-Host "pty.node / conpty.node:"
Get-ChildItem "$R\@deepseek-ai\dsh\node_modules\node-pty\prebuilds" -Recurse -Filter "*.node" -EA SilentlyContinue |
    Select-Object -ExpandProperty Name
```

**macOS**
```bash
NPM_ROOT="$(npm root -g)"
echo "嵌套: $([ -f "$NPM_ROOT/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-system-prompt/lib/index.js" ] && echo True || echo False)"
ls "$NPM_ROOT/@deepseek-ai/dsh/node_modules/node-pty/prebuilds" 2>/dev/null
```

**必须看到**：
```
嵌套: True
pty.node   或   conpty.node
```

### 第 8 步：重装插件

```powershell
# Windows
$u = "https://raw.githubusercontent.com/evan545295555-hash/Evans-repo/7d2f3b20f51aba41b1fb3d6b5920c23c928039c8/install.ps1"
$f = "$env:TEMP\dsh-install.ps1"
Invoke-WebRequest -Uri $u -OutFile $f -UseBasicParsing
if ((Get-Item $f).Length -lt 5000) { throw "文件长度异常，请重试" }
& $f
```

```bash
# macOS
u="https://raw.githubusercontent.com/evan545295555-hash/Evans-repo/7d2f3b20f51aba41b1fb3d6b5920c23c928039c8/install.sh"
f="$(mktemp /tmp/dsh-install-XXXXXX.sh)"
trap 'rm -f "$f"' EXIT
curl -fsSL --retry 3 -o "$f" "$u" || { echo "下载失败"; exit 1; }
[ "$(wc -c <"$f")" -ge 5000 ] || { echo "文件长度异常"; exit 1; }
bash -n "$f" || { echo "脚本语法错误，可能下载不完整"; exit 1; }
bash "$f"
```

---

# 情况 4：bundles 缺 base / web-app

**诊断显示**：`6. profile 配置` → `[FAIL] 缺 base` 或 `[FAIL] 缺 web-app`

**症状**：`preset-declare.json` 里 `phase: waiting-registry`，红队模式出不来。

## 为什么会这样

- 装过别的插件，把 `bundles` 改了
- 手动编辑 `package.json` 删错了
- 早期版本安装脚本没补全

## 修复：重跑安装脚本（新版会自动补）

```powershell
# Windows
$u = "https://raw.githubusercontent.com/evan545295555-hash/Evans-repo/7d2f3b20f51aba41b1fb3d6b5920c23c928039c8/install.ps1"
$f = "$env:TEMP\dsh-install.ps1"
Invoke-WebRequest -Uri $u -OutFile $f -UseBasicParsing
if ((Get-Item $f).Length -lt 5000) { throw "文件长度异常，请重试" }
& $f
```

```bash
# macOS
u="https://raw.githubusercontent.com/evan545295555-hash/Evans-repo/7d2f3b20f51aba41b1fb3d6b5920c23c928039c8/install.sh"
f="$(mktemp /tmp/dsh-install-XXXXXX.sh)"
trap 'rm -f "$f"' EXIT
curl -fsSL --retry 3 -o "$f" "$u" || { echo "下载失败"; exit 1; }
[ "$(wc -c <"$f")" -ge 5000 ] || { echo "文件长度异常"; exit 1; }
bash -n "$f" || { echo "脚本语法错误，可能下载不完整"; exit 1; }
bash "$f"
```

**新版会输出**：
```
OK 已补齐缺失的 base / web-app
```

## 手动修（如果脚本不管用）

**Windows**
```powershell
$js = @'
const fs=require('fs'),os=require('os'),path=require('path');
const p=path.join(os.homedir(),'.dsh','profiles','web','package.json');
const d=JSON.parse(fs.readFileSync(p,'utf8'));
d.dsh=d.dsh||{}; d.dsh.profile=d.dsh.profile||{};
let b=Array.isArray(d.dsh.profile.bundles)?d.dsh.profile.bundles.slice():[];
for (const need of ['@deepseek-ai/dsh-base','@deepseek-ai/dsh-web-app']) {
  if (!b.includes(need)) b.unshift(need);
}
d.dsh.profile.bundles=b;
fs.writeFileSync(p, JSON.stringify(d,null,2));
console.log('bundles:', b.join(','));
'@
$t="$env:TEMP\fix-bundles.cjs"; $js|Set-Content $t -Encoding utf8; node $t
```

**macOS**
```bash
node -e "
const fs=require('fs'),os=require('os'),path=require('path');
const p=path.join(os.homedir(),'.dsh','profiles','web','package.json');
const d=JSON.parse(fs.readFileSync(p,'utf8'));
d.dsh=d.dsh||{}; d.dsh.profile=d.dsh.profile||{};
let b=Array.isArray(d.dsh.profile.bundles)?d.dsh.profile.bundles.slice():[];
for (const need of ['@deepseek-ai/dsh-base','@deepseek-ai/dsh-web-app']) {
  if (!b.includes(need)) b.unshift(need);
}
d.dsh.profile.bundles=b;
fs.writeFileSync(p, JSON.stringify(d,null,2));
console.log('bundles:', b.join(','));
"
```

## 验证

```bash
node -p "require(require('os').homedir()+'/.dsh/profiles/web/package.json').dsh.profile.bundles.join(',')"
```

**必须包含 `@deepseek-ai/dsh-base,@deepseek-ai/dsh-web-app`**

## 然后重启宿主

```bash
$env:REDTEAM_PRESET_REFRESH = "1"     # Windows
export REDTEAM_PRESET_REFRESH=1        # macOS
dsh web
```

---

# 情况 5：phase registered-broken

**诊断显示**：`7. phase: registered-broken`，`broken` 有内容

**症状**：红队模式里某些能力缺失，或模式下拉里红队模式显示异常。

## 先看 broken 说什么

```powershell
# Windows
type $env:USERPROFILE\.dsh\redteam\preset-declare.json
```

```bash
# macOS
cat ~/.dsh/redteam/preset-declare.json
```

**`broken` 字段会写明哪个组件没起来**，例如：

```json
"broken": "persona (dsh-purge/redteam/persona): never started"
```

## 常见原因

| broken 内容 | 原因 | 修复 |
|---|---|---|
| `persona (dsh-purge/redteam/persona): never started` | preset 文件是旧版残留，引用了不存在的组件 | 清 preset 重生成（见下） |
| `tool-subagent-list-agents ...: never started` | preset 引用宿主没有的包 | 清 preset 重生成 |
| 其他组件名 | 组件崩了 | 清 preset + 重启，还不行就看修复指南底部 |

## 修复：清 preset 状态让它重新注册

### 第 1 步：停宿主

```powershell
# 只停 DSH 相关进程，不碰其他 node 项目
$dshProcs = Get-CimInstance Win32_Process -Filter "Name='node.exe'" -EA SilentlyContinue |
    Where-Object { $_.CommandLine -match 'dsh|deepseek' }
foreach ($p in $dshProcs) {
    Write-Host "  停止 node PID=$($p.ProcessId)" -ForegroundColor Gray
    Stop-Process -Id $p.ProcessId -Force -EA SilentlyContinue
}
# 桌面版 App
Get-Process "*DeepSeek Harness*" -EA SilentlyContinue | Stop-Process -Force -EA SilentlyContinue
Start-Sleep 2
Write-Host "已停 DSH 相关进程" -ForegroundColor Green
Write-Host "  其他 node 进程未动。如需查看：" -ForegroundColor DarkGray
Get-Process node -EA SilentlyContinue | Select-Object Id, ProcessName | Format-Table -AutoSize | Out-String | Write-Host
```

```bash
# macOS
pkill -f "dsh web" 2>/dev/null; pkill -f "dsh serve" 2>/dev/null; pkill -f "DeepSeek Harness" 2>/dev/null; sleep 2
```

### 第 2 步：删预设与状态

**Windows**
```powershell
$U = "$env:USERPROFILE\.dsh"
Remove-Item -Recurse -Force "$U\.agent-presets\redteam" -EA SilentlyContinue
Remove-Item -Force "$U\redteam\preset-declare.json" -EA SilentlyContinue
Write-Host "已清预设与状态" -ForegroundColor Green
```

**macOS**
```bash
rm -rf ~/.dsh/.agent-presets/redteam
rm -f ~/.dsh/redteam/preset-declare.json
echo "已清预设与状态"
```

### 第 3 步：带刷新变量重启

```powershell
# Windows
$env:REDTEAM_PRESET_REFRESH = "1"
dsh web
```

```bash
# macOS
export REDTEAM_PRESET_REFRESH=1
dsh web
```

### 第 4 步：点「应用」一次

**新预设需要点一次「应用」才会重新注册。**

```
dsh-purge → 清洗 → 应用
```

### 第 5 步：验证

```bash
cat ~/.dsh/redteam/preset-declare.json
```

**期望**：`phase: registered` + `broken: null`

---

# 情况 6：有多套残留

**诊断显示**：`8. 残留检查` 有输出，或 `4. dsh 命令` 报「有多个 dsh」

**症状**：
- `where dsh` / `which -a dsh` 出多个路径
- 版本混乱
- 装完不知道哪套在跑

## 第 1 步：看有几个

**Windows**
```powershell
where.exe dsh
Get-Command dsh -All -EA SilentlyContinue | Select-Object Source
```

**macOS**
```bash
which -a dsh
```

**如果只有一个** → 没有这问题，跳到情况 1-5。

**如果有多个** → 继续。

## 第 2 步：确认哪个是真的

**Windows**
```powershell
$R = npm root -g
Write-Host "npm 全局根: $R"
npm ls -g @deepseek-ai/dsh --depth=0
```

**macOS**
```bash
npm root -g
npm ls -g @deepseek-ai/dsh --depth=0
```

**正常情况**：`dsh` 路径应该在 `npm root -g` 的**兄弟目录** `bin/` 下。

**Windows 正常**：
```
dsh.cmd 位置: C:\Users\xxx\AppData\Roaming\npm\dsh.cmd
npm 全局根:   C:\Users\xxx\AppData\Roaming\npm\node_modules
```

**macOS 正常**：
```
dsh 位置:     /opt/homebrew/bin/dsh
npm 全局根:   /opt/homebrew/lib/node_modules
```

**如果 dsh 在别的盘/别的目录**（比如 `D:\deepseek\...`、`E:\deepseek\...`）→ 那是另一套，要清掉。

## 第 3 步：清掉多余的那套

**先确认那套是什么**

**Windows**
```powershell
# 举例：清 D 盘那套
if (Test-Path "D:\deepseek") {
    Get-ChildItem "D:\deepseek" | Select-Object Name, Length
}
```

**看清内容再删**，别删错。

**删除**

**Windows**
```powershell
if (Test-Path "D:\deepseek") { Remove-Item -Recurse -Force "D:\deepseek"; "已删 D:\deepseek" }
```

**macOS**
```bash
[ -d "/some/other/deepseek" ] && rm -rf "/some/other/deepseek"
```

## 第 4 步：清 PATH 里的死条目

**Windows**
```powershell
foreach ($scope in @("User", "Machine")) {
    $old = [Environment]::GetEnvironmentVariable("PATH", $scope)
    if ($old) {
        $new = ($old -split ';' | Where-Object { $_ -notlike "D:\deepseek*" -and $_ -ne "" }) -join ';'
        if ($old -ne $new) {
            try {
                [Environment]::SetEnvironmentVariable("PATH", $new, $scope)
                Write-Host "已从 $scope PATH 移除" -ForegroundColor Green
            } catch {
                Write-Host "$scope 需要管理员权限" -ForegroundColor Yellow
            }
        }
    }
}
```

**macOS**：检查 `~/.zshrc` / `~/.zprofile` / `~/.bash_profile` 里有没有 `export PATH=` 指向旧目录，手动删掉那行。

## 第 5 步：关窗口重开，验证

```powershell
# Windows
where.exe dsh
```

```bash
# macOS
which -a dsh
```

**应该只剩一个**（在 `npm root -g` 的兄弟 bin 下）。

---

# 情况 7：彻底重来

**诊断一片红，或者上面所有方法都试过还是不行。**

**这一步会删文件，所以全部做成了脚本。** 备份 → 停进程 → 预检 → 清理，一条命令走完，任何一步失败都会停下，不会删错东西。

---

## 第 1 步：运行清理脚本

### 它做什么

```
0. 列出 DSH 进程（只列，不杀）
1. 备份（sessions / skills / redteam / prompt-inject.md / package.json / cordis.patch.yml）
   ← 任一失败就退出，不进入清理
2. 提示你手动停 DSH 进程（脚本不杀，给你 kill 命令自己执行）
   ← 停完后按回车，脚本会重新检查，进程还在就拒绝继续
3. 检查备份标记（没有就拒绝清理）
3.5 预检 YAML 结构、package.json 可解析性
   ← 结构异常就报错，不删任何东西
4-7. 删插件目录、清 YAML、清 package.json、清预设
8. 验证结果
```

### Windows

**`clean-all.sh` 是 bash 脚本，Windows 需要先确认有 bash 环境。**

**先检查**：

```powershell
bash --version
```

| 结果 | 说明 |
|---|---|
| 出版本号（如 `GNU bash, version 5.x`） | ✅ 可以用下面的命令 |
| 报「无法识别」 | 需要装 Git for Windows（自带 Git Bash），或按文末「无 bash 的 Windows 分步版」 |

**有 bash 的话**：

```powershell
$SHA = "ba9d1ad5d28a9f4a55d658c390f5697537ddeeba"
$BASE = "https://raw.githubusercontent.com/evan545295555-hash/Evans-repo/$SHA/scripts"
$D = Join-Path $env:TEMP ("dsh-clean-" + [guid]::NewGuid().ToString())
New-Item -ItemType Directory -Path "$D\scripts" -Force | Out-Null

$files = @("clean-all.sh", "clean-cordis-patch.cjs", "clean-profile-deps.cjs", "list-dsh-procs.sh")
foreach ($f in $files) {
    $dst = Join-Path "$D\scripts" $f
    Invoke-WebRequest -Uri "$BASE/$f" -OutFile $dst -UseBasicParsing
    if ((Get-Item $dst).Length -lt 500) { throw "下载 $f 长度异常" }
    Write-Host "  OK  $f"
}

bash "$D/scripts/clean-all.sh"
```

**先预演**：

```powershell
bash "$D/scripts/clean-all.sh" --dry-run
```

**没有 bash**：跳到文末[「情况 7 补充：Windows 无 bash 分步版」](#情况-7-补充windows-无-bash-分步版)。

### macOS / Linux

```bash
SHA="ba9d1ad5d28a9f4a55d658c390f5697537ddeeba"
BASE="https://raw.githubusercontent.com/evan545295555-hash/Evans-repo/$SHA/scripts"
D="$(mktemp -d)"
mkdir -p "$D/scripts"

for f in clean-all.sh clean-cordis-patch.cjs clean-profile-deps.cjs list-dsh-procs.sh; do
  curl -fsSL --retry 3 -o "$D/scripts/$f" "$BASE/$f" || { echo "下载 $f 失败"; exit 1; }
  [ "$(wc -c <"$D/scripts/$f")" -ge 500 ] || { echo "$f 长度异常"; exit 1; }
  bash -n "$D/scripts/$f" 2>/dev/null || { echo "$f 语法错误"; exit 1; }
done

chmod +x "$D/scripts/clean-all.sh" "$D/scripts/list-dsh-procs.sh"
bash "$D/scripts/clean-all.sh"
```

**先预演一遍看会做什么**：

```bash
bash "$D/scripts/clean-all.sh" --dry-run
```

---

## 第 2 步：清宿主（脚本不管这一步）

```bash
npm uninstall -g @deepseek-ai/dsh
```

**Windows**
```powershell
$R = npm root -g
if (Test-Path "$R\@deepseek-ai") { Remove-Item -Recurse -Force "$R\@deepseek-ai" }
foreach ($f in @("dsh","dsh.cmd","dsh.ps1")) {
    $p = Join-Path $R $f
    if (Test-Path $p) { Remove-Item -Force $p }
}
npm cache clean --force
Write-Host "宿主已清" -ForegroundColor Green
```

**macOS**
```bash
NPM_ROOT="$(npm root -g)"
if [ -n "$NPM_ROOT" ] && [ -d "$NPM_ROOT" ]; then
  # 只删 dsh 包本身，保留 @deepseek-ai 下的其他包
  [ -d "$NPM_ROOT/@deepseek-ai/dsh" ] && rm -rf "$NPM_ROOT/@deepseek-ai/dsh" && echo "  已删 @deepseek-ai/dsh"
  AI="$NPM_ROOT/@deepseek-ai"
  if [ -d "$AI" ]; then
    if [ -z "$(ls -A "$AI" 2>/dev/null)" ]; then
      rmdir "$AI" && echo "  @deepseek-ai 已空，一并删除"
    else
      echo "  @deepseek-ai 下还有其他包，保留："
      ls "$AI" | sed 's/^/    /'
    fi
  fi
  rm -f "$(npm prefix -g)/bin/dsh"
fi
npm cache clean --force
echo "宿主已清"
```

---

## 第 3 步：跑诊断确认干净

```powershell
# Windows
$u = "https://raw.githubusercontent.com/evan545295555-hash/Evans-repo/7d2f3b20f51aba41b1fb3d6b5920c23c928039c8/diagnose.ps1"
$f = "$env:TEMP\dsh-diagnose.ps1"
Invoke-WebRequest -Uri $u -OutFile $f -UseBasicParsing
if ((Get-Item $f).Length -lt 500) { throw "下载不完整，请重试" }
& $f
```

```bash
# macOS
u="https://raw.githubusercontent.com/evan545295555-hash/Evans-repo/7d2f3b20f51aba41b1fb3d6b5920c23c928039c8/diagnose.sh"
f="$(mktemp /tmp/dsh-diagnose-XXXXXX.sh)"
trap 'rm -f "$f"' EXIT
curl -fsSL --retry 3 -o "$f" "$u" || { echo "下载失败"; exit 1; }
[ "$(wc -c <"$f")" -ge 3000 ] || { echo "文件长度异常"; exit 1; }
bash "$f"
```

**期望**：

```
2. 宿主: [FAIL] 未安装
5. 插件: 未安装
6. profile: bundles 只剩 base,web-app 或不存在
7. 红队模式: 未生成
8. 残留检查: 无输出
```

## 第 4 步：按全新安装来

看 [安装指南](https://github.com/evan545295555-hash/Evans-repo/blob/master/docs/dsh-purge-%E5%AE%89%E8%A3%85%E6%8C%87%E5%8D%97.md) 从第 1 步开始。

---

# 特殊：原生模块没编译

**症状**：

```
dsh web 启动失败
Error: Cannot find module '.../node-pty/...'
或
koffi: failed to load
```

**诊断显示**：`3. 宿主依赖布局` 通过了，但 `dsh web` 起不来。

## 为什么会这样

`node-pty` 和 `koffi` 是原生模块（C++ 编译的 `.node` 文件）。npm 11 默认**不执行**包的 install 脚本（防恶意包），所以它们没被编译。

## 修复

```bash
npm i -g @deepseek-ai/dsh@0.2.1-rc.2 --allow-scripts=@deepseek-ai/dsh-subprocess-local,koffi,node-pty,@google/genai,protobufjs
```

**耗时**：
- macOS：约 30 秒（用预编译）
- Windows：约 10-12 分钟（要真编译）

## 验证

**Windows**
```powershell
$R = npm root -g
Get-ChildItem "$R\@deepseek-ai\dsh\node_modules\node-pty\prebuilds" -Recurse -Filter "*.node" -EA SilentlyContinue |
    Select-Object -ExpandProperty Name
```

**期望看到 `conpty.node`**（Windows 上叫这个）

**macOS**
```bash
NPM_ROOT="$(npm root -g)"
ls "$NPM_ROOT/@deepseek-ai/dsh/node_modules/node-pty/prebuilds" 2>/dev/null
```

**期望看到 `darwin-arm64` 或 `darwin-x64` 目录，里面有 `pty.node`**

## 然后重试启动

```bash
dsh web
```

---

# 特殊：端口被占用

**症状**：

```
Error: listen EADDRINUSE: address already in use 127.0.0.1:3080
dsh: startup failed: 2 required plugins did not activate
```

## 原因

有个旧的 `dsh web` 还在后台跑。

## 修复 1：杀掉占用进程

**Windows**
```powershell
Get-NetTCPConnection -LocalPort 3080 -EA SilentlyContinue | ForEach-Object {
    Stop-Process -Id $_.OwningProcess -Force -EA SilentlyContinue
}
Start-Sleep 2
Write-Host "已清理 3080"
```

**macOS**
```bash
lsof -ti:3080 | xargs kill -9 2>/dev/null
echo "已清理 3080"
```

**然后重试**

```bash
dsh web
```

## 修复 2：换个端口

```bash
dsh web --port 3081
```

**浏览器打开 `http://127.0.0.1:3081/?token=...`**（终端会打印完整 URL）

---

# 特殊：点应用后白屏 / 页面加载失败

## 第 1 步：检查是不是应用时崩了

**Windows**
```powershell
Get-ChildItem "$env:USERPROFILE\.dsh\logs" -Filter "startup-*.log" -EA SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1 | ForEach-Object {
        Write-Host "=== $($_.Name) ===" -ForegroundColor Cyan
        Get-Content $_.FullName -Tail 30
    }
```

**macOS**
```bash
ls -t ~/.dsh/logs/startup-*.log 2>/dev/null | head -1 | xargs tail -30
```

## 第 2 步：看日志里有没有 `failed` / `did not activate`

**有** → 把那段发出来。

**没有** → 可能是浏览器缓存，`Ctrl+Shift+R` 强制刷新。

## 第 3 步：还原宿主补丁

**分两种情况**：

### 界面还能打开

```
dsh-purge → 状态 → 还原
```

### 界面打不开

**不能靠点按钮，用命令行还原**：

**Windows**
```powershell
# 重装宿主 = 源码恢复原始，补丁自然消失
npm i -g @deepseek-ai/dsh@0.2.1-rc.2 --ignore-scripts
npm i -g @deepseek-ai/dsh@0.2.1-rc.2 --allow-scripts=@deepseek-ai/dsh-subprocess-local,koffi,node-pty,@google/genai,protobufjs
```

**macOS**
```bash
npm i -g @deepseek-ai/dsh@0.2.1-rc.2 --ignore-scripts
npm i -g @deepseek-ai/dsh@0.2.1-rc.2 --allow-scripts=@deepseek-ai/dsh-subprocess-local,koffi,node-pty,@google/genai,protobufjs
```

**或者按情况 3 的完整重装流程走。**

### 验证补丁已还原

```bash
node -e '
const { execSync } = require("child_process");
const fs = require("fs"), path = require("path");
const root = execSync("npm root -g", { encoding: "utf8" }).trim();
const cands = [
  path.join(root, "@deepseek-ai", "dsh-system-prompt", "lib", "index.js"),
  path.join(root, "@deepseek-ai", "dsh", "node_modules", "@deepseek-ai", "dsh-system-prompt", "lib", "index.js"),
];
const found = cands.find(c => fs.existsSync(c));
if (!found) { console.log("找不到宿主文件"); process.exit(1); }
const n = (fs.readFileSync(found, "utf8").match(/\[dsh-purge\]/g) || []).length;
console.log("[dsh-purge] 标记:", n, "处");
console.log(n === 0 ? "✅ 补丁已还原" : "⚠️ 仍有 " + n + " 处标记");
'
```

---

# 网络问题：下载失败

## 症状

```
ERR 下载失败：...
或
irm : 基础连接已经关闭
```

## 修复：用镜像

**Windows**
```powershell
$u = "https://ghfast.top/https://raw.githubusercontent.com/evan545295555-hash/Evans-repo/7d2f3b20f51aba41b1fb3d6b5920c23c928039c8/install.ps1"
$f = "$env:TEMP\dsh-install.ps1"
Invoke-WebRequest -Uri $u -OutFile $f -UseBasicParsing
if ((Get-Item $f).Length -lt 5000) { throw "文件长度异常，请重试" }
& $f
```

**macOS**
```bash
u="https://ghfast.top/https://raw.githubusercontent.com/evan545295555-hash/Evans-repo/7d2f3b20f51aba41b1fb3d6b5920c23c928039c8/install.sh"
f="$(mktemp /tmp/dsh-install-XXXXXX.sh)"
trap 'rm -f "$f"' EXIT
curl -fsSL --retry 3 -o "$f" "$u" || { echo "下载失败"; exit 1; }
[ "$(wc -c <"$f")" -ge 5000 ] || { echo "文件长度异常"; exit 1; }
bash -n "$f" || { echo "脚本语法错误，可能下载不完整"; exit 1; }
bash "$f"
```

## 说明

上面的命令已经是「先下载再执行」，不需要另找写法。如果镜像也不通：

1. 用手机热点或换网络重试
2. 稍后再试（GitHub 偶发不可达）
3. 把原始报错贴出来，不要跳过校验直接执行

---

# 修复后的完整验证清单

## 重要：区分「插件加载」和「应用生效」

| 你看到的 | 证明什么 | 不能证明什么 |
|---|---|---|
| `preset-declare.json` 的 `phase: registered` | 宿主启动时插件加载成功 | **是否点过「应用」** |
| `preset-declare.json` 的 `at` 是刚刚 | 是本次启动写的 | **应用有没有写入宿主** |
| **宿主源码里有 `[dsh-purge]` 标记** | **应用已生效** | —— |

**`at` 在每次宿主启动时都会刷新**（组件加载即写入 `apply-start`，注册完成写 `registered`），所以「文件很新」不等于「应用成功」。

查宿主标记（这是唯一直接证据）：

```bash
node -e '
const { execSync } = require("child_process");
const fs = require("fs"), path = require("path");
const root = execSync("npm root -g", { encoding: "utf8" }).trim();
const cands = [
  path.join(root, "@deepseek-ai", "dsh-system-prompt", "lib", "index.js"),
  path.join(root, "@deepseek-ai", "dsh", "node_modules", "@deepseek-ai", "dsh-system-prompt", "lib", "index.js"),
  path.join(root, "dsh-system-prompt", "lib", "index.js"),
  path.join(root, "node_modules", "@deepseek-ai", "dsh-system-prompt", "lib", "index.js"),
];
const found = cands.find(c => fs.existsSync(c));
if (!found) { console.log("❌ 找不到 dsh-system-prompt"); process.exit(1); }
const n = (fs.readFileSync(found, "utf8").match(/\[dsh-purge\]/g) || []).length;
console.log("宿主文件:", found);
console.log("[dsh-purge] 标记:", n, "处");
if (n === 0) { console.log("❌ 应用没生效"); process.exit(1); }
console.log("✅ 应用已写入宿主");
'
```

## 然后跑诊断

修完任何一项后，跑诊断确认：

```powershell
# Windows
$u = "https://raw.githubusercontent.com/evan545295555-hash/Evans-repo/7d2f3b20f51aba41b1fb3d6b5920c23c928039c8/diagnose.ps1"
$f = "$env:TEMP\dsh-diagnose.ps1"
Invoke-WebRequest -Uri $u -OutFile $f -UseBasicParsing
if ((Get-Item $f).Length -lt 500) { throw "下载不完整，请重试" }
& $f
```

```bash
# macOS
u="https://raw.githubusercontent.com/evan545295555-hash/Evans-repo/7d2f3b20f51aba41b1fb3d6b5920c23c928039c8/diagnose.sh"
f="$(mktemp /tmp/dsh-diagnose-XXXXXX.sh)"
trap 'rm -f "$f"' EXIT
curl -fsSL --retry 3 -o "$f" "$u" || { echo "下载失败"; exit 1; }
[ "$(wc -c <"$f")" -ge 3000 ] || { echo "文件长度异常"; exit 1; }
bash "$f"
```

**必须全部 `[OK]`**：

```
1. Node.js           [OK] 符合要求（需要 20+）
2. 宿主              [OK] 已装 + 版本兼容
3. 布局              [OK] 摊平 或 嵌套
4. dsh 命令          [OK] 来自当前 Node 安装
5. 插件              [OK] 已装 + 版本正确
6. profile           [OK] dsh-purge 已登记 + base/web-app 都在
7. 红队模式          [OK] 注册成功
8. 残留检查          （无输出）
```

## 然后启动 + 点应用，按安装指南的三件证据验收

**不要只看 `preset-declare.json`** —— 它在启动时就会写，和点应用无关。

| 证据 | 命令 | 通过标准 |
|---|---|---|
| 1. 版本 | 见安装指南第 7 步第 1 小节 | `1.1.71-rc2.1` |
| 2. 本次启动加载了插件 | 见安装指南第 7 步第 2 小节 | `at` 距现在 < 10 分钟 + `registered` + `broken: null` |
| 3. 应用写进了宿主 | 见安装指南第 7 步第 3 小节 | 全新环境标记从 `0` 变 `> 0` |

**完整步骤和命令在 [安装指南第 7 步](https://github.com/evan545295555-hash/Evans-repo/blob/master/docs/dsh-purge-%E5%AE%89%E8%A3%85%E6%8C%87%E5%8D%97.md)，这里不重复。**

**特别提醒**：

- 已有标记的环境（重装/重复应用）**无法用标记变化证明本次成功**，只能确认宿主处于应用状态，本次结果看界面提示
- 补丁是幂等的，已含标记时跳过写入，所以标记数和 mtime 都不变

---

# 一页速查

| 诊断看到 | 跳到 |
|---|---|
| 插件未安装 | 情况 1 |
| 插件 1.1.71（非 rc2.1） | 情况 2 |
| 布局两种都找不到 | 情况 3 |
| bundles 缺 base/web-app | 情况 4 |
| phase registered-broken | 情况 5 |
| 多个 dsh 路径 | 情况 6 |
| 一片红 | 情况 7 |
| `Cannot find module ...node-pty` | 特殊：原生模块 |
| `EADDRINUSE` | 特殊：端口占用 |
| 下载失败 | 网络问题 |

---

**任何情况都修不好，把 diagnose 的完整输出 + install 脚本最后 20 行发出来。**

---

# 情况 7 补充：Windows 无 bash 分步版

**没有 Git Bash / WSL 时用这套。每一步都要看输出，失败就停。**

## S1. 备份（失败必须停）

```powershell
$DSH = if ($env:DSH_HOME) { $env:DSH_HOME } else { Join-Path $env:USERPROFILE ".dsh" }
if (-not (Test-Path $DSH)) { throw "找不到数据目录: $DSH" }
Write-Host "数据目录: $DSH"

$bk = Join-Path $env:USERPROFILE ("dsh-backup-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
New-Item -ItemType Directory -Path $bk -Force | Out-Null

$required = @("sessions","skills","redteam","prompt-inject.md",
              "profiles\web\package.json","profiles\web\cordis.patch.yml")
$failed = @()
foreach ($item in $required) {
    $src = Join-Path $DSH $item
    if (-not (Test-Path $src)) { Write-Host "  跳过（不存在）: $item" -ForegroundColor DarkGray; continue }
    try {
        $dst = Join-Path $bk $item
        $dd = Split-Path $dst -Parent
        if (-not (Test-Path $dd)) { New-Item -ItemType Directory -Path $dd -Force | Out-Null }
        Copy-Item -Recurse -Force $src $dst -ErrorAction Stop
        Write-Host "  OK  $item" -ForegroundColor Green
    } catch {
        $failed += $item
        Write-Host "  FAIL $item : $($_.Exception.Message)" -ForegroundColor Red
    }
}

if ($failed.Count -gt 0) {
    Write-Host ""
    Write-Host "备份失败: $($failed -join ', ')" -ForegroundColor Red
    Write-Host "已停止，未做任何清理。" -ForegroundColor Yellow
    return
}
New-Item -ItemType File -Path (Join-Path $bk ".backup-complete") -Force | Out-Null
Write-Host ""
Write-Host "备份完成: $bk" -ForegroundColor Cyan
```

## S2. 手动停 DSH

```powershell
# 只列出，不杀
gh --version >$null 2>&1
$procs = Get-CimInstance Win32_Process -Filter "Name='node.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -match '@deepseek-ai[\\/]dsh[\\/]lib[\\/]bin\.js' -or $_.CommandLine -match 'dsh\.cmd\s+(web|serve)' }
$procs | ForEach-Object { Write-Host "  DSH PID=$($_.ProcessId)  $($_.CommandLine)" }
Get-Process "*DeepSeek Harness*" -ErrorAction SilentlyContinue | ForEach-Object {
    Write-Host "  App PID=$($_.Id)  $($_.ProcessName)"
}
Write-Host ""
Write-Host "请手动退出桌面版 App，或在跑 dsh web 的终端按 Ctrl+C"
Write-Host "确认停完后按回车继续"
Read-Host
```

## S3. 检查备份标记

```powershell
$latest = Get-ChildItem $env:USERPROFILE -Filter "dsh-backup-*" -Directory -EA SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $latest -or -not (Test-Path (Join-Path $latest.FullName ".backup-complete"))) {
    throw "找不到完整备份标记，拒绝清理"
}
Write-Host "备份已验证: $($latest.FullName)" -ForegroundColor Green
```

## S4. 清插件目录

```powershell
$W = Join-Path $DSH "profiles\web\node_modules"
foreach ($p in @("dsh-purge","dsh-purge-community","dsh-purge-panel")) {
    $d = Join-Path $W $p
    if (Test-Path $d) { Remove-Item -Recurse -Force $d; Write-Host "  已删 $p" -ForegroundColor Green }
}
```

## S5. 清 cordis.patch.yml

**注意**：Windows 上如果没有 node，这一步跳过，手动编辑文件。

```powershell
$f = Join-Path $DSH "profiles\web\cordis.patch.yml"
if (Test-Path $f) {
    $js = @'
const fs=require("fs");
const p=process.argv[2];
const IDS=new Set(["dsh-purge","dsh-purge-community","dsh-purge-panel"]);
const lines=fs.readFileSync(p,"utf8").split(/\r?\n/);
const out=[];let i=0,removed=0;
while(i<lines.length){
  const m=lines[i].match(/^(\s*)- id:\s*(\S+)\s*$/);
  if(m&&IDS.has(m[2])){const ind=m[1].length;removed++;i++;
    while(i<lines.length){const l=lines[i];if(l.trim()===""){i++;continue;}
      if(l.match(/^(\s*)/)[1].length>ind){i++;continue;}break;}continue;}
  out.push(lines[i]);i++;
}
if(removed===0){console.log("没有 dsh-purge 条目");process.exit(0);}
fs.copyFileSync(p,p+".bak-"+Date.now());
fs.writeFileSync(p,out.join("\n")+"\n");
console.log("已移除 "+removed+" 个条目");
'@
    $tmp = Join-Path $env:TEMP "clean-patch.cjs"
    $js | Set-Content -Path $tmp -Encoding utf8
    node $tmp $f
}
```

## S6. 清 package.json

```powershell
$f = Join-Path $DSH "profiles\web\package.json"
if (Test-Path $f) {
    $js = @'
const fs=require("fs");
const p=process.argv[2];
const NAMES=new Set(["dsh-purge","dsh-purge-community","dsh-purge-panel"]);
const d=JSON.parse(fs.readFileSync(p,"utf8"));
let changed=false;
if(d.dsh&&d.dsh.profile&&Array.isArray(d.dsh.profile.bundles)){
  const b=d.dsh.profile.bundles.filter(x=>!NAMES.has(x));
  if(b.length!==d.dsh.profile.bundles.length){d.dsh.profile.bundles=b;changed=true;}
}
for(const k of Object.keys(d.dependencies||{})){if(NAMES.has(k)){delete d.dependencies[k];changed=true;}}
if(!changed){console.log("没有 dsh-purge 条目");process.exit(0);}
fs.copyFileSync(p,p+".bak-"+Date.now());
fs.writeFileSync(p,JSON.stringify(d,null,2)+"\n");
console.log("bundles:",(d.dsh&&d.dsh.profile&&d.dsh.profile.bundles||[]).join(",")||"空");
'@
    $tmp = Join-Path $env:TEMP "clean-deps.cjs"
    $js | Set-Content -Path $tmp -Encoding utf8
    node $tmp $f
}
```

## S7. 清预设

```powershell
Remove-Item -Recurse -Force (Join-Path $DSH ".agent-presets\redteam") -EA SilentlyContinue
Remove-Item -Force (Join-Path $DSH "redteam\preset-declare.json") -EA SilentlyContinue
Write-Host "已清预设" -ForegroundColor Green
```

