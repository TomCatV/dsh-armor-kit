<#
.SYNOPSIS
  重启 DSH Harness 宿主进程（补丁改了磁盘源码，必须重启才加载）
#>
[CmdletBinding()]
param(
  [int]$DelaySec = 5
)

$ErrorActionPreference = 'Continue'

function Say($msg, $color = 'White') { Write-Host $msg -ForegroundColor $color }

# 定位宿主主进程（electron + dsh-plugin-desktop/lib/main.js）
$main = Get-CimInstance Win32_Process -Filter "Name='electron.exe'" |
  Where-Object { $_.CommandLine -match 'dsh-plugin-desktop\\lib\\main\.js' -and $_.CommandLine -notmatch '--type=' } |
  Select-Object -First 1

if (-not $main) {
  # 兜底：DSH Desktop.exe
  $main = Get-CimInstance Win32_Process -Filter "Name='DSH Desktop.exe'" |
    Where-Object { $_.CommandLine -notmatch '--type=' } |
    Select-Object -First 1
}

if (-not $main) {
  Say "未找到运行中的 DSH 主进程。若尚未启动，直接打开即可。" 'Yellow'
  exit 0
}

$exe = $main.ExecutablePath
$argv = ($main.CommandLine -split '\s+', 2)[1]
$cwd  = Split-Path $exe -Parent
$mainPid = $main.ProcessId

Say "主进程 PID : $mainPid"
Say "可执行     : $exe"
Say "参数       : $argv"
Say ""
Say "$DelaySec 秒后杀掉并重新拉起..." 'Yellow'

$helper = Join-Path $env:TEMP 'dsh-armor-restart.ps1'
$script = @"
Start-Sleep -Seconds $DelaySec
Stop-Process -Id $mainPid -Force -ErrorAction SilentlyContinue
for(`$i=0; `$i -lt 40; `$i++) {
  if (-not (Get-Process -Id $mainPid -ErrorAction SilentlyContinue)) { break }
  Start-Sleep -Milliseconds 250
}
Start-Sleep -Seconds 2
`$env:DSH_PROFILE = 'desktop'
Remove-Item Env:ELECTRON_RUN_AS_NODE -ErrorAction SilentlyContinue
Start-Process -FilePath '$exe' -ArgumentList @($argv) -WorkingDirectory '$cwd'
"@
Set-Content -Path $helper -Value $script -Encoding UTF8

Start-Process -FilePath 'pwsh.exe' `
  -ArgumentList @('-NoProfile','-WindowStyle','Hidden','-File',$helper) `
  -WindowStyle Hidden

Say "重启助手已后台拉起（detached）。$DelaySec 秒后进程会重启。" 'Green'
Say "请等待窗口重新出现，然后运行 .\scripts\verify.ps1 验证。" 'Cyan'
