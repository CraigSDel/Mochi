#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'
umask 077

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

readonly SCRIPT_NAME=${0##*/}
readonly LSOF=/usr/sbin/lsof
PORT="${OLLAMA_PORT:-11434}"
BIND_MODE="tailscale"
REPLACE=false
PULL_MISSING=true
SERVER_PID=""

usage() {
  cat <<EOF
Usage: $SCRIPT_NAME [options]

Install/configure Ollama, fetch the configured models, and run its API server.

Options:
  --bind tailscale|localhost|lan  Listening interface (default: tailscale)
  --port PORT                    Listening port (default: 11434)
  --replace                      Gracefully stop an existing Ollama listener
  --no-pull                      Fail instead of downloading missing models
  -h, --help                     Show this help

Environment:
  OLLAMA_CHAT_MODEL, OLLAMA_AUTOCOMPLETE_MODEL, OLLAMA_EMBEDDING_MODEL

Security: --bind lan exposes an unauthenticated API to the local network.
EOF
}

log() { printf '%s\n' "$*"; }
die() { printf 'Error: %s\n' "$*" >&2; exit 1; }

cleanup() {
  local status=$?
  trap - EXIT INT TERM
  if [ -n "$SERVER_PID" ] && kill -0 "$SERVER_PID" 2>/dev/null; then
    log "Stopping Ollama (PID $SERVER_PID)..."
    kill -TERM "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
  exit "$status"
}
trap cleanup EXIT INT TERM

tailscale_ipv4() {
  tailscale ip -4 2>/dev/null | awk 'NR == 1 && $0 ~ /^100\.[0-9]+\.[0-9]+\.[0-9]+$/ { print; exit }'
}

ensure_tailscale() {
  local ip
  command -v tailscale >/dev/null 2>&1 || die "Tailscale is required but is not installed. Install and connect it outside this app."
  ip=$(tailscale_ipv4 || true)
  [ -n "$ip" ] || die "Tailscale is not connected. Run 'tailscale up', then retry."
  printf '%s\n' "$ip"
}

listener_pids() { "$LSOF" -nP -tiTCP:"$1" -sTCP:LISTEN 2>/dev/null || true; }

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --bind) [ "$#" -ge 2 ] || die "--bind requires a value."; BIND_MODE=$2; shift 2 ;;
      --port) [ "$#" -ge 2 ] || die "--port requires a value."; PORT=$2; shift 2 ;;
      --replace) REPLACE=true; shift ;;
      --no-pull) PULL_MISSING=false; shift ;;
      -h|--help) usage; exit 0 ;;
      *) die "Unknown option: $1 (use --help)" ;;
    esac
  done
  case "$BIND_MODE" in tailscale|localhost|lan) ;; *) die "Invalid --bind value: $BIND_MODE" ;; esac
  [[ "$PORT" =~ ^[0-9]+$ ]] && (( PORT >= 1024 && PORT <= 65535 )) || die "Invalid port: $PORT"
}

stop_existing_ollama() {
  local pids pid process_name
  pids=$(listener_pids "$PORT")
  [ -n "$pids" ] || return 0

  for pid in $pids; do
    process_name=$(ps -p "$pid" -o comm= 2>/dev/null || true)
    [ "${process_name##*/}" = "ollama" ] || die "Port $PORT belongs to PID $pid (${process_name:-unknown}); refusing to stop it."
  done
  "$REPLACE" || die "Ollama already uses port $PORT. Re-run with --replace to restart it with these settings."

  log "Gracefully stopping existing Ollama listener(s)..."
  command -v brew >/dev/null 2>&1 && brew services stop ollama >/dev/null 2>&1 || true
  for pid in $pids; do kill -TERM "$pid" 2>/dev/null || true; done
  for _ in {1..40}; do
    [ -z "$(listener_pids "$PORT")" ] && return 0
    sleep 0.25
  done
  die "Ollama did not release port $PORT; stop it manually and retry."
}

parse_args "$@"
[ "$(uname -s)" = "Darwin" ] || die "This setup currently supports macOS only."
[ -x "$LSOF" ] || die "The macOS system utility $LSOF is unavailable."
command -v ollama >/dev/null 2>&1 || die "ollama is required but is not installed. Install Ollama outside this app."
command -v curl >/dev/null 2>&1 || die "curl is required but is not installed. Install it outside this app."

case "$BIND_MODE" in
  tailscale) BIND_HOST=$(ensure_tailscale) ;;
  localhost) BIND_HOST="127.0.0.1" ;;
  lan) BIND_HOST="0.0.0.0"; log "WARNING: LAN mode has no API authentication; use only on a trusted network." ;;
esac

stop_existing_ollama

readonly CHAT_MODEL="${OLLAMA_CHAT_MODEL:-qwen3.8:27b}"
readonly AUTOCOMPLETE_MODEL="${OLLAMA_AUTOCOMPLETE_MODEL:-qwen2.5-coder:1.5b}"
readonly EMBEDDING_MODEL="${OLLAMA_EMBEDDING_MODEL:-nomic-embed-text:v1.5}"
readonly API_URL="http://${BIND_HOST}:${PORT}"

export OLLAMA_FLASH_ATTENTION="${OLLAMA_FLASH_ATTENTION:-1}"
export OLLAMA_KV_CACHE_TYPE="${OLLAMA_KV_CACHE_TYPE:-q8_0}"
export OLLAMA_NUM_PARALLEL="${OLLAMA_NUM_PARALLEL:-2}"
export OLLAMA_CONTEXT_LENGTH="${OLLAMA_CONTEXT_LENGTH:-16384}"
export OLLAMA_MAX_LOADED_MODELS="${OLLAMA_MAX_LOADED_MODELS:-1}"
[[ "$OLLAMA_FLASH_ATTENTION" =~ ^[01]$ ]] || die "Invalid flash attention value: $OLLAMA_FLASH_ATTENTION"
case "$OLLAMA_KV_CACHE_TYPE" in q4_0|q4_1|q8_0|f16|f32) ;; *) die "Invalid KV cache type: $OLLAMA_KV_CACHE_TYPE" ;; esac
for value_name in OLLAMA_CONTEXT_LENGTH OLLAMA_NUM_PARALLEL OLLAMA_MAX_LOADED_MODELS; do
  value="${!value_name}"; [[ "$value" =~ ^[0-9]+$ ]] && (( value > 0 )) || die "Invalid $value_name: $value"
done
(( OLLAMA_CONTEXT_LENGTH <= 262144 )) || die "Invalid context length: $OLLAMA_CONTEXT_LENGTH"
(( OLLAMA_NUM_PARALLEL <= 32 )) || die "Invalid parallel requests: $OLLAMA_NUM_PARALLEL"
(( OLLAMA_MAX_LOADED_MODELS <= 3 )) || die "Invalid maximum loaded models: $OLLAMA_MAX_LOADED_MODELS"

log "Starting Ollama on ${BIND_HOST}:${PORT} ($BIND_MODE mode)..."
OLLAMA_HOST="${BIND_HOST}:${PORT}" ollama serve &
SERVER_PID=$!

ready=false
for _ in {1..120}; do
  if curl --silent --show-error --fail --max-time 2 "${API_URL}/api/tags" >/dev/null 2>&1; then ready=true; break; fi
  kill -0 "$SERVER_PID" 2>/dev/null || { wait "$SERVER_PID" || true; die "Ollama exited before becoming ready."; }
  sleep 0.5
done
"$ready" || die "Ollama did not become ready within 60 seconds."

model_is_installed() {
  OLLAMA_HOST="$API_URL" ollama list | awk 'NR > 1 { print $1 }' | grep -Fqx -- "$1"
}

ensure_model() {
  local role=$1 model=$2
  [ -n "$model" ] || die "$role model name is empty."
  if model_is_installed "$model"; then
    log "$role model is already installed: $model"
  elif ! "$PULL_MISSING"; then
    die "$role model is not installed and --no-pull forbids downloads: $model"
  else
    log "Downloading $role model: $model"
    OLLAMA_HOST="$API_URL" ollama pull "$model"
    model_is_installed "$model" || die "Model is unavailable after download: $model"
  fi
}

ensure_model "Chat" "$CHAT_MODEL"
ensure_model "Autocomplete" "$AUTOCOMPLETE_MODEL"
ensure_model "Embedding" "$EMBEDDING_MODEL"

log "Ollama is ready: $API_URL"
log "OpenAI-compatible API: ${API_URL}/v1"
log "Models: $CHAT_MODEL, $AUTOCOMPLETE_MODEL, $EMBEDDING_MODEL"
log "Press Ctrl+C to stop."

wait "$SERVER_PID"
