#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'
umask 077

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

readonly SCRIPT_NAME=${0##*/}
readonly LSOF=/usr/sbin/lsof
BIND_MODE="tailscale"
MODEL_CHOICE=""
OFFLINE=false

usage() {
  cat <<EOF
Usage: $SCRIPT_NAME [options]

Run one llama.cpp model server. Models are downloaded by llama-server on first use.

Options:
  --model chat|autocomplete|embedding
                                      Select a model without prompting
  --bind tailscale|localhost|lan      Listening interface (default: tailscale)
  --offline                           Use only models already in the llama.cpp cache
  -h, --help                          Show this help

Security: --bind lan exposes an unauthenticated API to the local network.
EOF
}

log() { printf '%s\n' "$*"; }
die() { printf 'Error: %s\n' "$*" >&2; exit 1; }

require_macos() {
  [ "$(uname -s)" = "Darwin" ] || die "This setup currently supports macOS only."
}

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

listener_pids() {
  "$LSOF" -nP -tiTCP:"$1" -sTCP:LISTEN 2>/dev/null || true
}

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --model)
        [ "$#" -ge 2 ] || die "--model requires a value."
        MODEL_CHOICE=$2
        shift 2
        ;;
      --bind)
        [ "$#" -ge 2 ] || die "--bind requires a value."
        BIND_MODE=$2
        shift 2
        ;;
      --offline) OFFLINE=true; shift ;;
      -h|--help) usage; exit 0 ;;
      *) die "Unknown option: $1 (use --help)" ;;
    esac
  done

  case "$BIND_MODE" in tailscale|localhost|lan) ;; *) die "Invalid --bind value: $BIND_MODE" ;; esac
  case "$MODEL_CHOICE" in ""|chat|autocomplete|embedding) ;; *) die "Invalid --model value: $MODEL_CHOICE" ;; esac
}

parse_args "$@"
require_macos
[ -x "$LSOF" ] || die "The macOS system utility $LSOF is unavailable."

if [ -z "$MODEL_CHOICE" ]; then
  [ -t 0 ] || die "No terminal is available; specify --model."
  printf '%s\n' "Select model: 1) chat  2) autocomplete  3) embedding"
  read -r -p "Choice [1]: " selection
  case "${selection:-1}" in
    1) MODEL_CHOICE=chat ;;
    2) MODEL_CHOICE=autocomplete ;;
    3) MODEL_CHOICE=embedding ;;
    *) die "Invalid selection: $selection" ;;
  esac
fi

command -v llama-server >/dev/null 2>&1 || die "llama-server is required but is not installed. Install llama.cpp outside this app."

TAILSCALE_IP=""
case "$BIND_MODE" in
  tailscale)
    TAILSCALE_IP=$(ensure_tailscale)
    BIND_HOST=$TAILSCALE_IP
    ;;
  localhost) BIND_HOST="127.0.0.1" ;;
  lan)
    BIND_HOST="0.0.0.0"
    log "WARNING: LAN mode has no API authentication; use only on a trusted network."
    ;;
esac

EXTRA_FLAGS=()
case "$MODEL_CHOICE" in
  chat)
    RUNTIME_PREFIX="LLAMA_CHAT"
    HF_REPO="${LLAMA_CHAT_REPO:-unsloth/Qwen3.8-27B-GGUF}"
    HF_FILE="${LLAMA_CHAT_FILE:-Qwen3.8-27B-UD-Q4_K_M.gguf}"
    MODEL_ALIAS="${LLAMA_CHAT_ALIAS:-Qwen3.8-27B}"
    PORT="${LLAMA_CHAT_PORT:-11437}"
    CTX_SIZE="${LLAMA_CHAT_CONTEXT:-16384}"
    ;;
  autocomplete)
    RUNTIME_PREFIX="LLAMA_AUTOCOMPLETE"
    HF_REPO="${LLAMA_AUTOCOMPLETE_REPO:-Qwen/Qwen2.5-Coder-1.5B-Instruct-GGUF}"
    HF_FILE="${LLAMA_AUTOCOMPLETE_FILE:-qwen2.5-coder-1.5b-instruct-q4_k_m.gguf}"
    MODEL_ALIAS="${LLAMA_AUTOCOMPLETE_ALIAS:-Qwen2.5-Coder-1.5B}"
    PORT="${LLAMA_AUTOCOMPLETE_PORT:-11435}"
    CTX_SIZE="${LLAMA_AUTOCOMPLETE_CONTEXT:-8192}"
    ;;
  embedding)
    RUNTIME_PREFIX="LLAMA_EMBEDDING"
    HF_REPO="${LLAMA_EMBEDDING_REPO:-nomic-ai/nomic-embed-text-v1.5-GGUF}"
    HF_FILE="${LLAMA_EMBEDDING_FILE:-nomic-embed-text-v1.5.Q8_0.gguf}"
    MODEL_ALIAS="${LLAMA_EMBEDDING_ALIAS:-nomic-embed-text}"
    PORT="${LLAMA_EMBEDDING_PORT:-11436}"
    CTX_SIZE="${LLAMA_EMBEDDING_CONTEXT:-8192}"
    EXTRA_FLAGS=(--embedding --pooling mean)
    ;;
esac

"$OFFLINE" && EXTRA_FLAGS+=(--offline)

[[ "$PORT" =~ ^[0-9]+$ ]] && (( PORT >= 1024 && PORT <= 65535 )) || die "Invalid port: $PORT"
[[ "$CTX_SIZE" =~ ^[0-9]+$ ]] && (( CTX_SIZE > 0 )) || die "Invalid context size: $CTX_SIZE"
env_value() { local name="${RUNTIME_PREFIX}_$1"; printf '%s' "${!name:-}"; }
GPU_LAYERS="$(env_value GPU_LAYERS)"; GPU_LAYERS="${GPU_LAYERS:-99}"
FLASH_ATTENTION="$(env_value FLASH_ATTENTION)"; FLASH_ATTENTION="${FLASH_ATTENTION:-1}"
KV_KEY="$(env_value KV_CACHE_KEY)"; KV_KEY="${KV_KEY:-q8_0}"
KV_VALUE="$(env_value KV_CACHE_VALUE)"; KV_VALUE="${KV_VALUE:-q8_0}"
CACHE_REUSE="$(env_value CACHE_REUSE)"; CACHE_REUSE="${CACHE_REUSE:-256}"
BATCH_SIZE="$(env_value BATCH)"; BATCH_SIZE="${BATCH_SIZE:-512}"
UBATCH_SIZE="$(env_value UBATCH)"; UBATCH_SIZE="${UBATCH_SIZE:-256}"
THREADS="$(env_value THREADS)"; THREADS="${THREADS:-0}"
THREADS_BATCH="$(env_value THREADS_BATCH)"; THREADS_BATCH="${THREADS_BATCH:-0}"
MAX_OUTPUT="$(env_value MAX_OUTPUT_TOKENS)"; MAX_OUTPUT="${MAX_OUTPUT:-1024}"
TEMPERATURE="$(env_value TEMPERATURE)"; TEMPERATURE="${TEMPERATURE:-0.7}"
TOP_K="$(env_value TOP_K)"; TOP_K="${TOP_K:-40}"
TOP_P="$(env_value TOP_P)"; TOP_P="${TOP_P:-0.9}"
REPEAT_PENALTY="$(env_value REPEAT_PENALTY)"; REPEAT_PENALTY="${REPEAT_PENALTY:-1.1}"
OUTPUT_LIMIT="$(env_value AUTOCOMPLETE_OUTPUT_LIMIT)"; OUTPUT_LIMIT="${OUTPUT_LIMIT:-256}"
[[ "$GPU_LAYERS" =~ ^[0-9]+$ ]] && (( GPU_LAYERS <= 999 )) || die "Invalid GPU layers: $GPU_LAYERS"
case "$FLASH_ATTENTION" in 0|1) ;; *) die "Invalid flash attention value: $FLASH_ATTENTION" ;; esac
case "$KV_KEY" in q4_0|q4_1|q8_0|f16|f32) ;; *) die "Invalid KV cache key type: $KV_KEY" ;; esac
case "$KV_VALUE" in q4_0|q4_1|q8_0|f16|f32) ;; *) die "Invalid KV cache value type: $KV_VALUE" ;; esac
for value_name in CACHE_REUSE BATCH_SIZE UBATCH_SIZE THREADS THREADS_BATCH MAX_OUTPUT TOP_K OUTPUT_LIMIT; do
  value="${!value_name}"; [[ "$value" =~ ^[0-9]+$ ]] && (( value >= 0 )) || die "Invalid $value_name: $value"
done
awk -v value="$TEMPERATURE" 'BEGIN { exit !(value >= 0 && value <= 2) }' || die "Invalid temperature: $TEMPERATURE"
awk -v value="$TOP_P" 'BEGIN { exit !(value > 0 && value <= 1) }' || die "Invalid top-p: $TOP_P"
awk -v value="$REPEAT_PENALTY" 'BEGIN { exit !(value >= 0.5 && value <= 2) }' || die "Invalid repeat penalty: $REPEAT_PENALTY"

(( FLASH_ATTENTION == 1 )) && EXTRA_FLAGS+=(-fa on) || EXTRA_FLAGS+=(-fa off)
EXTRA_FLAGS+=(-ctk "$KV_KEY" -ctv "$KV_VALUE" --cache-reuse "$CACHE_REUSE" -b "$BATCH_SIZE" -ub "$UBATCH_SIZE")
(( THREADS > 0 )) && EXTRA_FLAGS+=(-t "$THREADS")
(( THREADS_BATCH > 0 )) && EXTRA_FLAGS+=(-tb "$THREADS_BATCH")
PREDICT_LIMIT="$MAX_OUTPUT"
[[ "$MODEL_CHOICE" = autocomplete ]] && PREDICT_LIMIT="$OUTPUT_LIMIT"
EXTRA_FLAGS+=(--n-predict "$PREDICT_LIMIT" --temp "$TEMPERATURE" --top-k "$TOP_K" --top-p "$TOP_P" --repeat-penalty "$REPEAT_PENALTY")

PIDS=$(listener_pids "$PORT")
if [ -n "$PIDS" ]; then
  die "Port $PORT is already in use by PID(s): $(printf '%s' "$PIDS" | tr '\n' ' '). Stop that service explicitly or choose another port."
fi

BASE_URL="http://${BIND_HOST}:${PORT}"
log "Starting $MODEL_ALIAS"
log "API: ${BASE_URL}/v1"
log "Bind mode: $BIND_MODE"
log "Press Ctrl+C to stop."

exec llama-server \
  -hf "$HF_REPO" \
  -hff "$HF_FILE" \
  --alias "$MODEL_ALIAS" \
  --host "$BIND_HOST" \
  --port "$PORT" \
  -c "$CTX_SIZE" \
  -ngl "${LLAMA_GPU_LAYERS:-99}" \
  "${EXTRA_FLAGS[@]}"
