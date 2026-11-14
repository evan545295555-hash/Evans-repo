param([switch]$Kill)
$dshProcs = @()
$otherProcs = @()
Get-CimInstance Win32_Process -Filter "Name='node.exe'" -ErrorAction SilentlyContinue | ForEach-Object {
    $cmd = $_.CommandLine
    if (-not $cmd) { return }
    $isDsh = $false
    if ($cmd -match '@deepseek-ai[\\/]dsh[\\/]lib[\\/]bin\.js') { $isDsh = $true }
    if ($cmd -match 'dsh\.cmd\s+(web|serve)') { $isDsh = $true }
    if ($cmd -match '[\\/]dsh\s+(web|serve)') { $isDsh = $true }
    $short = if ($cmd.Length -gt 78) { $cmd.Substring(0, 78) } else { $cmd }
    $row = [PSCustomObject]@{ PID = $_.ProcessId; Cmd = $short }
    if ($isDsh) { $script:dshProcs += $row } else { $script:otherProcs += $row }
}
Write-Host "`n=== DSH 进程（会被停）===" -ForegroundColor Cyan
if ($dshProcs.Count -eq 0) { Write-Host "  无" -ForegroundColor DarkGray }
foreach ($p in $dshProcs) { Write-Host "  PID=$($p.PID)  $($p.Cmd)" -ForegroundColor Green }
Write-Host "`n=== 其他 node 进程（不会停）===" -ForegroundColor Cyan
if ($otherProcs.Count -eq 0) { Write-Host "  无" -ForegroundColor DarkGray }
foreach ($p in $otherProcs) { Write-Host "  PID=$($p.PID)  $($p.Cmd)" -ForegroundColor DarkGray }
$appProcs = @(Get-Process "*DeepSeek Harness*" -ErrorAction SilentlyContinue)
if ($appProcs.Count -gt 0) {
    Write-Host "`n=== 桌面版 App ===" -ForegroundColor Cyan
    foreach ($a in $appProcs) { Write-Host "  PID=$($a.Id)  $($a.ProcessName)" }
}
if ($Kill) {
    Write-Host "`n=== 执行停止 ===" -ForegroundColor Yellow
    foreach ($p in $dshProcs) { Stop-Process -Id $p.PID -Force -ErrorAction SilentlyContinue; Write-Host "  已停 PID=$($p.PID)" -ForegroundColor Green }
    foreach ($a in $appProcs) { Stop-Process -Id $a.Id -Force -ErrorAction SilentlyContinue; Write-Host "  已停 App PID=$($a.Id)" -ForegroundColor Green }
} else {
    Write-Host "`n以上标 DSH 的是本次要停的；其他 node 不动。" -ForegroundColor DarkGray
    Write-Host "确认无误后加 -Kill 参数执行停止。" -ForegroundColor DarkGray
}
