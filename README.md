# Codex Session Migration

迁移 [Codex / ChatGPT Desktop](https://chatgpt.com)（OpenAI Codex 桌面版）会话到另一台机器的 skill / 知识库，重点覆盖 **macOS → Linux** 跨平台迁移。

> 本内容基于一次真实的 macOS 桌面版 → Ubuntu 桌面版迁移整理而成（源机 cli `0.163.0-alpha.10.2`，目标机 `0.164.0-alpha.11.1`）。

## 这是什么

一份可复用的迁移指南，包含：

- **存储结构**：会话在 `~/.codex/` 下的布局（`sessions/` rollout JSONL、`state_5.sqlite`、`thread_history_1.sqlite`、`session_index.jsonl`、`archived_sessions/`），以及 rollout 与 SQLite 的一体性（`threads.rollout_path` 指向 `sessions/` 下的 jsonl）。
- **迁移步骤**：源机 WAL checkpoint 收尾 → 打包 → 目标机解压 → 修复 `/Users/<user>` 绝对路径。
- **四类必踩的坑**及修复方法：
  1. 会话打不开报 `Failed to resume chat · list_turns is not supported yet` → `threads.history_mode` 与 rollout 的 `paginated/legacy` 对齐；
  2. 侧栏工作树（project）空 → 需注册 `.codex-global-state.json` 的 `local-projects`（而非 SQLite `projects` 表）；
  3. 项目内看不到会话 → 从 `.codex-global-state.json` 的 `projectless-thread-ids` 移除；
  4. 归档会话重新出现 → `threads.archived` 与文件位置对齐。

## 目录

```
.
├── SKILL.md                        # 主文档：迁移步骤 + 坑位修复
├── references/
│   ├── data-model.md               # SQLite 表结构与关键字段
│   └── desktop-json-state.md       # .codex-global-state.json 的项目/无项目状态模型
├── scripts/
│   └── migrate.sh                  # 一键迁移（pack 打包 / unpack 解压+修路径）
└── LICENSE                         # MIT
```

## 快速使用

```bash
# 源机（macOS，先彻底退出 Codex）：
scripts/migrate.sh pack

# 目标机（Linux）：
scripts/migrate.sh unpack codex-sessions.tar.gz --user=<新用户名> [--old-user=dadadawei]
```

如需连同桌面版 SQLite（会话内容索引 / 项目分组）一起迁移，在 `pack` 前设 `DESKTOP=1`。

## 已经有会话在目标机上的修复

如果你像本次案例一样，`sessions/` 已经拷过去了但：
- 点开会话报 `list_turns is not supported yet`
- 工作树侧栏为空
- 项目里看不到已迁移会话
- 归档会话混在正常列表

请直接读 [SKILL.md](SKILL.md) 第五节「采集自真实迁移的额外经验」，里面有每项的具体 SQL / JSON 修复。

## 免责声明

`SQLite 数据库是跨版本演进中的私有格式`，不同 Codex 版本间 `schema` 可能不同。迁移前**备份** `~/.codex`，并尽量保持两端 Codex 版本接近。`auth.json`、`installation_id`、`ipc/` 等机器绑定文件请勿迁移，目标机重新登录。

---

MIT License. See [LICENSE](LICENSE).