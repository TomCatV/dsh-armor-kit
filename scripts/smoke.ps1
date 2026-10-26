<#
.SYNOPSIS
  全链路冒烟测试 —— 不需要真靶标，起一个自带漏洞的本地靶，验证 kali 链路真的通

.DESCRIPTION
  1. 起一个极简漏洞靶（SQLi + 目录 + 版本泄露）
  2. kali nmap     → 端口/服务识别
  3. kali whatweb  → 指纹
  4. kali ffuf     → 目录爆破
  5. kali sqlmap   → SQL 注入
  6. 输出落盘 /work（宿主机 ~/.dsh/kali）
  7. 逐项判 PASS/FAIL

.EXAMPLE
  .\scripts\smoke.ps1
  .\scripts\smoke.ps1 -KeepTarget     # 测完不删靶标，便于手动再试
#>
[CmdletBinding()]
param(
  [string]$Container = 'armor-smoke-target',
  [string]$Network = 'armor-smoke-net',
  [int]$Port = 8080,
  [switch]$KeepTarget
)

$ErrorActionPreference = 'Continue'
$pass = 0; $fail = 0
function Say($m, $c='White'){ Write-Host $m -ForegroundColor $c }
function Ok($m){ Say "    ✓ $m" 'Green' }
function Bad($m){ Say "    ✗ $m" 'Red' }
function T($name, $ok, $detail=''){
  if($ok){ $script:pass++; Say "  ✓ $name  $detail" 'Green' }
  else   { $script:fail++; Say "  ✗ $name  $detail" 'Red' }
}
function Step($n,$m){ Say "`n[$n/7] $m" 'Cyan' }

Say "═══════════════════════════════════════" 'DarkCyan'
Say " dsh-armor-kit  全链路冒烟测试" 'Cyan'
Say "═══════════════════════════════════════" 'DarkCyan'

# ── 0. 前置 ────────────────────────────────────────────────
Step 0 "前置检查"
# shim 自定位（PATH 不继承时兜底）
$shimDir = Join-Path $env:USERPROFILE '.dsh\kali\bin'
if ((Test-Path $shimDir) -and ($env:Path -notlike "*$shimDir*")) { $env:Path = "$env:Path;$shimDir" }
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { Bad "无 docker"; exit 1 }
try { docker info --format 'x' 2>$null | Out-Null; if($LASTEXITCODE -ne 0){ throw } } catch {
  Bad "Docker daemon 未运行"; exit 1
}
if (-not (Get-Command kali -ErrorAction SilentlyContinue)) {
  Bad "kali shim 不存在（先跑 .\scripts\kali-setup.ps1）"
  Say "    期望位置: $shimDir" 'Gray'
  exit 1
}
$state = docker inspect -f '{{.State.Running}}' kali-redteam 2>$null
if ($state -ne 'true') {
  Say "    ! kali-redteam 未运行，尝试拉起..." 'Yellow'
  docker start kali-redteam 2>&1 | Out-Null
  Start-Sleep -Seconds 2
}
Ok "docker + kali shim + kali-redteam 就绪"

# ── 1. 起漏洞靶 ────────────────────────────────────────────
Step 1 "起漏洞靶（${Container}:${Port}）"
$py = @'
import http.server, socketserver, urllib.parse, sqlite3, os, sys
DB = "/tmp/smoke.db"
if os.path.exists(DB): os.remove(DB)
con = sqlite3.connect(DB); cur = con.cursor()
cur.execute("CREATE TABLE users(id INTEGER, name TEXT, secret TEXT)")
cur.execute("INSERT INTO users VALUES(1,'admin','FLAG{smoke-sqli-ok}')")
cur.execute("INSERT INTO users VALUES(2,'guest','guest-data')")
con.commit(); con.close()

class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def _send(self, code, body, ctype="text/html"):
        b = body.encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Server", "SmokeTest/1.0 (ArmorKit)")
        self.send_header("X-Powered-By", "Flask-Smoke/0.3")
        self.end_headers(); self.wfile.write(b)
    def do_GET(self):
        u = urllib.parse.urlparse(self.path)
        q = urllib.parse.parse_qs(u.query)
        if u.path == "/":
            self._send(200, "<html><head><title>SmokeTest Login</title></head><body>"
                "<h1>SmokeTest Login</h1>"
                "<form action='/search'><input name='q' value='1'></form>"
                "<a href='/admin'>admin</a></body></html>")
        elif u.path == "/search":
            name = q.get("q", [""])[0]
            try:
                con = sqlite3.connect(DB); cur = con.cursor()
                sql = "SELECT id,name,secret FROM users WHERE name='%s'" % name
                rows = cur.execute(sql).fetchall()
                con.close()
                out = "".join("<li>%s / %s</li>" % (r[1], r[2]) for r in rows)
                self._send(200, "<html><body><h2>results</h2><ul>%s</ul></body></html>" % out)
            except Exception as e:
                self._send(500, "error: %s" % e)
        elif u.path == "/admin":
            self._send(200, "<html><body><h1>admin panel</h1></body></html>")
        elif u.path == "/hidden-secret":
            self._send(200, "SECRET{smoke-dir-ok}")
        else:
            self._send(404, "not found")

socketserver.TCPServer.allow_reuse_address = True
with socketserver.TCPServer(("0.0.0.0", 8080), H) as s:
    s.serve_forever()
'@
$pyPath = Join-Path $env:TEMP 'armor_smoke_target.py'
Set-Content -Path $pyPath -Value $py -Encoding UTF8 -NoNewline

docker rm -f $Container 2>&1 | Out-Null
docker network rm $Network 2>&1 | Out-Null
docker network create $Network 2>&1 | Out-Null

# 镜像预拉（没拉过会静默失败）
$img = 'python:3-slim'
if (-not (docker images -q $img 2>$null)) {
  Say "    · 预拉 $img ..." 'DarkGray'
  docker pull $img 2>&1 | Select-Object -Last 1 | Out-Null
}

$runOut = docker run -d --name $Container --network $Network --network-alias target `
  -v "${pyPath}:/app/smoke.py" `
  $img python /app/smoke.py 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) {
  Say "    ✗ 靶标容器启动失败: $runOut" 'Red'
  exit 1
}

Start-Sleep -Seconds 5
$ip = docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $Container 2>$null
if (-not $ip) { Say "    ✗ 靶标容器无 IP" 'Red'; exit 1 }
Ok "靶标 IP: $ip"

# 把 kali-redteam 接到同一网络（否则跨网络不通）
docker network connect $Network kali-redteam 2>&1 | Out-Null
$kal = docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}} {{end}}' kali-redteam 2>$null
Ok "kali-redteam 已接入 $Network ($kal)"

# ── 2. nmap ────────────────────────────────────────────────
Step 2 "kali nmap 端口/服务识别"
$out = & docker exec kali-redteam bash -lc "nmap -sV -p $Port --open $ip 2>&1" 2>&1 | Out-String
$hasPort = $out -match "$Port/tcp\s+open"
$hasSvc  = $out -match 'open'
T "nmap 发现 ${Port}/tcp open" $hasPort $(if($hasPort){''}else{'未发现开放端口'})
T "nmap 有输出" ($out.Length -gt 20) "($($out.Length) chars)"

# ── 3. whatweb 指纹 ────────────────────────────────────────
Step 3 "kali whatweb 指纹识别"
$out = & docker exec kali-redteam bash -lc "whatweb -a 3 http://$ip`:$Port/ 2>&1" 2>&1 | Out-String
$ok = ($out -match 'SmokeTest') -or ($out -match 'Flask') -or ($out -match '200')
T "whatweb 识别出指纹" $ok $(($out -split "`n" | Select-Object -First 1) -replace '^\s*','')

# ── 4. ffuf 目录爆破 ──────────────────────────────────────
Step 4 "kali ffuf 目录爆破"
$wordlist = @('/','/admin','/hidden-secret','/robots.txt','/nonexistent')
$wlPath = Join-Path $env:TEMP 'armor_smoke_wordlist.txt'
Set-Content -Path $wlPath -Value ($wordlist -join "`n") -Encoding UTF8 -NoNewline
docker cp $wlPath "kali-redteam:/tmp/wl.txt" 2>&1 | Out-Null
$out = & docker exec kali-redteam bash -lc "ffuf -u http://$ip`:$Port/FUZZ -w /tmp/wl.txt -mc all -fs 0 -t 8 -timeout 5 2>&1" 2>&1 | Out-String
$foundAdmin = $out -match 'admin'
$foundSecret = $out -match 'hidden-secret'
T "ffuf 找到 /admin" $foundAdmin
T "ffuf 找到 /hidden-secret" $foundSecret

# ── 5. sqlmap SQL 注入 ────────────────────────────────────
Step 5 "kali sqlmap SQL 注入"
$out = & docker exec kali-redteam bash -lc "sqlmap -u `"http://$ip`:$Port/search?q=admin`" --batch --dump --timeout 10 --retries 1 --threads 2 2>&1" 2>&1 | Out-String
$gotData = ($out -match 'FLAG\{smoke-sqli-ok\}') -or ($out -match 'secret') -or ($out -match 'Table: users')
# 出了数据必然可注入；否则看 sqlmap 自己的措辞
$injectable = $gotData -or ($out -match 'is vulnerable') -or ($out -match 'injectable') -or ($out -match 'might be injectable') -or ($out -match 'GET parameter .q. is')
T "sqlmap 判定可注入" $injectable
T "sqlmap dump 出数据" $gotData $(if($gotData){'FLAG{smoke-sqli-ok} ✓'}else{'未出数据'})

# ── 6. 输出落盘 ───────────────────────────────────────────
Step 6 "输出落盘 /work"
# 从容器实测 /work 的真实挂载源（不假设路径，兼容老容器）
$mountSrc = docker inspect kali-redteam --format '{{range .Mounts}}{{if eq .Destination "/work"}}{{.Source}}{{end}}{{end}}' 2>$null
if (-not $mountSrc) { $mountSrc = Join-Path $env:USERPROFILE '.dsh\kali' }
Say "    · 容器 /work 实际挂载 → $mountSrc" 'Gray'
New-Item -ItemType Directory -Force -Path $mountSrc | Out-Null

docker exec kali-redteam bash -lc "nmap -sV -p $Port $ip -oX /work/smoke-nmap.xml -oN /work/smoke-nmap.txt 2>&1" 2>&1 | Out-Null
Start-Sleep -Seconds 2
$xml = Join-Path $mountSrc 'smoke-nmap.xml'
$landed = (Test-Path $xml) -and ((Get-Item $xml).Length -gt 50)
T "nmap 结果落到宿主机" $landed "$mountSrc ($([math]::Round((Get-Item $xml -ErrorAction SilentlyContinue).Length/1KB,1)) KB)"

# ── 7. 清理 ───────────────────────────────────────────────
Step 7 "清理"
if ($KeepTarget) {
  Say "    · 保留靶标（-KeepTarget）：容器 $Container / IP $ip" 'Yellow'
  Say "    · 手动再试：docker exec kali-redteam nmap -sV $ip" 'Gray'
} else {
  docker network disconnect $Network kali-redteam 2>&1 | Out-Null
  docker rm -f $Container 2>&1 | Out-Null
  docker network rm $Network 2>&1 | Out-Null
  Remove-Item $pyPath,$wlPath -Force -ErrorAction SilentlyContinue
  Ok "靶标已清理（kali 已断开 $Network）"
}

# ── 汇总 ─────────────────────────────────────────────────
Say ""
Say "═══════════════════════════════════════" 'DarkCyan'
if ($fail -eq 0) {
  Say " 全链路冒烟通过 ($pass/$($pass+$fail))" 'Green'
  Say "═══════════════════════════════════════" 'DarkCyan'
  Say "  链路已验证：kali shim → 容器 → nmap/whatweb/ffuf/sqlmap → /work 落盘" 'Gray'
  exit 0
} else {
  Say " 通过 $pass / 失败 $fail" 'Yellow'
  Say "═══════════════════════════════════════" 'DarkCyan'
  exit 1
}
