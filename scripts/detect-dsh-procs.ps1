# dsh-purge 进程识别（Windows 原生入口）
#
# 用法:
#   powershell -NoProfile -File scripts/detect-dsh-procs.ps1
#   powershell -NoProfile -File scripts/detect-dsh-procs.ps1 -Kill
#
# 输出格式（每行一条）：
#   <pid>|DSH|<commandLine>      这是本次要停的 DSH 进程
#   <pid>|other|<commandLine>    其他 node 进程，不动
#   QUERY_FAIL|<reason>          查询本身失败（区分于"查询成功但没匹配"）
#   QUERY_OK_NO_MATCH            查询成功，但没有任何 node 进程
#
# 筛选规则（只认这三种，不用「命令行含 dsh|deepseek」这种过宽规则）：
#   1. node 跑 ...\@deepseek-ai\dsh\lib\bin.js
#   2. dsh.cmd web / dsh.cmd serve
#   3. ...\dsh web / ...\dsh serve
#
# 一个普通 node 进程即使路径里有 deepseek（如 deepseek-tools\x.js）也不会被判为 DSH。

param([switch]$Kill)

$ErrorActionPreference = 'Continue'

function Test-IsDshProcess {
    param([string]$Cmd)
    if ([string]::IsNullOrWhiteSpace($Cmd)) { return $false }
    if ($Cmd -match '@deepseek-ai[\\/]dsh[\\/]lib[\\/]bin\.js') { return $true }
    if ($Cmd -match 'dsh\.cmd\s+(web|serve)') { return $true }
    if ($Cmd -match '[\\/]dsh\s+(web|serve)') { return $true }
    return $false
}

# ── 查询 ──────────────────────────────────────────────────
$procs = $null
try {
    $procs = Get-CimInstance Win32_Process -Filter "Name='node.exe'" -ErrorAction Stop
} catch {
    Write-Output ("QUERY_FAIL|Get-CimInstance 失败: " + $_.Exception.Message)
    exit 2
}

if ($null -eq $procs) {
    Write-Output "QUERY_FAIL|Get-CimInstance 返回 null"
    exit 2
}

$matched = 0
$dshList = @()

foreach ($p in $procs) {
    $cmd = $p.CommandLine
    if ([string]::IsNullOrWhiteSpace($cmd)) { continue }
    $matched++
    if (Test-IsDshProcess $cmd) {
        Write-Output ("{0}|DSH|{1}" -f $p.ProcessId, $cmd)
        $dshList += $p.ProcessId
    } else {
        Write-Output ("{0}|other|{1}" -f $p.ProcessId, $cmd)
    }
}

if ($matched -eq 0) {
    Write-Output "QUERY_OK_NO_MATCH|没有正在运行的 node 进程"
}

# ── 桌面版 App 单独列出 ──────────────────────────────────
$appProcs = @(Get-Process "*DeepSeek Harness*" -ErrorAction SilentlyContinue)
foreach ($a in $appProcs) {
    Write-Output ("{0}|APP|{1}" -f $a.Id, $a.ProcessName)
    $dshList += $a.Id
}

# ── 停止（只有显式 -Kill 才执行）────────────────────────
if ($Kill) {
    if ($dshList.Count -eq 0) {
        Write-Output "KILL_SKIPPED|没有需要停的进程"
        exit 0
    }
    foreach ($id in $dshList) {
        try {
            Stop-Process -Id $id -Force -ErrorAction Stop
            Write-Output ("KILLED|{0}" -f $id)
        } catch {
            Write-Output ("KILL_FAIL|{0}|{1}" -f $id, $_.Exception.Message)
        }
    }
}

exit 0
