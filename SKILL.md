---
name: codex-session-migration
description: "Codex/ChatGPT 桌面版会话跨机器迁移（macOS → Linux，含 CLI/桌面版两种目标）。当用户需要把 Codex 会话从一台机器搬到另一台、打包 ~/.codex 下的会话数据、迁移后修复绝对路径（/Users/xxx → /home/xxx）、或让迁移后的会话在目标端正确显示/可恢复时使用。覆盖会话存储结构（sessions/ rollout JSONL + state_5.sqlite + thread_history_1.sqlite + session_index.jsonl + archived_sessions）、WAL checkpoint 收尾、路径替换、桌面版专有 SQLite 的取舍、归档与会话列表修复。本 skill 基于一次真实的 macOS→Ubuntu 桌面版迁移经验整理。"
metadata:
  type: reference
  platforms: ["macos", "linux"]
  app: "Codex Desktop / ChatGPT Desktop"
  key_dirs: ["~/.codex/sessions", "~/.codex/archived_sessions"]
  key_dbs: ["state_5.sqlite", "thread_history_1.sqlite", "sqlite/codex-dev.db"]
---

# Codex 会话跨机器迁移

> 适用场景：把一台机器上的 Codex（含 ChatGPT 桌面版）历史会话搬到另一台机器，
> 重点是 macOS → Linux 这种跨平台、跨架构的迁移。

## 一、会话存在哪里（存储结构）

全部数据在 `~/.codex/` 下（环境变量 `$CODEX_HOME` 可覆盖）。核心：

| 文件/目录 | 作用 |
|-----------|------|
| `sessions/年/月/日/rollout-*.jsonl` | 每个会话的完整事件流（原始记录，按日期分目录） |
| `thread_history_1.sqlite` | 会话消息内容索引：`thread_items` 存每条消息 JSON，`thread_turns` 存每轮 turn |
| `state_5.sqlite` | 会话元数据：`threads` 表（标题、cwd、时间、归档/置顶、所属 project、model、`rollout_path` 指向上面的 jsonl） |
| `session_index.jsonl` | 会话列表索引（id / 标题 / 更新时间） |
| `archived_sessions/` | 归档会话的 rollout 文件 |
| `attachments/` | 会话附件 |

辅助（按需）：`memories_1.sqlite`、`memories_v2_1.sqlite`（记忆）、`goals_1.sqlite`（目标）、`.codex-global-state.json`（全局状态，含 project 注册/无项目线程列表）、`config.toml`。

决定性事实：**`threads.rollout_path` 直接指向 `sessions/` 里的 jsonl**，rollout JSONL 和两个 sqlite 是一体的 —— 会话要能正常打开/恢复，三者必须一起迁移。

## 二、迁移最小集 vs 全量

- **跨端通用最小集**（任何目标都能用）：
  ```
  sessions/
  archived_sessions/
  ```
  只有 rollout 文件。适合「目标端只装了 Codex CLI」的情况（CLI 只读 rollout，不读桌面端 SQLite）。

- **桌面版专属全集**（目标端也是桌面版时）：
  ```
  sessions/  archived_sessions/
  thread_history_1.sqlite (+wal/-shm)
  state_5.sqlite           (+wal/-shm)
  session_index.jsonl
  ```
  桌面版靠这些 SQLite 建会话列表、归档、置顶、项目分组；SQLite 是跨平台二进制，拷过去可直接用。

## 三、关键注意事项（血泪坑）

1. **必须彻底退出 Codex app**（不只是关窗口）：SQLite 是 WAL 模式，最新写入还在 `-wal` 文件里，退出时 app 才 checkpoint 合并；运行中直接拷会丢最近数据。
2. **不要迁移机器绑定的东西**，新机器重新生成/重新登录：
   - `auth.json`（登录凭证，拷过去可能失效）
   - `installation_id`
   - `ipc/`、`process_manager/`、`thread-writer-locks/`、`.tmp/`、`log/`、`browser/` 等运行时目录
3. **`config.toml` 别整体拷**：里面的 MCP 路径、项目绝对路径都是旧机器的，要逐项改成新机器路径，否则 MCP/插件报错。
4. **版本尽量一致**。alpha 版本的数据库 schema 随版本演进，跨大版本可能读不了库。
5. **`cwd` 路径硬编码**：rollout JSONL 和 `state_5.sqlite` 里都写死了 Mac 路径（如 `/Users/dadadawei/GolandProjects/ticket`）。历史消息内容不受影响；影响的是「继续对话时的工作目录」和「侧栏工作树分组」。

## 四、标准迁移步骤

### macOS 侧（源机，先彻底退出 Codex）

```bash
# WAL checkpoint 合并，更干净
sqlite3 ~/.codex/thread_history_1.sqlite "PRAGMA wal_checkpoint(TRUNCATE);"
sqlite3 ~/.codex/state_5.sqlite "PRAGMA wal_checkpoint(TRUNCATE);"

cd ~/.codex
# 目标若是桌面版（推荐带上 SQLite）
tar czf ~/codex-desktop-migrate.tar.gz \
  sessions/ archived_sessions/ \
  thread_history_1.sqlite state_5.sqlite session_index.jsonl
# 目标若是 CLI，只带 rollout
tar czf ~/codex-sessions-linux.tar.gz sessions/ archived_sessions/
```

### Linux 侧（目标机）

```bash
mkdir -p ~/.codex
tar xzf codex-desktop-migrate.tar.gz -C ~/.codex
```

### 修路径（Linux 上执行）

```bash
# 必做：rollout_path 指向目标机 .codex/sessions
sqlite3 ~/.codex/state_5.sqlite \
  "UPDATE threads SET rollout_path = replace(rollout_path, '/Users/<旧用户名>/.codex/sessions/', '$(echo ~)/.codex/sessions/');"

# 可选：threads.cwd 改成本机路径（仅当项目在 home 下同名目录）
sqlite3 ~/.codex/state_5.sqlite \
  "UPDATE threads SET cwd = replace(cwd, '/Users/<旧用户名>/', '$(echo ~)/');"

# 可选：rollout JSONL 里的 cwd（仅在旧会话继续跑命令时需要，且路径一一对应）
# grep -rl '/Users/<旧用户名>' ~/.codex/sessions | xargs sed -i.bak 's#/Users/<旧用户名>#/home/<新用户名>#g'
```

## 五、采集自真实迁移的额外经验

下面的坑在本次实际迁移中都踩过，迁移后如果会话「列表不显示 / 打不开 / 归档错乱」，逐项检查：

1. **会话打不开报 `Failed to resume chat · list_turns is not supported yet`**：
   根因是 `threads.history_mode` 与 rollout 实际格式不一致。新版本 rollout 的 `session_meta.payload.history_mode = "paginated"`，而手工插入 threads 时常默认写成 `legacy`。**把 `threads.history_mode` 对齐成 rollout meta 里标注的值**（`migrate-rollouts --json` 会报告每个线程是 `already_paginated` 还是 `eligible`）。

2. **侧栏工作树（project）是空的**：
   桌面版读的不是 `state_5.sqlite` 的 `projects` 表，而是 **`.codex-global-state.json` 的 `local-projects` 字段**（每条 `{id: uuid, name, rootPaths: [...]}`）加 `project-order` 列表。只往 SQLite 写 `project-xxx` 行 UI 不认。注册方式：
   ```json
   "local-projects": {
     "<uuid>": {"id": "<uuid>", "name": "ticket", "rootPaths": ["/home/xx/GolandProjects/ticket"], "createdAt": <ms>, "updatedAt": <ms>}
   },
   "project-order": ["<uuid>", ...]
   ```
   同时 `state_5.sqlite` 也补对应 uuid 的 `projects`/`project_roots` 行，`threads.project_id` 关联到 app-server 认识的 uuid（映射关系见 global-state 的 `app-server-project-id-by-legacy-project-id-by-host`）。

3. **项目里看不到会话**：
   根因是这些会话被 app 在早期（注册项目前）标进了 **`projectless-thread-ids`**（无项目会话列表）。即使 `threads.project_id` 已关联，UI 仍会按该名单剔除。修复：把已关联项目的会话 id 从 global-state 的 `projectless-thread-ids` 数组移除，并同步清理 `thread-projectless-output-directories`、`thread-workspace-root-hints` 里对应条目。

4. **归档会话又冒出来了**：
   `threads.archived` 与 rollout 文件位置不一致。把 rollout 文件位于 `archived_sessions/` 的会话 `archived` 置 1（补 `archived_at`），双向核对：文件在归档目录 ⟺ `archived=1`。

> 所有写库/改 global-state 的操作，先**完全退出**桌面版（含 app-server：`pkill -f 'resources/codex.*app-server'`）再做，改完再启动，避免应用用自己的内存状态覆盖。

## 六、常用诊断命令

```bash
# 查看会话与 project 关联
sqlite3 ~/.codex/state_5.sqlite "SELECT id, title, cwd, project_id, history_mode, archived FROM threads LIMIT 20;"

# 查看 catalog（桌面端侧栏数据源之一）
sqlite3 ~/.codex/sqlite/codex-dev.db "SELECT COUNT(*) FROM local_thread_catalog;"

# 迁移评估（不执行）
codex migrate-rollouts --json

# 看全局状态里的项目/无项目清单
python3 -c "import json; g=json.load(open('$(echo ~)/.codex/.codex-global-state.json')); print(g.get('local-projects').keys()); print(len(g.get('projectless-thread-ids', [])))"
```

## 七、参考

- [references/data-model.md](references/data-model.md) —— 各 SQLite 表结构与关键字段
- [references/desktop-json-state.md](references/desktop-json-state.md) —— `.codex-global-state.json` 的项目/归档状态模型
- [scripts/migrate.sh](scripts/migrate.sh) —— 一键迁移脚本（源机打包 + 目标机解压修路径）