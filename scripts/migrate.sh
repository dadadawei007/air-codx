#!/usr/bin/env bash
# Codex 会话一键迁移
# 用法：
#   源机（macOS）：   ./migrate.sh pack
#   目标机（Linux）： ./migrate.sh unpack /path/to/codex-sessions.tar.gz --user=dadadawei
#                     可选 --desktop  ：连同 SQLite 一起迁移（目标也是桌面版时才用）
#                     可选 --no-path  ：跳过 rollout_path/cwd 路径替换
set -euo pipefail

PACKNAME="codex-sessions.tar.gz"
CODX="$HOME/.codex"

# ---------- pack ----------
pack() {
  command -v sqlite3 >/dev/null || { echo "需要 sqlite3"; exit 1; }
  # 用户必须已彻底退出 Codex（桌面版 WAL 需 checkpoint）
  echo ">>> 请确认已完全退出 Codex/ChatGPT 桌面版（含后台 app-server）"
  read -r -p "确认退出后按回车继续... " _

  if [ -f "$CODX/thread_history_1.sqlite" ]; then
    sqlite3 "$CODX/thread_history_1.sqlite" "PRAGMA wal_checkpoint(TRUNCATE);" 2>/dev/null || true
  fi
  if [ -f "$CODX/state_5.sqlite" ]; then
    sqlite3 "$CODX/state_5.sqlite" "PRAGMA wal_checkpoint(TRUNCATE);" 2>/dev/null || true
  fi

  cd "$CODX"
  DESKTOP="${DESKTOP:-0}"
  if [ "$DESKTOP" = "1" ]; then
    tar czf "$HOME/$PACKNAME" sessions/ archived_sessions/ \
      thread_history_1.sqlite state_5.sqlite session_index.jsonl \
      .codex-global-state.json 2>/dev/null
    echo ">>> 已打包(${PACKNAME})：含会话 + 桌面 SQLite + 全局状态"
  else
    tar czf "$HOME/$PACKNAME" sessions/ archived_sessions/
    echo ">>> 已打包(${PACKNAME})：仅会话 rollout（CLI 目标）"
  fi
  du -h "$HOME/$PACKNAME"
}

# ---------- unpack ----------
unpack() {
  TARBALL="$1"; shift || true
  OLD_USER=""
  NEW_USER=""
  DO_PATH=1
  for a in "$@"; do
    case "$a" in
      --user=*) NEW_USER="${a#--user=}";;
      --old-user=*) OLD_USER="${a#--old-user=}";;
      --no-path) DO_PATH=0;;
    esac
  done
  [ -n "$NEW_USER" ] || NEW_USER="$(id -un)"
  [ -n "$OLD_USER" ] || OLD_USER="dadadawei"

  mkdir -p "$CODX"
  tar xzf "$TARBALL" -C "$CODX"
  echo ">>> 解压完成"

  # 修 rollout_path —— 必做，否则桌面版点不开会话
  if [ "$DO_PATH" = "1" ] && [ -f "$CODX/state_5.sqlite" ]; then
    sqlite3 "$CODX/state_5.sqlite" \
      "UPDATE threads SET rollout_path = replace(rollout_path, '/Users/$OLD_USER/.codex/sessions/', '$HOME/.codex/sessions/');"
    # cwd 可选（仅项目在 home 下同名目录时）
    sqlite3 "$CODX/state_5.sqlite" \
      "UPDATE threads SET cwd = replace(cwd, '/Users/$OLD_USER/', '$HOME/');"
    echo ">>> 已替换 rollout_path / cwd：/Users/$OLD_USER -> $HOME"
  fi
  echo ">>> 启动目标端 Codex（桌面版先登录），会话应可见。"
  echo "    若某会话打不开报 list_turns，参见 SKILL 五-1(home mode 对齐)。"
  echo "    若项目侧栏空 / 会话不显示，参见 SKILL 五-2/3(global-state)。"
}

case "${1:-}" in
  pack) pack;;
  unpack) shift; unpack "$@";;
  *)
    echo "用法: $0 pack | unpack <tar> [--user=<新用户名>] [--old-user=<旧用户名>] [--no-path]"
    exit 1
    ;;
esac