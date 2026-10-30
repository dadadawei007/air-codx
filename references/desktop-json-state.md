# 桌面版 JSON 全局状态模型（`.codex-global-state.json`）

这个文件在桌面版里同时管「项目（工作树）」和「无项目会话」两套状态，迁移后要让侧栏正确显示，必须读懂它。

## `local-projects`（UI 真正读取的项目注册表）

**关键事实：侧栏工作树的来源是这个，不是 `state_5.sqlite.projects`。**

```json
"local-projects": {
  "aab88e53-2a01-42a6-9143-0ff5ebf1a584": {
    "id": "aab88e53-2a01-42a6-9143-0ff5ebf1a584",
    "name": "ticket",
    "rootPaths": ["/home/xx/GolandProjects/ticket"],
    "createdAt": 1793340548916,
    "updatedAt": 1793340548916
  }
}
```

配套状态：
- `project-order`：数组，侧栏项目排序，必须是 local-projects 的 id 集合。
- `selected-project`：`{"type":"local","projectId":"<uuid>"}` 当前选中项目。
- `unified-sidebar-project-order-v1`：旧版字段，可留空。
- `app-server-project-id-by-legacy-project-id-by-host`：`{"local:$(echo ~)/.codex": {"<ui-uuid>": "<app-server-uuid>"}}` —— UI 与 app-server 的项目 id 映射。UI 用户创建的项目（如 aab88e53）会映射到 app-server 自己在 `state_5.projects` 建的 UUID（如 01a18b6d）。

> 手工注册项目时：`local-projects` 写 UI uuid，`state_5.projects`/`project_roots` 写同一 uuid（或 app-server uuid），`threads.project_id` 关联到 **app-server 认识的 id**（看 `app-server-project-id-by-legacy-...` 映射），否则侧栏显示为空的。

## `projectless-thread-ids`（无项目会话名单）

**关键事实：被列在这里的会话，即使 `threads.project_id` 已关联，UI 也会把它从项目会话里剔除。**

```json
"projectless-thread-ids": ["01a16ee6-...", "01a16ef1-..."]
```

成因：应用在做本地线程扫描时，若当时没有任何已注册项目 / 或 cwd 不在任何 `project_roots` 下，就把该会话标记为 projectless。注册项目后不会自动移除。

修复：把已关联项目的会话 id 从数组里删掉，并同步清理：
- `thread-projectless-output-directories`（`{threadId: "…/outputs"}`）
- `thread-workspace-root-hints`（`{threadId: "…"}`）

## `thread-projectless-output-directories` / `thread-workspace-root-hints`

成对出现，是 projectless 会话的输出目录提示与工作树根提示。会话归到项目后要一并删，否则残留会导致 UI 仍把该项目会话当无项目处理。

## `app-server-projects-migration-by-host`

```
"local:$(echo ~)/.codex": {"version": 1, "projectsMigrated": true, "threadAssignmentsMigrated": false, "pendingThreadAssignmentIds": [...]}
```
`pendingThreadAssignmentIds` 列出的会话等待被分配到项目；迁移后如果还有遗留，app-server 会继续尝试分配。

## 诊断

```bash
python3 - <<'EOF'
import json, sqlite3
g = json.load(open("/home/xx/.codex/.codex-global-state.json"))
print("local-projects:", list(g.get("local-projects", {}).keys()))
print("project-order:", g.get("project-order"))
print("projectless-thread-ids:", len(g.get("projectless-thread-ids", [])))
con = sqlite3.connect("/home/xx/.codex/state_5.sqlite")
print("threads w/ project:", con.execute("SELECT COUNT(*) FROM threads WHERE project_id IS NOT NULL").fetchone()[0])
EOF
```