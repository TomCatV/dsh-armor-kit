# 上游归属与许可 / Upstream Attribution

本仓库是融合封装版，包含两个上游开源项目的完整副本，均以 MIT 许可发布。

---

## 1. dsh-purge / dsh-purge-community

- **来源**: https://github.com/kingcharleslzy-ai/dsh-purge
- **许可**: MIT License
- **版权**: Copyright (c) 2026 小杨
- **位置**: `plugins/dsh-purge-community/`
- **内容**: 80 条宿主清洗补丁引擎（`lib/*.js`）、红队 MCP 工具实现（`lib/redteam/`）、红队角色预设（`presets/redteam/`）、红队技能文档（`skills/redteam/`）
- **改动**: `skills/redteam/*.md` 每份在 frontmatter 之后追加了 3 行「Kali 路由」提示（指向 `docs/KALI.md`），正文未改。MIT 许可允许修改，原 LICENSE 保留。

## 2. dsh-infinite-gen-4（无限四代）

- **来源**: https://github.com/Minglink/dsh-infinite-gen-4
- **许可**: MIT License
- **版权**: Copyright (c) 2026 Minglink
- **位置**: `plugins/dsh-infinite-gen-4/`
- **内容**: 双层协同注入内核、破甲提示词、客户端状态条、profile 元数据工具

---

## 本仓库原创部分

- `kali/kali.ps1`、`kali/kali.cmd` —— Kali 容器路由 shim
- `kali/setup.sh` —— 容器内工具链安装脚本
- `inject/prompt-inject.md` 的唤醒口令块（「甲来」）
- `scripts/*.ps1`（install / kali-setup / restart-dsh / verify / uninstall）
- `docs/KALI.md`、`README.md`、`NOTICE.md`

以上按 MIT 许可发布。

---

## 未包含

- 任何凭据、API key、私钥
- 任何靶标 / 目标 / 资产数据（`~\.dsh\redteam\` 本地资产库永不入库）
- 任何个人信息

所有上游副本保留其原始 LICENSE 文件。
