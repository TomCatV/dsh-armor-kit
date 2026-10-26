<#
.SYNOPSIS
  一键部署 Kali 红队容器（dsh-armor-kit）

.DESCRIPTION
  1. 检测 Docker Desktop 是否就绪
  2. 拉 kali-rolling 镜像
  3. 创建 kali-redteam 容器（挂载 ~/.dsh/kali 为 /work）
  4. 在容器内跑 setup.sh 装全工具链
  5. 把 kali shim 装进 PATH
  6. 自检逐个工具

.EXAMPLE
  .\scripts\kali-setup.ps1
  .\scripts\kali-setup.ps1 -Force      # 重建容器
#>
[CmdletBinding()]
param(
  [string]$Container = 'kali-redteam',
  [string]$Image = 'kalilinux/kali-rolling',
  [string]$WorkDir = "$env:USERPROFILE\.dsh\kali",
  [switch]$Force
)

$ErrorActionPreference = 'Stop'
$KitRoot = Split-Path $PSScriptRoot -Parent

function Say($m, $c = 'White') { Write-Host $m -ForegroundColor $c }
function Ok($m)   { Say "    ✓ $m" 'Green' }
function Warn($m) { Say "    ! $m" 'Yellow' }
function Bad($m)  { Say "    ✗ $m" 'Red' }
function Step($n, $m) { Say "`n[$n/6] $m" 'Cyan' }

Say "═══════════════════════════════════════" 'DarkCyan'
Say " dsh-armor-kit  Kali 容器部署" 'Cyan'
Say "═══════════════════════════════════════" 'DarkCyan'

# ── 1. Docker ──────────────────────────────────────────────
Step 1 "检测 Docker"
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
  Bad "未找到 docker CLI"
  Say "  → 安装 Docker Desktop: https://docs.docker.com/desktop/setup/install/windows/"
  exit 1
}
try {
  & docker info --format '{{.ServerVersion}}' 2>$null | Out-Null
  if ($LASTEXITCODE -ne 0) { throw 'daemon down' }
  Ok ("Docker daemon 就绪")
} catch {
  Bad "Docker daemon 未运行"
  Say "  → 启动 Docker Desktop 后重试（状态栏鲸鱼图标右键 → Start）"
  exit 1
}

# ── 2. 镜像 ───────────────────────────────────────────────
Step 2 "准备镜像 $Image"
$haveImage = & docker images -q $Image 2>$null
if (-not $haveImage) {
  Warn "镜像不存在，拉取中（约 200MB）..."
  & docker pull $Image
  if ($LASTEXITCODE -ne 0) { Bad "镜像拉取失败（检查网络/代理）"; exit 1 }
}
Ok "镜像就绪"

# ── 3. 工作目录 ───────────────────────────────────────────
Step 3 "工作目录 $WorkDir"
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
Ok "已挂载为容器内 /work"

# ── 4. 创建容器 ───────────────────────────────────────────
Step 4 "容器 $Container"
$exists = & docker inspect $Container 2>$null
if ($exists -and $Force) {
  Warn "-Force：删除旧容器重建"
  & docker rm -f $Container | Out-Null
  $exists = $null
}
if (-not $exists) {
  & docker run -d `
    --name $Container `
    --hostname kali `
    --restart unless-stopped `
    -v "${WorkDir}:/work" `
    -v "${env:USERPROFILE}\.ssh:/host-ssh:ro" `
    $Image `
    sleep infinity
  if ($LASTEXITCODE -ne 0) { Bad "容器创建失败"; exit 1 }
  Ok "容器已创建并后台常驻"
} else {
  Ok "容器已存在"
  & docker start $Container | Out-Null
}

# ── 5. 装工具链 ───────────────────────────────────────────
Step 5 "容器内安装工具链（setup.sh，首次约 3-8 分钟）"
$setupSh = Join-Path $KitRoot 'kali\setup.sh'
if (-not (Test-Path $setupSh)) { Bad "套件缺失 kali\setup.sh"; exit 1 }

# 拷进容器再执行（避免 stdin 传输丢字符）
& docker cp $setupSh "${Container}:/tmp/setup.sh" | Out-Null
& docker exec $Container bash /tmp/setup.sh
if ($LASTEXITCODE -ne 0) { Warn "setup.sh 退出码 $LASTEXITCODE（部分包可能装失败，看上面 MISS）" }
else { Ok "工具链安装完成" }

# ── 6. 装 shim 进 PATH ────────────────────────────────────
Step 6 "安装 kali shim 进 PATH"
$binDir = Join-Path $env:USERPROFILE '.dsh\kali\bin'
New-Item -ItemType Directory -Force -Path $binDir | Out-Null

Copy-Item (Join-Path $KitRoot 'kali\kali.cmd') $binDir -Force
Copy-Item (Join-Path $KitRoot 'kali\kali.ps1') $binDir -Force
Ok "shim → $binDir"

# 加 PATH（用户级，持久化）
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if ($userPath -notlike "*$binDir*") {
  [Environment]::SetEnvironmentVariable('Path', "$userPath;$binDir", 'User')
  Ok "已加入用户 PATH（新终端生效）"
} else {
  Ok "PATH 已包含"
}
$env:Path = "$env:Path;$binDir"

# ── 自检 ─────────────────────────────────────────────────
Say ""
Say "═══════════════════════════════════════" 'DarkCyan'
Say " 工具链自检" 'Cyan'
Say "═══════════════════════════════════════" 'DarkCyan'
& docker exec $Container bash -lc "for t in nmap masscan sqlmap hydra john hashcat ffuf gobuster dirsearch nikto whatweb chisel proxychains4 smbclient enum4linux nc socat python3 impacket-smbclient; do printf '  %-22s ' `$t; command -v `$t >/dev/null 2>&1 && echo OK || echo MISS; done"

Say ""
Say "═══════════════════════════════════════" 'DarkCyan'
Say " 完成" 'Green'
Say "═══════════════════════════════════════" 'DarkCyan'
Say ""
Say "用法（宿主机直接敲）：" 'Cyan'
Say "  kali nmap -sV TARGET" 'White'
Say "  kali hydra -L users.txt -P pass.txt ssh://TARGET" 'White'
Say "  kali --shell        # 进容器" 'White'
Say "  kali --check        # 自检工具链" 'White'
Say ""
Say "⚠ 新开一个终端才能让 PATH 生效（当前已临时加好）" 'Yellow'
