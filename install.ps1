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
$major = [int](node -p "process.versions.node.split('.')[0]")
if ($major -lt 18) { Die "Node 版本太低（$(node -v)），需要 18 以上" }
Ok "Node $(node -v)"

# ── 2) 宿主 ────────────────────────────────────────────────
# 注意：Windows 上 dsh --version 可能返回 0 但不打印，
# 所以这里不把版本号当作硬条件，只保证 npm 全局包装上。
$needHost = $true
if (Get-Command dsh -ErrorAction SilentlyContinue) {
  $cur = (dsh --version 2>$null | Out-String).Trim()
  if ($cur -eq $HostVersion) { $needHost = $false; Ok "宿主 $cur" }
  elseif ($cur) { Warn "宿主版本 $cur，切换到 $HostVersion" }
  else { Warn "dsh 无输出（Windows 已知问题），仍继续" }
}
if ($needHost) {
  Say "安装 DeepSeek Harness $HostVersion（依赖较多，请耐心等）"
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
Write-Host "   重启 DeepSeek Harness 生效"
Write-Host "   启动： dsh web"
Write-Host "   回滚： 删除 $profileDir\node_modules\dsh-purge 后重跑 dsh --profile web --dump-config"
