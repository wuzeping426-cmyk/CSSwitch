#!/usr/bin/env bash
set -euo pipefail

PROVIDER="deepseek"
PROXY_PORT="18991"
SCIENCE_PORT="8000"
ALLOW_PLACEHOLDER="0"
EMAIL="virtual@localhost.invalid"
BASE_URL=""
MODEL=""
RELAY_THINKING=""
MAX_HISTORY="48"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --provider) PROVIDER="$2"; shift 2 ;;
    --proxy-port) PROXY_PORT="$2"; shift 2 ;;
    --science-port|--port) SCIENCE_PORT="$2"; shift 2 ;;
    --base-url) BASE_URL="$2"; shift 2 ;;
    --model) MODEL="$2"; shift 2 ;;
    --relay-thinking) RELAY_THINKING="$2"; shift 2 ;;
    --max-history) MAX_HISTORY="$2"; shift 2 ;;
    --allow-placeholder) ALLOW_PLACEHOLDER="1"; shift ;;
    --email) EMAIL="$2"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

if ! [[ "$MAX_HISTORY" =~ ^[1-9][0-9]*$ ]]; then
  echo "--max-history must be a positive integer." >&2
  exit 2
fi

case "$PROVIDER" in
  deepseek) KEY_ENV="DEEPSEEK_API_KEY" ;;
  qwen) KEY_ENV="DASHSCOPE_API_KEY" ;;
  openai-custom) KEY_ENV="CSSWITCH_OPENAI_KEY" ;;
  relay|glm|xiaomi|siliconflow|kimi|minimax|openrouter|custom) KEY_ENV="CSSWITCH_RELAY_KEY" ;;
  *) echo "Provider must be deepseek, qwen, openai-custom, relay, glm, xiaomi, siliconflow, kimi, minimax, openrouter, or custom." >&2; exit 2 ;;
esac

case "$PROVIDER" in
  glm)
    PROVIDER="relay"
    BASE_URL="${BASE_URL:-https://open.bigmodel.cn/api/anthropic}"
    MODEL="${MODEL:-glm-5.2}"
    RELAY_THINKING="${RELAY_THINKING:-adaptive}"
    ;;
  xiaomi)
    PROVIDER="relay"
    BASE_URL="${BASE_URL:-https://api.xiaomimimo.com/anthropic}"
    MODEL="${MODEL:-mimo-v2.5-pro}"
    RELAY_THINKING="${RELAY_THINKING:-adaptive}"
    ;;
  siliconflow)
    PROVIDER="relay"
    BASE_URL="${BASE_URL:-https://api.siliconflow.cn}"
    MODEL="${MODEL:-deepseek-ai/DeepSeek-V4-Flash}"
    RELAY_THINKING="${RELAY_THINKING:-adaptive}"
    ;;
  kimi)
    PROVIDER="relay"
    BASE_URL="${BASE_URL:-https://api.moonshot.cn/anthropic}"
    MODEL="${MODEL:-kimi-k2.7-code}"
    RELAY_THINKING="${RELAY_THINKING:-enabled}"
    ;;
  minimax)
    PROVIDER="relay"
    BASE_URL="${BASE_URL:-https://api.minimaxi.com/anthropic}"
    MODEL="${MODEL:-MiniMax-M3}"
    RELAY_THINKING="${RELAY_THINKING:-adaptive}"
    ;;
  openrouter)
    PROVIDER="relay"
    BASE_URL="${BASE_URL:-https://openrouter.ai/api}"
    MODEL="${MODEL:-anthropic/claude-sonnet-5}"
    RELAY_THINKING="${RELAY_THINKING:-adaptive}"
    ;;
  custom)
    PROVIDER="relay"
    RELAY_THINKING="${RELAY_THINKING:-adaptive}"
    ;;
esac

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -n "${CS_BIN:-}" ]]; then
  :
elif [[ -x "$REPO/linux-x64" ]]; then
  CS_BIN="$REPO/linux-x64"
else
  ROOT="$(cd "$REPO/.." && pwd)"
  CS_BIN="$ROOT/linux-x64"
fi
ENV_FILE="$REPO/.env"
# Keep this short: Claude Science creates Unix sockets below data-dir, and
# Linux has a 108-byte sun_path limit.
STATE_DIR="$HOME/cs/.sandbox"
SANDBOX_HOME="$STATE_DIR/h"
DATA_DIR="$SANDBOX_HOME/.claude-science"
LOG_DIR="$HOME/.csswitch/logs"
RUN_DIR="$HOME/.csswitch/run"
AUTH_TOKEN_FILE="$RUN_DIR/auth-token"
PROXY_PID_FILE="$RUN_DIR/proxy.pid"
BASE_URL_FILE="$RUN_DIR/base-url"
PROXY_LOG="$LOG_DIR/proxy.log"
SCIENCE_LOG="$LOG_DIR/science-start.log"

mkdir -p "$LOG_DIR" "$RUN_DIR" "$SANDBOX_HOME"
chmod 700 "$HOME/.csswitch" "$STATE_DIR" "$SANDBOX_HOME" "$RUN_DIR" 2>/dev/null || true

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing dependency: $1" >&2
    echo "Install it in WSL Ubuntu, for example: sudo apt-get install $2" >&2
    exit 3
  }
}

need python3 python3
need node nodejs
need bwrap bubblewrap
need socat socat

if [[ ! -x "$CS_BIN" ]]; then
  echo "Claude Science binary is not executable: $CS_BIN" >&2
  echo "Run: chmod +x '$CS_BIN'" >&2
  exit 3
fi

if [[ ! -f "$ENV_FILE" ]]; then
  cp "$REPO/.env.example" "$ENV_FILE"
  chmod 600 "$ENV_FILE" 2>/dev/null || true
  echo "Created $ENV_FILE. Put your $KEY_ENV in it, then run this script again." >&2
  exit 4
fi

KEY_VALUE="$(awk -F= -v key="$KEY_ENV" '$1 == key {print $2}' "$ENV_FILE" | tail -n 1 | tr -d "\"'" | xargs || true)"
if [[ -z "$KEY_VALUE" || "$KEY_VALUE" == *"your-"* ]]; then
  if [[ "$ALLOW_PLACEHOLDER" != "1" ]]; then
    echo "$ENV_FILE does not contain a real $KEY_ENV." >&2
    echo "Edit it first. Example: $KEY_ENV=sk-..." >&2
    exit 4
  fi
fi

if [[ "$PROVIDER" == "relay" && -z "$BASE_URL" ]]; then
  BASE_URL="$(awk -F= '$1 == "CSSWITCH_RELAY_BASE_URL" {print $2}' "$ENV_FILE" | tail -n 1 | tr -d "\"'" | xargs || true)"
fi
if [[ "$PROVIDER" == "relay" && -z "$MODEL" ]]; then
  MODEL="$(awk -F= '$1 == "CSSWITCH_RELAY_MODEL" {print $2}' "$ENV_FILE" | tail -n 1 | tr -d "\"'" | xargs || true)"
fi
if [[ "$PROVIDER" == "openai-custom" && -z "$BASE_URL" ]]; then
  BASE_URL="$(awk -F= '$1 == "CSSWITCH_OPENAI_BASE_URL" {print $2}' "$ENV_FILE" | tail -n 1 | tr -d "\"'" | xargs || true)"
fi
if [[ "$PROVIDER" == "openai-custom" && -z "$MODEL" ]]; then
  MODEL="$(awk -F= '$1 == "CSSWITCH_OPENAI_MODEL" {print $2}' "$ENV_FILE" | tail -n 1 | tr -d "\"'" | xargs || true)"
fi

if [[ "$PROVIDER" == "relay" && -z "$BASE_URL" ]]; then
  echo "relay/custom Anthropic needs --base-url or CSSWITCH_RELAY_BASE_URL in .env." >&2
  exit 4
fi
if [[ "$PROVIDER" == "relay" && -z "$MODEL" ]]; then
  echo "relay/custom Anthropic needs --model or CSSWITCH_RELAY_MODEL in .env." >&2
  exit 4
fi
if [[ "$PROVIDER" == "openai-custom" && -z "$BASE_URL" ]]; then
  echo "openai-custom needs --base-url or CSSWITCH_OPENAI_BASE_URL in .env." >&2
  exit 4
fi
if [[ "$PROVIDER" == "openai-custom" && -z "$MODEL" ]]; then
  echo "openai-custom needs --model or CSSWITCH_OPENAI_MODEL in .env." >&2
  exit 4
fi

"$REPO/stop-csswitch-science-wsl.sh" --quiet || true

AUTH_TOKEN="$(python3 - <<'PY'
import secrets
print(secrets.token_hex(16))
PY
)"
PROXY_BASE_URL="http://127.0.0.1:${PROXY_PORT}/${AUTH_TOKEN}"
printf '%s\n' "$AUTH_TOKEN" > "$AUTH_TOKEN_FILE"
printf '%s\n' "$PROXY_BASE_URL" > "$BASE_URL_FILE"
chmod 600 "$AUTH_TOKEN_FILE" "$BASE_URL_FILE" 2>/dev/null || true

if ! find "$DATA_DIR/.oauth-tokens" -maxdepth 1 -name '*.enc' -print -quit 2>/dev/null | grep -q . \
  || [[ ! -f "$DATA_DIR/active-org.json" ]]; then
  # Reuse the largest existing organization database when recovering virtual
  # credentials. Generating a new org UUID would hide existing projects.
  RECOVERY_ORG_UUID=""
  RECOVERY_DB_SIZE=0
  for ORG_DIR in "$DATA_DIR"/orgs/*; do
    [[ -d "$ORG_DIR" && -f "$ORG_DIR/operon-cli.db" ]] || continue
    ORG_DB_SIZE="$(stat -c '%s' "$ORG_DIR/operon-cli.db" 2>/dev/null || echo 0)"
    if [[ "$ORG_DB_SIZE" -gt "$RECOVERY_DB_SIZE" ]]; then
      RECOVERY_ORG_UUID="$(basename "$ORG_DIR")"
      RECOVERY_DB_SIZE="$ORG_DB_SIZE"
    fi
  done

  RECOVERY_ARGS=()
  if [[ -n "$RECOVERY_ORG_UUID" ]]; then
    RECOVERY_ARGS+=(--org-uuid "$RECOVERY_ORG_UUID")
  fi
  node "$REPO/scripts/make-virtual-oauth.mjs" \
    --auth-dir "$DATA_DIR" \
    --email "$EMAIL" \
    "${RECOVERY_ARGS[@]}" \
    --force >/dev/null
fi

PROXY_ARGS=(python3 "$REPO/proxy/csswitch_proxy.py"
  --provider "$PROVIDER" \
  --port "$PROXY_PORT" \
  --env-file "$ENV_FILE" \
  --auth-token "$AUTH_TOKEN" \
  --log "$PROXY_LOG")
if [[ "$PROVIDER" == "relay" ]]; then
  PROXY_ARGS+=(--relay-base "$BASE_URL")
fi
if [[ "$PROVIDER" == "openai-custom" ]]; then
  PROXY_ARGS+=(--openai-base "$BASE_URL")
fi

PROXY_ENV=(PYTHONIOENCODING=utf-8 CSSWITCH_MAX_HISTORY_MESSAGES="$MAX_HISTORY")
if [[ "$PROVIDER" == "relay" ]]; then
  PROXY_ENV+=(CSSWITCH_RELAY_BASE_URL="$BASE_URL" CSSWITCH_RELAY_MODEL="$MODEL")
  if [[ -n "$RELAY_THINKING" ]]; then
    PROXY_ENV+=(CSSWITCH_RELAY_THINKING="$RELAY_THINKING")
  fi
fi
if [[ "$PROVIDER" == "openai-custom" ]]; then
  PROXY_ENV+=(CSSWITCH_OPENAI_BASE_URL="$BASE_URL" CSSWITCH_OPENAI_MODEL="$MODEL"
    CSSWITCH_OPENAI_MODELS="gpt-6-astra,gpt-5.5,gpt-5.4,gpt-5.6-luna,gpt-5.6-sol,gpt-5.6-terra,codex-auto-review"
    CSSWITCH_OPENAI_FALLBACK_MODELS="gpt-5.6-terra,gpt-5.5,gpt-5.4")
  fi

env "${PROXY_ENV[@]}" nohup "${PROXY_ARGS[@]}" \
  >"$LOG_DIR/proxy.stdout.log" 2>"$LOG_DIR/proxy.stderr.log" &
echo $! > "$PROXY_PID_FILE"

for _ in $(seq 1 50); do
  if curl -fsS "http://127.0.0.1:${PROXY_PORT}/${AUTH_TOKEN}/health" >/dev/null 2>&1; then
    break
  fi
  sleep 0.1
done
curl -fsS "http://127.0.0.1:${PROXY_PORT}/${AUTH_TOKEN}/health" >/dev/null

PROXY_HOSTPORT="127.0.0.1:${PROXY_PORT}"
NO_PROXY="127.0.0.1,localhost,::1"

HOME="$SANDBOX_HOME" \
ANTHROPIC_BASE_URL="$PROXY_BASE_URL" \
https_proxy="http://${PROXY_HOSTPORT}" HTTPS_PROXY="http://${PROXY_HOSTPORT}" \
no_proxy="$NO_PROXY" NO_PROXY="$NO_PROXY" \
"$CS_BIN" serve \
  --data-dir "$DATA_DIR" \
  --port "$SCIENCE_PORT" \
  --no-browser \
  --no-auto-update \
  --detached \
  >"$SCIENCE_LOG" 2>&1

STATUS="$(HOME="$SANDBOX_HOME" "$CS_BIN" status --data-dir "$DATA_DIR")"
URL="$(HOME="$SANDBOX_HOME" "$CS_BIN" url --data-dir "$DATA_DIR" | sed -n '1p')"

cat <<EOF
CSSwitch proxy: http://127.0.0.1:${PROXY_PORT}/${AUTH_TOKEN}
Claude Science: http://localhost:${SCIENCE_PORT}
Login URL:
$URL

Status:
$STATUS

Logs:
  $PROXY_LOG
  $SCIENCE_LOG
EOF
