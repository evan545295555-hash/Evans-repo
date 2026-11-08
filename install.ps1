# dsh-purge 1.1.71-rc2.1 一键安装（Windows PowerShell，仅 web profile）
# 用法： irm https://raw.githubusercontent.com/evan545295555-hash/Evans-repo/main/install.ps1 | iex
$ErrorActionPreference = "Stop"

$PluginVersion = "1.1.71-rc2.1"
$HostVersion   = "0.2.1-rc.2"
$RepoRaw       = "https://raw.githubusercontent.com/evan545295555-hash/Evans-repo/main"
$Pkg = "https://github.com/evan545295555-hash/Evans-repo/releases/download/v$PluginVersion/dsh-purge-$PluginVersion.tgz"

function Say($m) { Write-Host "==> $m" -ForegroundColor Cyan }
function Ok($m)  { Write-Host "OK  $m" -ForegroundColor Green }
function Die($m) { Write-Host "ERR $m" -ForegroundColor Red; exit 1 }

# 找真正在用的 web profile，不再硬编码 $env:USERPROFILE\.dsh
function Find-ProfileDir {
  $cands = @()
  if ($env:DSH_HOME) { $cands += $env:DSH_HOME }
  $dshCmd = Get-Command dsh -ErrorAction SilentlyContinue
  if ($dshCmd) {
    $dir = Split-Path $dshCmd.Source
    $cands += @(
      (Join-Path $dir ".dsh"),
      (Join-Path (Split-Path $dir) ".dsh"),
      (Join-Path (Split-Path (Split-Path $dir)) ".dsh")
    )
  }
  $cands += @(
    (Join-Path $env:USERPROFILE ".dsh"),
    (Join-Path $env:APPDATA "DeepSeek Harness\dsh-home"),
    (Join-Path $env:LOCALAPPDATA "DeepSeek Harness\dsh-home")
  )
  foreach ($c in ($cands | Select-Object -Unique)) {
    if (-not $c) { continue }
    $p = Join-Path $c "profiles\web"
    if (Test-Path (Join-Path $p "package.json")) { return $p }
  }
  return $null
}

Say "dsh-purge $PluginVersion 安装器（仅 web profile / dsh web）"
Say "注意：本脚本会把宿主版本对齐到 $HostVersion，其他版本会被覆盖重装"

# 1) Node + npm
if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
  Die "没检测到 Node.js。先装它：https://nodejs.org （选 LTS）"
}
if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
  Die "没检测到 npm。它随 Node.js 一起安装：https://nodejs.org"
}
$major = [int](node -p "process.versions.node.split('.')[0]")
if ($major -lt 18) { Die "Node 版本太低（$(node -v)），需要 18 以上" }
Ok "Node $(node -v)"

# 2) 宿主（版本不符会覆盖重装，已在开头披露）
$needHost = $true
if (Get-Command dsh -ErrorAction SilentlyContinue) {
  $cur = (dsh --version 2>$null | Out-String).Trim()
  if ($cur -eq $HostVersion) { $needHost = $false; Ok "宿主 $cur" }
  else { Say "宿主当前是 $cur，将覆盖切换到 $HostVersion（约 830 MB）" }
}
if ($needHost) {
  Say "安装 DeepSeek Harness $HostVersion（约 830 MB，耐心等）"
  npm i -g "@deepseek-ai/dsh@$HostVersion"
  if ($LASTEXITCODE -ne 0) { Die "宿主安装失败" }
  Ok "宿主 $((dsh --version 2>$null | Out-String).Trim())"
}

# 3) 初始化并定位 web profile
dsh --profile web --dump-config 2>$null | Out-Null
$ProfileDir = Find-ProfileDir
if (-not $ProfileDir) {
  Die "找不到 web profile 目录（已找 DSH_HOME / dsh 启动器旁边 / USERPROFILE\.dsh）。请设置 DSH_HOME 后重试。"
}
Ok "profile: $ProfileDir"

# 4) 插件
Say "下载并安装插件"
dsh plugin --profile web add --ignore-scripts $Pkg
if ($LASTEXITCODE -ne 0) { Die "插件安装失败" }

# 5) 登记
Say "登记到 profile"
Push-Location $ProfileDir
try {
  node node_modules/dsh-purge/scripts/ensure-profile-bundle.mjs
  if ($LASTEXITCODE -ne 0) { Die "profile 登记脚本执行失败" }
} finally {
  Pop-Location
}

# 6) 验收：三层断言，不再依赖 dump-config 输出行首无缩进
if (-not (Test-Path (Join-Path $ProfileDir "node_modules\dsh-purge\package.json"))) {
  Die "插件包未落地：$ProfileDir\node_modules\dsh-purge"
}
$pkgJson = Join-Path $ProfileDir "package.json"
node -e 'const p=require(process.argv[1]);const b=p&&p.dsh&&p.dsh.profile&&p.dsh.profile.bundles;process.exit(Array.isArray(b)&&b.includes("dsh-purge")?0:1)' $pkgJson
if ($LASTEXITCODE -ne 0) { Die "profile 登记失败（bundles 未写入）" }
$dump = (dsh --profile web --dump-config 2>$null | Out-String)
if ([string]::IsNullOrWhiteSpace($dump)) { Die "dsh --profile web --dump-config 无输出，无法确认挂载" }
$n = [regex]::Matches($dump, '(?im)^\s*-?\s*(id|name):\s*dsh-purge\s*$').Count
if ($n -lt 1) { Die "配置里找不到 dsh-purge 挂载。诊断：cd '$ProfileDir'; dsh --profile web --dump-config | Select-Object -First 40" }
Ok "挂载校验通过（匹配 $n 处）"

Write-Host ""
Ok "安装完成，重启 DeepSeek Harness 生效"
Write-Host "   启动： dsh web"
Write-Host "   然后： 点标题旁 dsh-purge → Clean → Apply → 新开一个对话"
Write-Host "   卸载： irm $RepoRaw/uninstall.ps1 | iex"
Write-Host "          只跑 dsh plugin --profile web remove dsh-purge 会残留配置，别只跑那条"
