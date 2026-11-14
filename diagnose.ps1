# dsh-purge 环境诊断（只读，不改任何东西）
# 用法：irm <raw 地址> | iex

$ErrorActionPreference = "Continue"

function Line { Write-Host ("=" * 60) -ForegroundColor DarkGray }
function Head($t) { Write-Host "`n$t" -ForegroundColor Cyan }
function Ok($t)   { Write-Host "  [OK]   $t" -ForegroundColor Green }
function Bad($t)  { Write-Host "  [FAIL] $t" -ForegroundColor Red }
function Warn2($t){ Write-Host "  [WARN] $t" -ForegroundColor Yellow }
function Info($t) { Write-Host "  $t" -ForegroundColor Gray }

Line
Write-Host " dsh-purge 环境诊断（只读）" -ForegroundColor White
Write-Host " 本脚本不会修改任何文件" -ForegroundColor DarkGray
Line

# ── 1. Node ──────────────────────────────────────────────
Head "1. Node.js"
if (Get-Command node -EA SilentlyContinue) {
    $v = "$(node -v 2>&1)".Trim()
    Info "版本: $v"
    if ($v -match 'v(\d+)\.') {
        $major = [int]$Matches[1]
        if ($major -ge 20) { Ok "符合要求（需要 20+）" }
        else { Bad "版本太低，需要 20+"; Info "升级: winget install OpenJS.NodeJS.LTS" }
    } else {
        Bad "无法解析版本: $v"
    }
    Info "npm: $(npm -v 2>&1)"
} else {
    Bad "未安装 Node.js"
    Info "安装: winget install OpenJS.NodeJS.LTS"
}

# ── 2. 宿主 ──────────────────────────────────────────────
Head "2. 宿主 (DeepSeek Harness)"
$npmRoot = ""
try { $npmRoot = "$(npm root -g 2>&1)".Trim() } catch { }
Info "npm 全局根: $npmRoot"

$hostVer = ""
try {
    $ls = "$(npm ls -g @deepseek-ai/dsh --depth=0 2>&1)"
    if ($ls -match '@deepseek-ai/dsh@([\w.\-]+)') { $hostVer = $Matches[1] }
} catch { }

if ($hostVer) {
    Ok "已装: @deepseek-ai/dsh@$hostVer"
    if ($hostVer -like "0.2.*") { Ok "版本兼容（0.2.x）" }
    else { Warn2 "非 0.2.x，插件可能不兼容" }
} else {
    Bad "未安装宿主"
    Info "安装: npm i -g @deepseek-ai/dsh@0.2.1-rc.2"
}

# ── 3. 布局 ──────────────────────────────────────────────
Head "3. 宿主依赖布局"
$dshDir = Join-Path $npmRoot "@deepseek-ai\dsh"
$flat   = Join-Path $npmRoot "@deepseek-ai\dsh-system-prompt\lib\index.js"
$nested = Join-Path $dshDir "node_modules\@deepseek-ai\dsh-system-prompt\lib\index.js"

if (Test-Path $flat) {
    Ok "摊平布局（hoisted）"
} elseif (Test-Path $nested) {
    Ok "嵌套布局（npm 全局默认，插件已兼容）"
} else {
    Bad "两种布局都找不到 dsh-system-prompt"
    Info "摊平: $flat"
    Info "嵌套: $nested"
}

# ── 4. dsh 命令 ──────────────────────────────────────────
Head "4. dsh 命令"
$dshCmd = Get-Command dsh -EA SilentlyContinue
if ($dshCmd) {
    Info "路径: $($dshCmd.Source)"
    # npm root -g = <prefix>\node_modules，命令在 <prefix>\dsh.cmd
    # 两者是兄弟，不能用前缀比较
    $all = @(Get-Command dsh -All -EA SilentlyContinue)
    if ($all.Count -gt 1) {
        Warn2 "发现 $($all.Count) 个 dsh，可能有多套安装："
        $all | ForEach-Object { Info "    $($_.Source)" }
    } elseif ($dshCmd.Source -like "*\nodejs\dsh.cmd" -or $dshCmd.Source -like "$npmRoot\..\dsh.cmd" -or (Split-Path $dshCmd.Source -Parent) -eq (Split-Path $npmRoot -Parent)) {
        Ok "来自当前 Node 安装（正确）"
    } else {
        Warn2 "不在当前 Node 安装下，可能有多套"
    }
} else {
    Bad "dsh 命令不存在"
}

# ── 5. 插件 ──────────────────────────────────────────────
Head "5. 插件 (dsh-purge)"
$web = "$env:USERPROFILE\.dsh\profiles\web"
$pkg = Join-Path $web "node_modules\dsh-purge"

if (Test-Path $pkg) {
    $pv = ""
    try { $pv = (Get-Content (Join-Path $pkg "package.json") -Raw | ConvertFrom-Json).version } catch { }
    Ok "已装: $pv"
    if ($pv -eq "1.1.71-rc2.1") { Ok "版本正确" }
    else { Warn2 "版本不是 1.1.71-rc2.1，可能缺修复" }
} else {
    Info "未安装"
}

# ── 6. profile 配置 ─────────────────────────────────────
Head "6. profile 配置"
$profPkg = Join-Path $web "package.json"
if (Test-Path $profPkg) {
    try {
        $d = Get-Content $profPkg -Raw | ConvertFrom-Json
        $bundles = $d.dsh.profile.bundles
        Info "bundles: $($bundles -join ',')"
        if ($bundles -contains "dsh-purge") { Ok "dsh-purge 已登记" }
        else { Info "dsh-purge 未登记（没装或已清）" }
        if ($bundles -contains "@deepseek-ai/dsh-base") { Ok "base 存在" } else { Bad "缺 base" }
        if ($bundles -contains "@deepseek-ai/dsh-web-app") { Ok "web-app 存在" } else { Bad "缺 web-app" }
    } catch { Bad "package.json 解析失败" }
} else {
    Info "profile package.json 不存在（还没初始化）"
}

$patch = Join-Path $web "cordis.patch.yml"
if (Test-Path $patch) {
    $n = (Select-String -Path $patch -Pattern "dsh-purge" -SimpleMatch -EA SilentlyContinue).Count
    Info "patch.yml 里 dsh-purge 提及: $n"
} else {
    Info "cordis.patch.yml 不存在"
}

# ── 7. 红队模式 ─────────────────────────────────────────
Head "7. 红队模式"
$st = "$env:USERPROFILE\.dsh\redteam\preset-declare.json"
if (Test-Path $st) {
    try {
        $s = Get-Content $st -Raw | ConvertFrom-Json
        Info "phase  : $($s.phase)"
        Info "plugins: $($s.plugins)"
        Info "broken : $($s.broken)"
        if ($s.phase -eq "registered" -and -not $s.broken) { Ok "注册成功" }
        elseif ($s.phase -eq "registered-broken") { Warn2 "有组件未启动，见 broken" }
        elseif ($s.phase -eq "waiting-registry") { Warn2 "等 registry，可能 bundles 缺项" }
    } catch { Bad "解析失败" }
} else {
    Info "未生成（插件还没加载过）"
}

# ── 8. 残留检查 ─────────────────────────────────────────
Head "8. 残留检查"
$leftovers = @{
    "D:\deepseek"                                      = (Test-Path "D:\deepseek")
    "$npmRoot\@deepseek-ai"                            = (Test-Path (Join-Path $npmRoot "@deepseek-ai"))
    "$web\node_modules\dsh-purge-community"            = (Test-Path (Join-Path $web "node_modules\dsh-purge-community"))
    "$web\node_modules\dsh-purge-panel"                = (Test-Path (Join-Path $web "node_modules\dsh-purge-panel"))
    "$env:USERPROFILE\.dsh\.agent-presets\redteam"     = (Test-Path "$env:USERPROFILE\.dsh\.agent-presets\redteam")
    "$env:USERPROFILE\.dsh\dsh-purge-community"        = (Test-Path "$env:USERPROFILE\.dsh\dsh-purge-community")
}
foreach ($k in $leftovers.Keys) {
    if ($leftovers[$k]) { Info "$k : 存在" }
}

# ── 9. 总结 ─────────────────────────────────────────────
Line
Write-Host " 诊断完成，未修改任何文件" -ForegroundColor White
Write-Host ""
Write-Host " 请把以上完整输出截图发出来" -ForegroundColor Yellow
Line
