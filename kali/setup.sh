#!/bin/bash
export DEBIAN_FRONTEND=noninteractive

# 宿主机 Clash TUN 会把域名解析成 198.18.x.x（fake-ip），https 证书校验常失败：
# 改用 http 镜像 + 关闭证书校验
cat > /etc/apt/sources.list <<'EOF'
deb http://mirrors.aliyun.com/kali kali-rolling main contrib non-free non-free-firmware
EOF

cat > /etc/apt/apt.conf.d/99insecure <<'EOF'
Acquire::https::Verify-Peer "false";
Acquire::https::Verify-Host "false";
Acquire::Check-Valid-Until "false";
Acquire::Retries "3";
EOF

echo "== [1] apt update =="
apt-get update -qq -o Acquire::AllowInsecureRepositories=true 2>&1 | tail -5
apt-get update 2>&1 | tail -3

INST="-y --no-install-recommends -o Acquire::AllowInsecureRepositories=true --allow-unauthenticated"

echo "== [2] base =="
apt-get install $INST ca-certificates curl wget git unzip jq vim less procps iproute2 iputils-ping dnsutils whois net-tools tcpdump openssh-client sshpass 2>&1 | tail -3

echo "== [3] scanners =="
apt-get install $INST nmap masscan netcat-openbsd socat proxychains4 ffuf gobuster dirsearch sqlmap nikto whatweb 2>&1 | tail -3

echo "== [4] creds =="
apt-get install $INST hydra john hashcat medusa 2>&1 | tail -3

echo "== [5] smb/ad =="
apt-get install $INST smbclient enum4linux nbtscan redis-tools default-mysql-client 2>&1 | tail -3

echo "== [6] python =="
apt-get install $INST python3 python3-pip python3-venv 2>&1 | tail -3
mkdir -p /etc/pip
printf '[global]\nindex-url = https://pypi.tuna.tsinghua.edu.cn/simple\ntrusted-host = pypi.tuna.tsinghua.edu.cn\n' > /etc/pip.conf
pip3 install --break-system-packages -q impacket requests beautifulsoup4 pycryptodome 2>&1 | tail -3

echo "== [7] impacket scripts =="
apt-get install $INST impacket-scripts 2>&1 | tail -3

echo "== [8] wordlists =="
apt-get install $INST seclists 2>&1 | tail -3

echo "== [9] tunnels =="
apt-get install $INST chisel 2>&1 | tail -2

echo "== summary =="
for t in nmap masscan sqlmap hydra john hashcat ffuf gobuster dirsearch nikto whatweb chisel proxychains4 smbclient enum4linux nc socat python3; do
  printf '  %-20s ' "$t"; command -v "$t" >/dev/null 2>&1 && echo OK || echo MISS
done
echo "== done =="
