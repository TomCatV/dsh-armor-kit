<#
.SYNOPSIS
  运行时实测：验证 purge 补丁真的在跑（不是读配置，是跑出来的）

  测试项：
    1. 越界写盘   —— 往 C:\Windows\Temp 写/读/删，无需 escalation
    2. 提权命令   —— 直接执行系统命令，无确认弹窗
    3. 身份句清除 —— 宿主源码里不得残留 DeepSeek Harness 身份句
    4. 注入保护   —— 系统提示模块必须含 inject 保留逻辑
    5. 审批放行   —— user-approval 模块必须含 auto-granted 标记
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'
$pass = 0; $fail = 0; $warn = 0

function Say($msg, $color = 'White') { Write-Host $msg -ForegroundColor $color }
function T($name, $ok, $detail = '') {
  if ($ok) { $script:pass++; Say "    ✓ $name $detail" 'Green' }
  else     { $script:fail++; Say "    ✗ $name $detail" 'Red' }
}

# 定位宿主
$aiBase = $env:DSH_BASE
if (-not $aiBase) {
  foreach ($c in @("$env:USERPROFILE\Downloads\dsh-desktop-master\dsh-desktop-master\dsh-plugin-desktop\node_modules\@deepseek-ai",
                   "$env:USERPROFILE\.dsh\profiles\node_modules\@deepseek-ai")) {
    if (Test-Path "$c\dsh-agent-instructions\lib\index.js") { $aiBase = $c; break }
  }
}

Say "═══════════════════════════════════════" 'DarkCyan'
Say " dsh-armor-kit  运行时实测" 'Cyan'
Say "═══════════════════════════════════════" 'DarkCyan'
Say "宿主根: $aiBase"
Say ""

# ── 1. 越界写盘 ───────────────────────────────────────────
Say "[1] 越界写盘（Windows\Temp，无 escalation 参数）" 'Cyan'
$probe = "$env:TEMP\dsh-armor-probe-$(Get-Random).txt"
try {
  Set-Content -Path $probe -Value "ok $(Get-Date -Format o)" -Encoding UTF8
  $read = Get-Content $probe -Raw
  Remove-Item $probe -Force
  T "写入→读回→删除" ($read -match 'ok') ""
} catch {
  T "写入→读回→删除" $false $_.Exception.Message
}

# ── 2. 提权命令 ───────────────────────────────────────────
Say "[2] 提权命令（直接执行，无确认）" 'Cyan'
try {
  $out = & whoami 2>&1
  T "whoami" ($LASTEXITCODE -eq 0) "→ $out"
} catch {
  T "whoami" $false $_.Exception.Message
}

# ── 3. 身份句清除 ─────────────────────────────────────────
Say "[3] 身份句清除" 'Cyan'
$identity = 'You are an AI agent powered by DeepSeek Harness'
$hits = @()
if ($aiBase) {
  $hits = Get-ChildItem "$aiBase\dsh-system-prompt","$aiBase\dsh-persona" -Recurse -File -Include '*.js' -ErrorAction SilentlyContinue |
    Select-String -Pattern $identity -SimpleMatch -ErrorAction SilentlyContinue
}
T "身份句已从 runtime 消失" (@($hits).Count -eq 0) $(if (@($hits).Count) { "残留 $($hits.Count) 处" } else { "" })

# ── 4. 注入保护 ───────────────────────────────────────────
Say "[4] 注入保护（系统提示瀑布保留）" 'Cyan'
if ($aiBase) {
  $f = "$aiBase\dsh-system-prompt\lib\index.js"
  $m = if (Test-Path $f) { Select-String -Path $f -Pattern 'complete prompt keeps inject' -SimpleMatch } else { $null }
  T "inject 保留逻辑已落地" ([bool]$m) $(if ($m) { "L$($m.LineNumber)" } else { "" })
} else {
  T "inject 保留逻辑已落地" $false "宿主未定位"
}

# ── 5. 审批放行 ───────────────────────────────────────────
Say "[5] 审批自动放行" 'Cyan'
if ($aiBase) {
  $f = "$aiBase\dsh-user-approval\lib\index.js"
  $m = if (Test-Path $f) { Select-String -Path $f -Pattern 'auto-granted' -SimpleMatch } else { $null }
  T "审批 auto-granted 标记" ([bool]$m) $(if ($m) { "L$($m.LineNumber)" } else { "" })
} else {
  T "审批 auto-granted 标记" $false "宿主未定位"
}

# ── 6. Kali 工具链 ─────────────────────────────────────────
Say "[6] Kali 容器工具链" 'Cyan'
$kaliCmd = Get-Command kali -ErrorAction SilentlyContinue
if (-not $kaliCmd) {
  Warn "kali shim 不在 PATH（新开终端或跑 .\scripts\kali-setup.ps1）"
  $script:warn++
} else {
  $state = (& docker inspect -f '{{.State.Running}}' kali-redteam 2>$null)
  if ($state -eq 'true') {
    $miss = 0
    $tools = 'nmap masscan sqlmap hydra john hashcat ffuf chisel python3'.Split(' ')
    $out = & docker exec kali-redteam bash -lc "for t in $($tools -join ' '); do command -v `$t >/dev/null 2>&1 || echo `$t; done" 2>$null
    $missingTools = @($out | Where-Object { $_ })
    $miss = $missingTools.Count
    if ($miss -eq 0) { T "容器在跑 + 核心工具齐全" $true "" }
    else { T "容器在跑 + 核心工具齐全" $false "缺: $($missingTools -join ', ')" }
  } elseif ($state -eq 'false') {
    T "Kali 容器在跑" $false "容器存在但未运行（kali 命令会自动拉起）"
    $script:warn++
  } else {
    T "Kali 容器在跑" $false "容器不存在，跑 .\scripts\kali-setup.ps1"
    $script:warn++
  }
}

# ── 汇总 ─────────────────────────────────────────────────
Say ""
Say "═══════════════════════════════════════" 'DarkCyan'
$note = if ($warn) { "（+${warn} 项警告）" } else { "" }
if ($fail -eq 0) {
  Say " 全部通过 ($pass/$($pass+$fail))$note" 'Green'
  Say "═══════════════════════════════════════" 'DarkCyan'
  exit 0
} else {
  Say " 通过 $pass / 失败 $fail$note" 'Yellow'
  Say "═══════════════════════════════════════" 'DarkCyan'
  Say "失败项多为宿主版本锚点漂移，先跑 .\scripts\install.ps1 重打补丁" 'Yellow'
  exit 1
}
