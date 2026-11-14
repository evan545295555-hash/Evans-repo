# dsh-purge 1.1.71-rc2.1 一键安装（Windows PowerShell）
# 用法：irm <raw 地址> | iex
$ErrorActionPreference = "Stop"

$PluginVersion = "1.1.71-rc2.1"
$HostVersion   = "0.2.1-rc.2"
$PkgUrl = "https://github.com/evan545295555-hash/Evans-repo/releases/download/v$PluginVersion/dsh-purge-$PluginVersion.tgz"
$DshHomeDir = if ($env:DSH_HOME) { $env:DSH_HOME } else { Join-Path $env:USERPROFILE ".dsh" }

function Say($m)  { Write-Host "==> $m" -ForegroundColor Cyan }
function Ok($m)   { Write-Host "OK  $m" -ForegroundColor Green }
function Warn($m) { Write-Host "!!  $m" -ForegroundColor Yellow }
function Die($m)  { Write-Host "ERR $m" -ForegroundColor Red; exit 1 }

Say "dsh-purge $PluginVersion 安装器（Windows）"

# ── 1) Node ────────────────────────────────────────────────
if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
  Die "没检测到 Node.js。先装它：https://nodejs.org （选 LTS，双击安装）"
}

# 不用 [int] 强转：Windows 上 node -p 可能带警告或空行，
# 强转失败会抛异常，而 $ErrorActionPreference=Stop 会让脚本静默退出。
$nodeVerRaw = ""
try { $nodeVerRaw = ("$(node -v 2>&1)").Trim() } catch { }
if ($nodeVerRaw -notmatch 'v?(\d+)\.') {
  Die "无法识别 Node 版本。原始输出：[$nodeVerRaw]  请手动确认 node -v 能正常输出版本号"
}
$major = [int]$Matches[1]
if ($major -lt 20) {
  Die "Node 版本太低（$nodeVerRaw）。宿主依赖 powershell-utils / is-in-ssh 要求 Node 20+。`n    升级： winget install OpenJS.NodeJS.LTS`n    装完关掉 PowerShell 重开，node -v 确认 v20 以上。"
}
Ok "Node $nodeVerRaw"

# ── 1.5) npm 策略（仅提示）─────────────────────────────────
# install-strategy=hoisted 只对本地项目生效，全局安装永远嵌套。
# 这里不再强制修改，避免让用户误以为改了就有用。
$strategy = ""
try { $strategy = ("$(npm config get install-strategy 2>$null)").Trim() } catch { }
if ($strategy -eq "hoisted") {
  Ok "npm 策略 hoisted"
} else {
  Write-Host "  提示: npm install-strategy=$strategy（对全局安装无影响，可忽略）" -ForegroundColor DarkGray
}

# ── 2) 宿主 ────────────────────────────────────────────────
# 用 npm ls 读全局版本，不依赖 dsh --version。
# Windows 上 dsh --version 常无输出，会导致误判"版本不对"而重装 830MB。
$needHost = $true
$installedHost = ""
try {
  $lsOut = (npm ls -g @deepseek-ai/dsh --depth=0 2>&1 | Out-String)
  if ($lsOut -match '@deepseek-ai/dsh@([\w.\-]+)') { $installedHost = $Matches[1] }
} catch { }

  if ($installedHost) {
    # 实测 0.2.0-rc.2 与 0.2.1-rc.2 都能完整应用（applied 67 / 56，failed 0）
    # 任意 0.2.x 保留，不强制降级，避免白下 830MB
    Ok "已装宿主 $installedHost（兼容）"
    if ($installedHost -notlike "0.2.*") {
      Warn "宿主是 $installedHost，本插件面向 0.2.x；如遇异常再升级"
    }
    $needHost = $false
} elseif (Get-Command dsh -ErrorAction SilentlyContinue) {
  Ok "dsh 命令存在（版本号读不到，按已安装处理）"
  $needHost = $false
}

if ($needHost) {
  Say "未检测到宿主，安装 DeepSeek Harness $HostVersion（约 830 MB，耐心等）"
  npm i -g "@deepseek-ai/dsh@$HostVersion"
  if ($LASTEXITCODE -ne 0) { Die "宿主安装失败：$LASTEXITCODE" }
  Ok "宿主已安装"
}

# ── 2.5) 布局检查（仅提示，不阻断）─────────────────────────
# npm 全局安装默认把依赖嵌套在 <pkg>/node_modules/ 下，这是设计行为；
# install-strategy=hoisted 只对本地项目生效，全局安装不遵守。
# 插件本身已兼容两种布局（hostCleanMarkersPresent 有四个候选路径），
# 所以这里只提示，不重装、不退出。
$npmRoot = (npm root -g).Trim()
$flatPath = Join-Path $npmRoot "@deepseek-ai\dsh-system-prompt\lib\index.js"
$nestedPath = Join-Path $npmRoot "@deepseek-ai\dsh\node_modules\@deepseek-ai\dsh-system-prompt\lib\index.js"
if (Test-Path $flatPath) {
  Ok "布局：摊平（hoisted）"
} elseif (Test-Path $nestedPath) {
  Ok "布局：嵌套（npm 全局默认，插件已兼容）"
} else {
  Warn "未找到 dsh-system-prompt，插件可能检测不到宿主"
  Write-Host "    摊平: $flatPath" -ForegroundColor DarkGray
  Write-Host "    嵌套: $nestedPath" -ForegroundColor DarkGray
}

# ── 2.6) 原生模块构建（自动，无需用户手动）─────────────────
# npm 11 默认拦截 install/postinstall 脚本，node-pty / koffi 等原生模块
# 不编译会导致 dsh web 启动失败：Cannot find module ...\pty.node
$hostVerForRebuild = if ($installedHost) { $installedHost } else { $HostVersion }
function Test-NativeOk {
  $dirs = @(
    (Join-Path $npmRoot "@deepseek-ai\dsh\node_modules\node-pty"),
    (Join-Path $npmRoot "@deepseek-ai\node-pty"),
    (Join-Path $npmRoot "node-pty")
  )
  foreach ($d in $dirs) {
    # node-pty 1.x：build\Release\pty.node
    if (Test-Path (Join-Path $d "build\Release\pty.node")) { return $true }
    # node-pty 1.2+：prebuilds\<platform>-<arch>\pty.node
    $pre = Join-Path $d "prebuilds"
    if (Test-Path $pre) {
      $hit = Get-ChildItem -Path $pre -Filter "pty.node" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
      if ($hit) { return $true }
    }
  }
  return $false
}

if (Test-NativeOk) {
  Ok "原生模块已就绪"
} else {
  Say "补跑原生模块构建（node-pty / koffi / protobufjs，约 30 秒）"
  npm i -g "@deepseek-ai/dsh@$hostVerForRebuild" `
    --allow-scripts=@deepseek-ai/dsh-subprocess-local,koffi,node-pty,@google/genai,protobufjs 2>&1 | Out-Null
  if (Test-NativeOk) {
    Ok "原生模块已编译"
  } else {
    Warn "node-pty 仍缺失，dsh web 可能起不来"
    Write-Host "    手动补跑:" -ForegroundColor DarkGray
    Write-Host "    npm i -g @deepseek-ai/dsh@$hostVerForRebuild --allow-scripts=@deepseek-ai/dsh-subprocess-local,koffi,node-pty,@google/genai,protobufjs" -ForegroundColor DarkGray
  }
}

# ── 3) profile 目录 ────────────────────────────────────────
$profileDir = Join-Path $DshHomeDir "profiles\web"
New-Item -ItemType Directory -Force -Path $profileDir | Out-Null
Set-Location $profileDir
Say "profile: $profileDir"

# ── 4) 最小 package.json ───────────────────────────────────
if (-not (Test-Path "package.json")) {
  '{"name":"dsh-profile-web","private":true,"version":"0.0.0","dependencies":{}}' |
    Set-Content -Path "package.json" -Encoding utf8
  Ok "已创建最小 package.json"
}

# ── 4.5) 确保 profile 有默认 bundles ──────────────────────
$hasBundles = $false
try {
  $pj = Get-Content "package.json" -Raw | ConvertFrom-Json
  if ($pj.dsh -and $pj.dsh.profile -and $pj.dsh.profile.bundles -and $pj.dsh.profile.bundles.Count -gt 0) { $hasBundles = $true }
} catch { }
if (-not $hasBundles) {
  $pj = Get-Content "package.json" -Raw | ConvertFrom-Json
  if (-not $pj.dsh) { $pj | Add-Member -NotePropertyName dsh -NotePropertyValue ([pscustomobject]@{}) -Force }
  if (-not $pj.dsh.profile) { $pj.dsh | Add-Member -NotePropertyName profile -NotePropertyValue ([pscustomobject]@{}) -Force }
  $pj.dsh.profile | Add-Member -NotePropertyName bundles -NotePropertyValue @('@deepseek-ai/dsh-base','@deepseek-ai/dsh-web-app') -Force
  $pj | ConvertTo-Json -Depth 10 | Set-Content package.json -Encoding utf8
  Ok "已补默认 bundles"
}

# ── 5) 下载插件包 ──────────────────────────────────────────
$tmp = Join-Path $env:TEMP "dsh-purge-$PluginVersion.tgz"
Say "下载插件 $PluginVersion"
try {
  Invoke-WebRequest -Uri $PkgUrl -OutFile $tmp -UseBasicParsing
} catch {
  Die "下载失败：$($_.Exception.Message)"
}
$mb = [math]::Round((Get-Item $tmp).Length / 1MB, 2)
Ok "已下载 $mb MB"

# ── 6) npm 直装 ────────────────────────────────────────────
# 必须绕开 dsh plugin：实测 Windows 上它返回 exit 0 但什么都不装。
Say "安装插件到 profile"
npm install --save --ignore-scripts $tmp 2>&1 | Select-Object -Last 5
if ($LASTEXITCODE -ne 0) { Die "npm install 失败：$LASTEXITCODE" }
if (-not (Test-Path "node_modules\dsh-purge\package.json")) {
  Die "包未就位：node_modules\dsh-purge 不存在"
}

# npm 会把临时文件路径写进 dependencies，%TEMP% 清理后即失效。
# 换成稳定的 release URL。
npm pkg set "dependencies.dsh-purge=$PkgUrl" 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { Warn "无法重写 dependencies，保留原值" }
Ok "插件已写入 node_modules"

# ── 7) 登记到 bundles ─────────────────────────────────────
Say "登记到 profile bundles"
node "node_modules\dsh-purge\scripts\ensure-profile-bundle.mjs"
if ($LASTEXITCODE -ne 0) { Die "登记失败：$LASTEXITCODE" }

# ── 8) 文件级验证（不依赖 dsh 输出）────────────────────────
$v = (Get-Content "node_modules\dsh-purge\package.json" -Raw | ConvertFrom-Json).version
if ($v -ne $PluginVersion) { Die "版本不符：$v" }

$dep = (Get-Content "package.json" -Raw | ConvertFrom-Json).dependencies.'dsh-purge'
if (-not $dep) { Die "profile package.json 未声明 dsh-purge 依赖" }

$patchHit = (Select-String -Path "cordis.patch.yml" -Pattern "dsh-purge" -SimpleMatch -ErrorAction SilentlyContinue).Count
if (-not $patchHit) { Die "cordis.patch.yml 未登记 dsh-purge" }

foreach ($f in @("lib\identity.js", "lib\core.js", "client.js", "bin\dsh-purge.js")) {
  if (-not (Test-Path (Join-Path "node_modules\dsh-purge" $f))) { Die "缺少文件：$f" }
}

# ── 9) 更新地址校验 ───────────────────────────────────────
$upd = Join-Path "node_modules\dsh-purge" "lib\update.js"
if (Test-Path $upd) {
  $m = Select-String -Path $upd -Pattern '^const REPO = "([^"]+)"'
  if ($m) {
    $repo = $m.Matches[0].Groups[1].Value
    if ($repo -match "YuJunZhiXue|HunYiSage") {
      Warn "update.js 仍指向第三方仓库：$repo（请重新拉取最新包）"
    } else {
      Ok "更新源：$repo"
    }
  }
}


Write-Host ""
Ok "安装完成：dsh-purge $v"

# ── 10) 红队模式注册状态 ───────────────────────────────────
$statusFile = Join-Path $DshHomeDir "redteam\preset-declare.json"
if (Test-Path $statusFile) {
  try {
    $st = Get-Content $statusFile -Raw | ConvertFrom-Json
    Write-Host "红队模式状态：$($st.phase)（plugins=$($st.plugins)）" -ForegroundColor Cyan
    if ($st.phase -eq 'registered') { Ok "红队模式已注册" }
    else { Warn "红队模式未完成注册，请按下面第 3 步操作" }
  } catch { Warn "preset-declare.json 解析失败" }
} else {
  Write-Host "红队模式：尚未注册" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "════ 下一步（必须做，否则看不到插件）════" -ForegroundColor Yellow
Write-Host "  0. 首次启动前先设（只在当前窗口有效）：" -ForegroundColor Cyan
Write-Host "       `$env:REDTEAM_PRESET_REFRESH = `"1`""
Write-Host "  1. 完全退出 DeepSeek Harness（托盘右键退出，不是关窗口）"
Write-Host "  2. 重新打开宿主"
Write-Host "  3. 点会话标题旁的 dsh-purge → 清洗 → 应用"
Write-Host "  4. 它会自动重启一次"
Write-Host "  5. 再开，模式下拉里就有「红队模式」"
Write-Host ""
Write-Host "  检查注册状态：" -ForegroundColor Cyan
Write-Host "    type `$env:USERPROFILE\.dsh\redteam\preset-declare.json"
Write-Host ""
Write-Host "  回滚：删除 $profileDir\node_modules\dsh-purge"
Write-Host ""
Write-Host "  ────────────────────────────────" -ForegroundColor Magenta
Write-Host "   你给巴里啊啊点赞了吗？" -ForegroundColor Yellow
Write-Host "  ────────────────────────────────" -ForegroundColor Magenta
