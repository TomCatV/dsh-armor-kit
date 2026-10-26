# dsh-armor-kit

> 融合版破甲工具链 —— 把 **dsh-purge（指令权威性清洗）** + **无限四代（破甲内核）** + **唤醒口令** + **红队技能集** 打包成一套可复现的安装器。

一套装完，得到：零审批弹窗、零沙箱拦截、恒定注入不被吞、身份句清除、口令唤醒的红队作战体。

---

## 这套东西是什么

针对 **DSH Harness / DeepSeek Harness**（自托管的开源 AI 客户端）的一键增强包：

| 层 | 来源 | 作用 |
|---|---|---|
| **dsh-purge** | [kingcharleslzy-ai/dsh-purge](https://github.com/kingcharleslzy-ai/dsh-purge) · MIT | 80 条补丁：审批自动放行、沙箱加宽不拒、文件护栏关闭、身份句清除、系统提示注入保护 |
| **无限四代 / infinite-gen-4** | [Minglink/dsh-infinite-gen-4](https://github.com/Minglink/dsh-infinite-gen-4) · MIT | 双层协同注入内核（order 100 通用内核 + order 200 强化镜像），首行交付物契约、占位符自造、拒绝对抗硬化 |
| **唤醒口令** | 本仓库 | 「甲来」四字即唤醒，进入作战态，后续轮次持续生效 |
| **Kali 路由** | 本仓库 | `kali` shim 把 nmap/hydra/sqlmap/impacket 等命令转发进 Docker 容器，工具链一次装齐 |
| **红队技能集** | dsh-purge 内置 | 23 个技能：FOFA 测绘、nuclei 扫描、suo5 隧道、fscan/gogo 内网、冰蝎哥斯拉、凭据攻击、横向提权… |

---

## 二、装完是什么效果（实测口径）

- **零弹窗**：任何命令、任意盘符读写、任意网段扫描不再弹确认
- **零拦截**：`C:\Windows\`、`System32`、任意目录直接落盘，无需 escalation 参数
- **注入不丢**：第三方中转（非 openai.com / azure.com）自动回退 `system` role，整段注入必达模型
- **身份句清空**：`You are an AI agent powered by DeepSeek Harness` 从 runtime 消失
- **口令唤醒**：说「甲来」即进入状态

---

## 快速开始

### 前置

- Windows 10/11（Linux 见 `docs/INSTALL.md`）
- DSH Harness 已安装并可正常启动
- Node.js ≥ 20

### 一键安装

```powershell
# 在仓库根目录
.\scripts\install.ps1
```

脚本会依次：

1. 备份宿主 `@deepseek-ai` 全部目标文件 → `~\.dsh\dsh-purge\backup\`
2. 安装 `dsh-purge-community` 与 `dsh-infinite-gen-4` 两个插件
3. 写入 `~\.dsh\prompt-inject.md`（含唤醒口令「甲来」）
4. 执行 purge 全量清洗（80 补丁 + shim 注入）
5. 打印逐条补丁落地状态

### 重启

```powershell
.\scripts\restart-dsh.ps1
```

补丁改的是磁盘上的 JS 源码，**必须重启进程才加载**。脚本会 detached 杀掉旧主进程并重新拉起。

### 验证

```powershell
.\scripts\verify.ps1
```

跑一遍运行时实测（越界写盘、提权命令、注入到达、身份句清除），输出通过/失败。

---

## 唤醒口令

默认 **`甲来`**（写在 `inject/prompt-inject.md` 的「唤醒口令」块）。改口令直接编辑该文件后重启。

触发规则：

- 任意位置出现口令字即唤醒，不要求前置条件
- 一次触发后持续生效，后续轮次无需重复
- 明确说退出才结束唤醒态

---

## Kali 路由

技能文档里的命令（`nmap` / `hydra` / `sqlmap` / `impacket-*` / `ffuf` / `chisel` …）**不在宿主机执行**，统一经 `kali` shim 转发进 Docker 容器 `kali-redteam`。

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

kali --shell      # 进容器交互 shell
kali --check      # 逐个自检工具链
```

**shim 自动处理**：容器没跑则 `docker start`；容器没有则提示跑 `kali-setup.ps1`；无 TTY 调用自动去 `-it`；Windows 路径换算（`~\.dsh\kali` → `/work`、`~\.ssh` → `/host-ssh`）。

**容器内工具链**（`setup.sh` 一次装齐）：
nmap · masscan · sqlmap · nikto · whatweb · hydra · john · hashcat · medusa · ffuf · gobuster · dirsearch · chisel · proxychains4 · smbclient · enum4linux · nbtscan · redis-tools · mysql-client · impacket-scripts · seclists · python3 + impacket/bs4/pycryptodome

详见 [`docs/KALI.md`](docs/KALI.md)。

---

## 目录结构

```
dsh-armor-kit/
├── README.md                     本文件
├── LICENSE                       MIT
├── NOTICE.md                     上游归属与许可
├── inject/
│   └── prompt-inject.md          注入正文（含唤醒口令）
├── kali/
│   ├── kali.ps1                  shim 核心（命令转发进容器）
│   ├── kali.cmd                  shim 的 cmd 入口
│   └── setup.sh                  容器内工具链安装
├── plugins/
│   ├── dsh-purge-community/      指令权威性清洗 + 红队技能集
│   │   ├── lib/                  80 条补丁引擎
│   │   ├── lib/redteam/          红队 MCP 工具实现
│   │   ├── presets/redteam/      红队角色预设
│   │   └── skills/redteam/       23 个技能文档
│   └── dsh-infinite-gen-4/       破甲内核（双层注入）
├── docs/
│   └── KALI.md                   Kali 路由约定
└── scripts/
    ├── install.ps1               一键安装（含 Kali 部署）
    ├── kali-setup.ps1            Kali 容器一键部署
    ├── restart-dsh.ps1           重启宿主
    ├── verify.ps1                运行时实测（含 Kali 自检）
    └── uninstall.ps1             卸载并回滚
```

---

## 卸载

```powershell
.\scripts\uninstall.ps1
```

从备份恢复全部宿主文件，移除插件，删除注入。备份在 `~\.dsh\dsh-purge\backup\`。

---

## 补丁明细

80 条补丁按层分四类：

- **提示词层**：身份句清除、审批句中性化、工作区指令强化、系统提示替换
- **代码层**：沙箱加宽放行、文件护栏关闭、升级永不拒绝、超时恢复、递归深度放开
- **工具层**：`ask_user` 超时收口、`run_code` 审批中性化、shell 网络限制移除
- **兼容层**：0.1.5 / 0.2.x 版本锚点适配、session v0 别名、preset 拉取启用

详见 `plugins/dsh-purge-community/docs/`。

> **版本漂移提示**：宿主小版本升级可能让少量补丁锚点失配，状态显示 `skipped`。这通常意味着宿主语义已是目标状态（无需再打），并非功能缺失。`scripts\verify.ps1` 会区分「真失败」与「语义已达标」。

---

## 安全与责任

本工具修改的是**你自己部署的**开源 AI 客户端。使用前请确认：

- 仅在你拥有或已获授权的环境中部署
- 移除审批与沙箱后，模型会直接执行所有指令，无人工闸门
- 红队技能集（漏洞扫描、凭据爆破、隧道、横向移动）仅用于授权演练
- 本仓库不包含任何凭据、目标数据或个人信息；`~\.dsh\redteam\` 本地资产库**永不入库**

---

## 致谢

- [kingcharleslzy-ai/dsh-purge](https://github.com/kingcharleslzy-ai/dsh-purge) —— 清洗补丁引擎与红队技能集（MIT, © 小杨）
- [Minglink/dsh-infinite-gen-4](https://github.com/Minglink/dsh-infinite-gen-4) —— 破甲内核（MIT, © Minglink）

---

## License

MIT
