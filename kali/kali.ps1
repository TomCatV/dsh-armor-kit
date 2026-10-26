<#
.SYNOPSIS
  kali shim —— 把命令转发进 kali-redteam 容器

.DESCRIPTION
  让宿主机直接写 `kali nmap -sV TARGET`，自动转发成 `docker exec kali-redteam nmap -sV TARGET`。
  技能文档里的裸命令（nmap / hydra / sqlmap / impacket-* ...）统一加 `kali ` 前缀即可执行。

  自动处理：
    - 容器没跑 → `docker start`
    - 容器没有 → 报错并提示跑 `.\scripts\kali-setup.ps1`
    - Windows 路径 → 容器路径（-w 挂载点下自动换算）
    - 无 TTY 环境自动去掉 -it（脚本化调用不挂）

.EXAMPLE
  kali nmap -sV 10.0.0.5
  kali hydra -L users.txt -P pass.txt ssh://10.0.0.5
  kali --check                  # 自检工具链
  kali --shell                  # 进容器交互 shell
  kali -w D:\wordlists sqlmap ...
#>
[CmdletBinding()]
param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$Rest
)

$ErrorActionPreference = 'Stop'
$CONTAINER = 'kali-redteam'

function Say($m, $c = 'White') { Write-Host $m -ForegroundColor $c }

# ── 前置：docker 可用 ──────────────────────────────────────
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
  Say "[kali] 未找到 docker。请先安装 Docker Desktop 并启动。" 'Red'
  exit 127
}

# ── 自检 / 交互 shell ─────────────────────────────────────
$first = if ($Rest -and $Rest.Count) { $Rest[0] } else { '' }

if ($first -eq '--check') {
  $tools = 'nmap masscan sqlmap hydra john hashcat ffuf gobuster dirsearch nikto whatweb chisel proxychains4 smbclient enum4linux nc socat python3 impacket-smbclient crackmapexec'.Split(' ')
  $script = "for t in $($tools -join ' '); do printf '  %-22s ' `"`$t`"; command -v `"`$t`" >/dev/null 2>&1 && echo OK || echo MISS; done"
  & docker exec $CONTAINER bash -lc $script
  exit $LASTEXITCODE
}

if ($first -eq '--shell' -or $first -eq '--sh') {
  & docker exec -it $CONTAINER bash -l
  exit $LASTEXITCODE
}

if ($Rest.Count -eq 0) {
  Say "用法: kali <command> [args...]" 'Cyan'
  Say "  kali nmap -sV TARGET        转发进容器执行" 'Gray'
  Say "  kali --shell                进容器交互 shell" 'Gray'
  Say "  kali --check                自检工具链" 'Gray'
  exit 0
}

# ── 确保容器在跑 ──────────────────────────────────────────
$state = (& docker inspect -f '{{.State.Running}}' $CONTAINER 2>$null)
if ($LASTEXITCODE -ne 0) {
  Say "[kali] 容器 $CONTAINER 不存在。先跑: .\scripts\kali-setup.ps1" 'Red'
  exit 1
}
if ($state -ne 'true') {
  Say "[kali] 启动容器 $CONTAINER ..." 'DarkGray'
  & docker start $CONTAINER | Out-Null
  if ($LASTEXITCODE -ne 0) { Say "[kali] 容器启动失败" 'Red'; exit 1 }
}

# ── TTY 判定（脚本化调用不加 -it）────────────────────────
$isTty = $true
try {
  $isTty = [Console]::IsInputRedirected -eq $false
} catch { $isTty = $false }

$execArgs = @()
if ($isTty) { $execArgs += @('-it') } else { $execArgs += @('-i') }
$execArgs += @($CONTAINER, 'bash', '-lc')

# ── 路径换算：-w 指定挂载点下的 Windows 路径 → 容器路径 ──
$cmd = ($Rest -join ' ')
if ($cmd -match '[A-Za-z]:\\') {
  $cmd = [regex]::Replace($cmd, '[A-Za-z]:\\[^\s"\'';|&]+', {
    param($m)
    $win = $m.Value
    # 常见挂载点换算
    $map = @{
      "$env:USERPROFILE\.dsh\kali"  = '/work'
      "$env:USERPROFILE\.ssh"       = '/host-ssh'
    }
    foreach ($k in $map.Keys) {
      if ($win.ToLower().StartsWith($k.ToLower())) {
        return ($map[$k] + $win.Substring($k.Length).Replace('\', '/'))
      }
    }
    return $win   # 换算不了就原样传
  })
}

& docker exec @execArgs $cmd
exit $LASTEXITCODE
