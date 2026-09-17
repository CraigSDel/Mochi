#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'
umask 077

export PATH="/opt/homebrew/bin:/usr/local/bin:${PATH:-}"

readonly SCRIPT_NAME=${0##*/}
BIND_MODE="tailscale"
MODEL_CHOICE=""
INSTALL_MISSING=true
TAILSCALE_UP=true
OFFLINE=false

usage() {
  cat <<EOF
Usage: $SCRIPT_NAME [options]

Run one llama.cpp model server. Models are downloaded by llama-server on first use.

Options:
  --model chat|autocomplete|embedding
                                      Select a model without prompting
  --bind tailscale|localhost|lan      Listening interface (default: tailscale)
  --no-install                        Do not install missing Homebrew packages
  --no-tailscale-up                   Do not run 'tailscale up' when disconnected
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

install_formula() {
  local command_name=$1 formula=$2
  command -v "$command_name" >/dev/null 2>&1 && return 0
  "$INSTALL_MISSING" || die "$command_name is required but is not installed."
  command -v brew >/dev/null 2>&1 || die "Homebrew is required to install $formula: https://brew.sh"
  log "Installing $formula with Homebrew..."
  brew install "$formula"
  command -v "$command_name" >/dev/null 2>&1 || die "$formula installed, but $command_name is not on PATH."
}

tailscale_ipv4() {
  tailscale ip -4 2>/dev/null | awk 'NR == 1 && $0 ~ /^100\.[0-9]+\.[0-9]+\.[0-9]+$/ { print; exit }'
}

ensure_tailscale() {
  local ip
  install_formula tailscale tailscale >&2
  ip=$(tailscale_ipv4 || true)
  if [ -z "$ip" ] && "$TAILSCALE_UP"; then
    log "Tailscale is disconnected; starting sign-in..." >&2
    tailscale up || sudo tailscale up
    ip=$(tailscale_ipv4 || true)
  fi
  [ -n "$ip" ] || die "Tailscale is not connected. Run 'tailscale up', then retry."
  printf '%s\n' "$ip"
}

listener_pids() {
  lsof -nP -tiTCP:"$1" -sTCP:LISTEN 2>/dev/null || true
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
      --no-install) INSTALL_MISSING=false; shift ;;
      --no-tailscale-up) TAILSCALE_UP=false; shift ;;
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

install_formula llama-server llama.cpp
install_formula lsof lsof

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
    HF_REPO="${LLAMA_CHAT_REPO:-unsloth/Qwen3.8-27B-GGUF}"
    HF_FILE="${LLAMA_CHAT_FILE:-Qwen3.8-27B-UD-Q4_K_M.gguf}"
    MODEL_ALIAS="${LLAMA_CHAT_ALIAS:-Qwen3.8-27B}"
    PORT="${LLAMA_CHAT_PORT:-11437}"
    CTX_SIZE="${LLAMA_CHAT_CONTEXT:-16384}"
    EXTRA_FLAGS=(-fa on --jinja -ctk q8_0 -ctv q8_0 --cache-reuse 256)
    ;;
  autocomplete)
    HF_REPO="${LLAMA_AUTOCOMPLETE_REPO:-Qwen/Qwen2.5-Coder-1.5B-Instruct-GGUF}"
    HF_FILE="${LLAMA_AUTOCOMPLETE_FILE:-qwen2.5-coder-1.5b-instruct-q4_k_m.gguf}"
    MODEL_ALIAS="${LLAMA_AUTOCOMPLETE_ALIAS:-Qwen2.5-Coder-1.5B}"
    PORT="${LLAMA_AUTOCOMPLETE_PORT:-11435}"
    CTX_SIZE="${LLAMA_AUTOCOMPLETE_CONTEXT:-8192}"
    EXTRA_FLAGS=(-fa on --cache-reuse 256)
    ;;
  embedding)
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
