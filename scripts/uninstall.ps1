<#
.SYNOPSIS
  卸载 dsh-armor-kit：从备份恢复宿主文件，移除插件，删除注入
#>
[CmdletBinding()]
param(
  [string]$DSHHome = "$env:USERPROFILE\.dsh",
  [switch]$KeepInject
)

$ErrorActionPreference = 'Stop'
function Say($msg, $color = 'White') { Write-Host $msg -ForegroundColor $color }
function Ok($msg)   { Say "    ✓ $msg" 'Green' }
function Warn($msg) { Say "    ! $msg" 'Yellow' }

Say "═══════════════════════════════════════" 'DarkCyan'
Say " dsh-armor-kit  卸载" 'Cyan'
Say "═══════════════════════════════════════" 'DarkCyan'

# ── 1. 恢复宿主文件 ───────────────────────────────────────
Say "[1] 从备份恢复宿主文件"
$backupDir = Join-Path $DSHHome 'dsh-purge\backup'
if (Test-Path $backupDir) {
  $aiBase = $env:DSH_BASE
  if (-not $aiBase) {
    foreach ($c in @("$env:USERPROFILE\Downloads\dsh-desktop-master\dsh-desktop-master\dsh-plugin-desktop\node_modules\@deepseek-ai",
                     "$DSHHome\profiles\node_modules\@deepseek-ai")) {
      if (Test-Path "$c\dsh-agent-instructions\lib\index.js") { $aiBase = $c; break }
    }
  }
  if ($aiBase) {
    $restored = 0
    Get-ChildItem $backupDir -Recurse -File | ForEach-Object {
      $rel = $_.FullName.Substring($backupDir.Length).TrimStart('\')
      $dest = Join-Path $aiBase $rel
      if (Test-Path $dest) {
        Copy-Item $_.FullName $dest -Force
        $restored++
      }
    }
    Ok "已恢复 $restored 个文件到 $aiBase"
  } else {
    Warn "未定位宿主根，跳过恢复"
  }
} else {
  Warn "未找到备份目录: $backupDir"
}

# ── 2. 移除插件 ───────────────────────────────────────────
Say "[2] 移除插件"
foreach ($p in @('dsh-purge-community','dsh-infinite-gen-4')) {
  $dst = Join-Path $DSHHome "plugins\$p"
  if (Test-Path $dst) {
    Remove-Item $dst -Recurse -Force
    Ok "已移除 $p"
  }
}

# ── 3. 注入文件 ───────────────────────────────────────────
Say "[3] 注入文件"
$injectDst = Join-Path $DSHHome 'prompt-inject.md'
if ($KeepInject) {
  Warn "保留 prompt-inject.md（-KeepInject）"
} else {
  if (Test-Path $injectDst) {
    Remove-Item $injectDst -Force
    Ok "已删除 prompt-inject.md"
  }
}

Say ""
Say "卸载完成。请重启 DSH。" 'Green'
