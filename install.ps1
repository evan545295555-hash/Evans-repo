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
if ($major -lt 18) { Die "Node 版本太低（$nodeVerRaw），需要 18 以上" }
Ok "Node $nodeVerRaw"

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
  Ok "已装宿主 $installedHost"
  if ($installedHost -ne $HostVersion) {
    Warn "宿主是 $installedHost，脚本按 $HostVersion 验证；继续用现有版本"
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
