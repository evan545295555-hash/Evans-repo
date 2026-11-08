# dsh-purge 一键卸载（Windows PowerShell，web profile）
# 用法： irm https://raw.githubusercontent.com/evan545295555-hash/Evans-repo/main/uninstall.ps1 | iex
#
# 为什么需要它： dsh plugin --profile web remove dsh-purge 只是转发给 pnpm，
# 只删包和依赖，既不还原宿主补丁，也不清 profile 的 bundles / cordis.patch.yml
# 登记，残留会让宿主启动时挂载一个已不存在的 bundle。
$ErrorActionPreference = "Stop"

$RepoRaw = "https://raw.githubusercontent.com/evan545295555-hash/Evans-repo/main"

function Say($m)  { Write-Host "==> $m" -ForegroundColor Cyan }
function Ok($m)   { Write-Host "OK  $m" -ForegroundColor Green }
function Warn($m) { Write-Host "WARN $m" -ForegroundColor Yellow }
function Die($m)  { Write-Host "ERR $m" -ForegroundColor Red; exit 1 }

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

if (-not (Get-Command node -ErrorAction SilentlyContinue)) { Die "没检测到 Node.js，无法执行卸载" }

Say "dsh-purge 卸载器（web profile）"
$ProfileDir = Find-ProfileDir
if (-not $ProfileDir) { Die "找不到 web profile 目录。请设置 DSH_HOME 后重试。" }
Ok "profile: $ProfileDir"

# 1) 备份：只备份要动的两个文件，绝不删除原始配置
$HomeDir = Split-Path (Split-Path $ProfileDir)
$BackupDir = Join-Path $HomeDir ("backup-dsh-purge-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
foreach ($f in @("package.json", "cordis.patch.yml")) {
  $src = Join-Path $ProfileDir $f
  if (Test-Path $src) { Copy-Item -Path $src -Destination (Join-Path $BackupDir $f) -Force }
}
Ok "已备份到 $BackupDir"

# 2) 还原宿主补丁 + 清 package.json 登记
$Cli = Join-Path $ProfileDir "node_modules\dsh-purge\bin\dsh-purge.js"
if (Test-Path $Cli) {
  Say "还原补丁并移除 profile 登记"
  node $Cli --uninstall
  if ($LASTEXITCODE -ne 0) { Die "补丁还原失败，未继续删除文件。备份在 $BackupDir" }
  Ok "补丁与 package.json 登记已处理"
} else {
  Warn "没找到插件 CLI：$Cli，跳过补丁还原"
  Warn "若之前点过 Apply，请先从界面 dsh-purge → Clean → Restore 还原宿主"
}

# 3) 移除 npm 依赖
Say "移除插件包"
dsh plugin --profile web remove dsh-purge 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) { Warn "pnpm remove 未执行成功（包可能已被 --uninstall 清掉），继续做残留检查" }

# 4) 精确清除 cordis.patch.yml 的 insert 块（只删逐行完全匹配的整块）
Say "清除 profile 补丁登记"
$tmpScript = Join-Path $env:TEMP "dsh-purge-remove-$PID.mjs"
try {
  Invoke-WebRequest -Uri "$RepoRaw/scripts/remove-profile-insert.mjs" -OutFile $tmpScript -TimeoutSec 30 -UseBasicParsing
} catch {
  Warn "清理脚本下载失败，跳过自动清理（下面会给出残留检查）"
}
if (Test-Path $tmpScript) {
  try {
    $raw = (node $tmpScript $ProfileDir 2>$null | Out-String).Trim()
    $result = $raw | ConvertFrom-Json
    switch ($result.status) {
      "removed"     { Ok "cordis.patch.yml 的 dsh-purge insert 已移除" }
      "absent"      { Ok "cordis.patch.yml 无需清理" }
      "no-file"     { Ok "cordis.patch.yml 无需清理" }
      "unrecognized" {
        Warn "cordis.patch.yml 里有 dsh-purge 残留，但形态与安装器写入的不一致，未自动改动"
        Warn "残留行号：$($result.lines -join ', ')；备份在 $BackupDir"
      }
      default       { Warn "清理结果无法解析：$raw" }
    }
  } catch {
    Warn "清理脚本执行异常：$($_.Exception.Message)"
  } finally {
    Remove-Item -Path $tmpScript -Force -ErrorAction SilentlyContinue
  }
}

# 5) 残留复检，不静默报成功
Say "残留复检"
$pkgJson = Join-Path $ProfileDir "package.json"
node -e 'const p=require(process.argv[1]);const b=(p.dsh&&p.dsh.profile&&p.dsh.profile.bundles)||[];const d=p.dependencies||{};process.exit(b.includes("dsh-purge")||Object.prototype.hasOwnProperty.call(d,"dsh-purge")?1:0)' $pkgJson
$leftPkg = $LASTEXITCODE -ne 0
$leftYaml = $false
$patchFile = Join-Path $ProfileDir "cordis.patch.yml"
if (Test-Path $patchFile) {
  $leftYaml = [bool](Select-String -Path $patchFile -Pattern '^\s*-?\s*(id|name):\s*dsh-purge' -Quiet)
}
if ($leftPkg -or $leftYaml) {
  Warn "仍检测到残留（package.json=$leftPkg / cordis.patch.yml=$leftYaml），本次不算干净卸载"
  Warn "备份在 $BackupDir；请手动删除残留条目后重启 dsh web"
  exit 1
}
Ok "无残留"

Write-Host ""
Ok "卸载完成，重启 dsh web 生效"
Write-Host "   备份： $BackupDir"
Write-Host "   启动： dsh web"
