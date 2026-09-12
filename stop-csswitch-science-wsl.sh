#!/usr/bin/env bash
set -euo pipefail

QUIET="0"
if [[ "${1:-}" == "--quiet" ]]; then
  QUIET="1"
fi

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$REPO/.." && pwd)"
CS_BIN="${CS_BIN:-$ROOT/linux-x64}"
# Must match start-csswitch-science-wsl.sh. Kept short for AF_UNIX paths.
STATE_DIR="$HOME/cs/.sandbox"
SANDBOX_HOME="$STATE_DIR/h"
DATA_DIR="$SANDBOX_HOME/.claude-science"
RUN_DIR="$HOME/.csswitch/run"
PROXY_PID_FILE="$RUN_DIR/proxy.pid"

if [[ -x "$CS_BIN" ]]; then
  HOME="$SANDBOX_HOME" "$CS_BIN" stop --data-dir "$DATA_DIR" >/dev/null 2>&1 || true
fi

for PID in $(pgrep -f "$CS_BIN serve" 2>/dev/null || true); do
  kill "$PID" >/dev/null 2>&1 || true
done
sleep 0.2
for PID in $(pgrep -f "$CS_BIN serve" 2>/dev/null || true); do
  kill -9 "$PID" >/dev/null 2>&1 || true
done
for PID in $(pgrep -f "socat UNIX-LISTEN:.*/\\.claude-science/sbx-bind-src" 2>/dev/null || true); do
  kill "$PID" >/dev/null 2>&1 || true
done
sleep 0.1
for PID in $(pgrep -f "socat UNIX-LISTEN:.*/\\.claude-science/sbx-bind-src" 2>/dev/null || true); do
  kill -9 "$PID" >/dev/null 2>&1 || true
done

if [[ -f "$PROXY_PID_FILE" ]]; then
  PID="$(cat "$PROXY_PID_FILE" 2>/dev/null || true)"
  if [[ -n "$PID" ]] && kill -0 "$PID" >/dev/null 2>&1; then
    kill "$PID" >/dev/null 2>&1 || true
    sleep 0.2
    kill -9 "$PID" >/dev/null 2>&1 || true
  fi
  rm -f "$PROXY_PID_FILE"
fi

if [[ "$QUIET" != "1" ]]; then
  echo "Stopped CSSwitch proxy and Claude Science sandbox instance."
fi
