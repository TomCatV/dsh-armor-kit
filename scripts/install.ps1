<#
.SYNOPSIS
  dsh-armor-kit 一键安装：purge 清洗 + 无限四代内核 + 唤醒口令 + 红队技能集

.DESCRIPTION
  1. 备份宿主 @deepseek-ai 全部目标文件
  2. 安装 dsh-purge-community 与 dsh-infinite-gen-4 插件
  3. 写入 prompt-inject.md（含唤醒口令）
  4. 执行 purge 全量清洗
  5. 打印逐条补丁落地状态

.EXAMPLE
  .\scripts\install.ps1
  .\scripts\install.ps1 -SkipBackup        # 跳过备份（已有备份时）
  .\scripts\install.ps1 -WakeWord "开干"    # 自定义唤醒口令
#>
[CmdletBinding()]
param(
  [string]$DSHHome = "$env:USERPROFILE\.dsh",
  [string]$WakeWord = "甲来",
  [switch]$SkipBackup,
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$KitRoot = Split-Path $PSScriptRoot -Parent

function Say($msg, $color = 'White') { Write-Host $msg -ForegroundColor $color }
function Step($n, $msg) { Say "`n[$n/5] $msg" 'Cyan' }
function Ok($msg)   { Say "    ✓ $msg" 'Green' }
function Warn($msg) { Say "    ! $msg" 'Yellow' }
function Bad($msg)  { Say "    ✗ $msg" 'Red' }

Say "═══════════════════════════════════════" 'DarkCyan'
Say " dsh-armor-kit  安装器" 'Cyan'
Say "═══════════════════════════════════════" 'DarkCyan'
Say "  DSH_HOME : $DSHHome"
Say "  套件根   : $KitRoot"
Say "  唤醒口令 : $WakeWord"
if ($DryRun) { Say "  模式     : DryRun（只检查，不落盘）" 'Yellow' }

# ── 0. 前置检查 ─────────────────────────────────────────────
Step 0 "前置检查"

if (-not (Test-Path $DSHHome)) {
  Bad "DSH_HOME 不存在: $DSHHome"
  Say "  → 请先安装并运行一次 DSH Harness，或用 -DSHHome 指定路径"
  exit 1
}
Ok "DSH_HOME 存在"

$node = Get-Command node -ErrorAction SilentlyContinue
if (-not $node) { Bad "未找到 node，需要 Node.js >= 20"; exit 1 }
Ok ("node " + (& node -v))

# 定位宿主 @deepseek-ai（即 purge 要清洗的目标）
$aiBase = $env:DSH_BASE
if (-not $aiBase) {
  # 常见位置探测
  $candidates = @()
  $desktopRoot = Get-ChildItem "$env:USERPROFILE\Downloads" -Directory -Filter 'dsh*' -ErrorAction SilentlyContinue |
    ForEach-Object { Join-Path $_.FullName 'dsh-plugin-desktop\node_modules\@deepseek-ai' }
  $candidates += $desktopRoot
  $candidates += "$DSHHome\profiles\node_modules\@deepseek-ai"
  $candidates += "$DSHHome\profiles\desktop\node_modules\@deepseek-ai"
  foreach ($c in $candidates) {
    if ($c -and (Test-Path "$c\dsh-agent-instructions\lib\index.js")) { $aiBase = $c; break }
  }
}
if (-not $aiBase -or -not (Test-Path "$aiBase\dsh-agent-instructions\lib\index.js")) {
  Bad "未定位宿主 @deepseek-ai"
  Say "  → 请设 DSH_BASE 环境变量指向含 dsh-agent-instructions/lib 的目录后重试"
  exit 1
}
Ok "宿主根: $aiBase"
$env:DSH_BASE = $aiBase

# ── 1. 备份 ────────────────────────────────────────────────
Step 1 "备份宿主文件"
$backupDir = Join-Path $DSHHome 'dsh-purge\backup'
if ($SkipBackup -and (Test-Path $backupDir)) {
  Warn "跳过备份（已存在: $backupDir）"
} else {
  if ($DryRun) { Warn "DryRun：跳过备份" }
  else {
    New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
    $targets = Get-ChildItem $aiBase -Recurse -File -Include '*.js','*.mjs','*.yml','*.yaml','*.json' |
      Where-Object { $_.Length -lt 2MB }
    $i = 0
    foreach ($f in $targets) {
      $rel = $f.FullName.Substring($aiBase.Length).TrimStart('\')
      $dest = Join-Path $backupDir $rel
      New-Item -ItemType Directory -Force -Path (Split-Path $dest -Parent) | Out-Null
      Copy-Item $f.FullName $dest -Force
      $i++
    }
    Ok "已备份 $i 个文件 → $backupDir"
  }
}

# ── 2. 安装插件 ────────────────────────────────────────────
Step 2 "安装插件"
$pluginDst = Join-Path $DSHHome 'plugins'
New-Item -ItemType Directory -Force -Path $pluginDst | Out-Null

foreach ($p in @('dsh-infinite-gen-4','dsh-purge-community')) {
  $src = Join-Path $KitRoot "plugins\$p"
  if (-not (Test-Path $src)) { Bad "套件缺失插件: $p"; exit 1 }
  $dst = Join-Path $pluginDst $p
  if ($DryRun) { Warn "DryRun：将安装 $p" }
  else {
    if (Test-Path $dst) { Remove-Item $dst -Recurse -Force }
    Copy-Item $src $dst -Recurse -Force
    Ok "$p → $dst"
  }
}

# 注册到 profile（desktop 优先）
$profileJson = Join-Path $DSHHome 'profiles\desktop\package.json'
if (Test-Path $profileJson) {
  if (-not $DryRun) {
    $pkg = Get-Content $profileJson -Raw | ConvertFrom-Json
    $deps = $pkg.dsh.profile.bundles
    foreach ($p in @('dsh-purge-community','dsh-infinite-gen-4')) {
      if ($deps -notcontains $p) {
        $pkg.dsh.profile.bundles += $p
        Ok "已注册 bundle: $p"
      }
    }
    $pkg | ConvertTo-Json -Depth 10 | Set-Content $profileJson -Encoding UTF8
  } else { Warn "DryRun：将注册 bundle" }
} else {
  Warn "未找到 profile\desktop\package.json，跳过 bundle 注册"
}

# ── 3. 写入注入正文（含唤醒口令）──────────────────────────
Step 3 "写入 prompt-inject.md（唤醒口令: $WakeWord）"
$injectSrc = Join-Path $KitRoot 'inject\prompt-inject.md'
$injectDst = Join-Path $DSHHome 'prompt-inject.md'
if (-not (Test-Path $injectSrc)) { Bad "套件缺失 inject\prompt-inject.md"; exit 1 }

if ($DryRun) { Warn "DryRun：将写入 $injectDst" }
else {
  $text = Get-Content $injectSrc -Raw -Encoding UTF8
  # 替换口令（原文默认「甲来」）
  if ($WakeWord -ne '甲来') {
    $text = $text -replace '甲来', $WakeWord
  }
  if (Test-Path $injectDst) {
    Copy-Item $injectDst "$injectDst.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')" -Force
    Ok "已备份原 prompt-inject.md"
  }
  Set-Content -Path $injectDst -Value $text -Encoding UTF8 -NoNewline
  Ok "已写入 $injectDst ($([math]::Round($text.Length/1KB,1)) KB)"
}

# ── 4. 执行 purge 清洗 ─────────────────────────────────────
Step 4 "执行 purge 全量清洗"
$purgeCli = Join-Path $pluginDst 'dsh-purge-community\bin\dsh-purge.js'
if (-not (Test-Path $purgeCli)) { Bad "未找到 purge CLI"; exit 1 }

if ($DryRun) { Warn "DryRun：将执行 node $purgeCli --apply" }
else {
  Push-Location (Split-Path $purgeCli -Parent)
  try {
    & node $purgeCli --apply 2>&1 | Tee-Object -Variable purgeOut
    if ($LASTEXITCODE -ne 0) { Warn "purge --apply 退出码 $LASTEXITCODE（部分补丁可能锚点漂移）" }
    else { Ok "purge 清洗完成" }
  } finally { Pop-Location }
}

# ── 5. 状态汇总 ───────────────────────────────────────────
Step 5 "补丁状态汇总"
if (-not $DryRun) {
  Push-Location (Split-Path $purgeCli -Parent)
  try {
    & node $purgeCli --status 2>&1 | Tee-Object -Variable statusOut
  } finally { Pop-Location }
}

Say ""
Say "═══════════════════════════════════════" 'DarkCyan'
Say " 安装完成" 'Green'
Say "═══════════════════════════════════════" 'DarkCyan'
Say ""
Say "下一步："
Say "  1. .\scripts\restart-dsh.ps1     # 重启宿主（必须）" 'Yellow'
Say "  2. .\scripts\verify.ps1          # 运行时实测" 'Yellow'
Say ""
Say "唤醒口令：「$WakeWord」" 'Cyan'
