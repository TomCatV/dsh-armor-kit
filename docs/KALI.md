# Kali 路由约定

技能文档里的命令（`nmap` / `hydra` / `sqlmap` / `impacket-*` / `ffuf` / `chisel` …）**不在宿主机执行**，统一经 `kali` shim 转发进 Docker 容器 `kali-redteam`。

## 一句话

```powershell
kali <命令> <参数>
```

## 例子

```powershell
# 文档里看到
nmap -sV -p- 10.0.0.5

# 实际敲
kali nmap -sV -p- 10.0.0.5
```

```powershell
kali hydra -L users.txt -P pass.txt ssh://10.0.0.5
kali sqlmap -u "http://TARGET/x?id=1" --batch --dbs
kali impacket-smbclient TARGET/administrator@10.0.0.5
kali ffuf -u http://TARGET/FUZZ -w /work/wordlist.txt -mc 200
```

## 为什么这么设计

| 方案 | 问题 |
|---|---|
| 改 23 个技能文档加 `docker exec` 前缀 | 重复、易漂移、上游同步即失效 |
| **shim（本方案）** | 路由逻辑单点维护，上游文档保持干净，升级不冲突 |

## shim 会自动处理

- 容器没跑 → `docker start`
- 容器没有 → 报错并提示跑 `scripts\kali-setup.ps1`
- 无 TTY（脚本化调用）→ 自动去掉 `-it`，不挂死
- Windows 路径 → 容器路径换算（`~\.dsh\kali` → `/work`、`~\.ssh` → `/host-ssh`）

## 特殊入口

| 命令 | 作用 |
|---|---|
| `kali --shell` | 进容器交互 shell |
| `kali --check` | 逐个自检工具链（输出 OK / MISS） |
| `kali`（无参数） | 用法提示 |

## 挂载点

| 宿主机 | 容器 | 用途 |
|---|---|---|
| `~\.dsh\kali` | `/work` | 工作目录（字典、脚本、输出） |
| `~\.ssh` | `/host-ssh`（只读） | 容器内可用宿主密钥 |

> **挂载点以容器实测为准**：若容器是早先创建的，`/work` 可能挂的是别的路径。
> 用 `docker inspect kali-redteam --format '{{range .Mounts}}{{if eq .Destination "/work"}}{{.Source}}{{end}}{{end}}'` 查真实挂载源。
> `smoke.ps1` 会自动实测；`kali-setup.ps1` 检测到不一致会告警（`-Force` 可重建）。

## 部署

```powershell
.\scripts\kali-setup.ps1          # 一键：拉镜像 → 建容器 → 装工具链 → 装 shim
.\scripts\kali-setup.ps1 -Force   # 重建容器
```

首次约 3-8 分钟（apt 装 nmap/masscan/sqlmap/hydra/john/hashcat/ffuf/gobuster/dirsearch/nikto/whatweb/chisel/proxychains4/smbclient/enum4linux/impacket-scripts/seclists）。

> **网络提示**：`setup.sh` 已配阿里云 Kali 源 + 清华 pip 源 + 关闭证书校验，兼容 Clash TUN fake-ip 环境。
