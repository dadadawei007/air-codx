# Codex 会话数据结构参考

实测于 macOS 桌面版（cli 0.163.0-alpha.10.2）与 Ubuntu 桌面版（0.164.0-alpha.11.1）。字段随版本演进，仅作常见参考。

## `state_5.sqlite`

### `threads`（会话元数据，核心表）

```
id                  TEXT PK        # 会话 UUID（= rollout 文件名里的 uuid 段）
rollout_path        TEXT NOT NULL  # 指向 ~/.codex/sessions/年/月/日/rollout-*.jsonl
created_at          INTEGER        # epoch 秒
updated_at          INTEGER
source              TEXT           # vscode / cli / exec / desktop
model_provider      TEXT           # custom / openai / ...
cwd                 TEXT           # 会话工作目录（Mac 迁移后要替换路径）
title               TEXT           # 会话标题
sandbox_policy      TEXT           # JSON，如 {"type":"disabled"}
approval_mode       TEXT           # never / on-request / ...
tokens_used         INTEGER
has_user_event      INTEGER
archived            INTEGER        # 0/1，归档标记
archived_at         INTEGER
git_sha / git_branch / git_origin_url
cli_version         TEXT
first_user_message  TEXT
memory_mode         TEXT           # enabled
history_mode        TEXT           # legacy | paginated  ← 关键，见 SKILL 五-1
name                TEXT           # 显示名
is_pinned           INTEGER
project_id          TEXT           # 关联 projects(id)，可为 NULL
originator          TEXT           # "Codex Desktop" 等
recency_at / recency_at_ms
```

### `projects`（工作树项目）

```
id                  TEXT PK        # 桌面端用 UUID（如 01a18b6d-...）；手工插入可用 project-<name> 但 UI 不认，须用 UUID
name                TEXT NOT NULL
metadata            TEXT           # 默认 '{}'
position            INTEGER
created_at_ms / updated_at_ms
```

### `project_roots`

```
project_id  TEXT    # REFERENCES projects(id) ON DELETE CASCADE
position    INTEGER
path        TEXT    # 项目根目录绝对路径
PRIMARY KEY (project_id, position)
```

## `thread_history_1.sqlite`（消息内容索引）

| 表 | 作用 |
|----|------|
| `thread_turns` | 每轮 turn：id、序号、状态、起止时间 |
| `thread_items` | 每条消息：thread_id + turn_id + item_id + 序号 + 时间戳 + 完整 JSON 载荷 |
| `thread_history_projection_state` | 每会话的投影状态（字节数等） |

paginated 模式的会话，桌面端靠它渲染对话；导入后若这里没有对应行，UI 会用 rollout 重建列表（但部分交互，如中途恢复，需史此表一致）。

## `sqlite/codex-dev.db`（本地线程目录，侧栏数据源之一）

关键表 `local_thread_catalog`：
```
host_id / thread_id / display_title / source_created_at / source_updated_at
cwd / source_kind / model_provider / git_branch
observation_sequence / missing_candidate / thread_source / pending_observed_title
project_id / conversation_origin / trial_conversation_type / chatgpt_async_status
```
app-server 启动时会按它重建侧栏；手工迁移时若缺行，可用 UI 动作或重启后由扫描重建，也可靠 INSERT 补齐（observation_sequence 用 max+1 递增）。

## `session_index.jsonl`

每行 `{"id":"...","thread_name":"...","updated_at":"..."}`，是会话标题索引；新版可能被 catalog 取代，但迁移时顺手带上无害。