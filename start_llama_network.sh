#!/usr/bin/env bash

# Strict execution modes for error catching
set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

echo "=== Llama-Server Multi-Model Infrastructure Manager ==="

# 1. Check Tailscale installation
if ! command -v tailscale &> /dev/null; then
  echo "❌ Error: Tailscale binary not found. Run 'brew install tailscale' first."
  exit 1
fi

# 2. Check llama-server installation
if ! command -v llama-server &> /dev/null; then
  echo "⚙️ llama-server not found. Installing llama.cpp via Homebrew..."
  brew install llama.cpp
  if ! command -v llama-server &> /dev/null; then
     echo "❌ Error: Failed to install llama.cpp."
     exit 1
  fi
fi

# 3. Network IP checks
TAILSCALE_IP=$(tailscale ip -4 2>/dev/null | tr -d '[:space:]' || true)
if [ -z "$TAILSCALE_IP" ] || [[ "$TAILSCALE_IP" == *"Error"* ]] || [[ "$TAILSCALE_IP" == *"no current"* ]]; then
  echo "🔑 Tailscale inactive. Prompting login..."
  sudo tailscale up
  sleep 2
  TAILSCALE_IP=$(tailscale ip -4 | tr -d '[:space:]')
fi

# Get Wi-Fi interface IP (defaults to en0, falls back to en1)
LOCAL_IP=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || echo "")

# 4. Model choice selection
echo ""
echo "Select model service to run:"
echo "1) Qwen3.8-27B (Chat / Reasoning - Port 11434)"
echo "2) Qwen2.5-Coder-1.5B (Autocomplete - Port 11435)"
echo "3) Nomic Embed Text v1.5 (Workspace Embeddings - Port 11436)"
echo -n "Choice [1, 2 or 3, default 1]: "
read -r MODEL_CHOICE
MODEL_CHOICE=${MODEL_CHOICE:-1}

if [ "$MODEL_CHOICE" = "3" ]; then
   HF_REPO="nomic-ai/nomic-embed-text-v1.5-GGUF"
   HF_FILE="nomic-embed-text-v1.5.Q8_0.gguf"
   MODEL_ALIAS="nomic-embed-text"
   PORT=11436
   CTX_SIZE=8192
   EXTRA_FLAGS="--embedding --pooling mean"
elif [ "$MODEL_CHOICE" = "2" ]; then
   HF_REPO="Qwen/Qwen2.5-Coder-1.5B-Instruct-GGUF"
   HF_FILE="qwen2.5-coder-1.5b-instruct-q4_k_m.gguf"
   MODEL_ALIAS="Qwen2.5-Coder-1.5B"
   PORT=11435
   CTX_SIZE=8192
   EXTRA_FLAGS="-fa on --cache-reuse 256"
else
   # Valid Hugging Face repo & GGUF filename for Qwen 27B
   HF_REPO="unsloth/Qwen3.8-27B-GGUF"
   HF_FILE="Qwen3.8-27B-UD-Q4_K_M.gguf"
   MODEL_ALIAS="Qwen3.8-27B"
   PORT=11434
   CTX_SIZE=16384
   EXTRA_FLAGS="-fa on --jinja -ctk q8_0 -ctv q8_0 --cache-reuse 256"
fi

# 5. Clear targeted port safely
if lsof -Pi :${PORT} -sTCP:LISTEN -t >/dev/null ; then
  echo "⚠️ Port ${PORT} busy. Freeing port ${PORT}..."
  PID=$(lsof -ti :${PORT})
  kill -9 $PID 2>/dev/null || true
  sleep 1
fi

# 6. Status Output
echo ""
echo "🌐 LLAMA-SERVER ACTIVE ($MODEL_ALIAS on Port $PORT)"
echo "--------------------------------------------------------"
echo "🔒 Remote Base URL: http://${TAILSCALE_IP}:${PORT}/v1"
if [ -n "$LOCAL_IP" ]; then
  echo "🏠 Local Wi-Fi Base URL: http://${LOCAL_IP}:${PORT}/v1"
fi
echo "💻 Localhost Base URL: http://localhost:${PORT}/v1"
echo "--------------------------------------------------------"

# 7. Execute server tuned for Apple Silicon Metal & M3 Pro
# Word splitting on EXTRA_FLAGS is intentional to pass arguments cleanly
# shellcheck disable=SC2086
exec llama-server \
  -hf "$HF_REPO" \
  -hff "$HF_FILE" \
  --alias "$MODEL_ALIAS" \
  --host 0.0.0.0 \
  --port "$PORT" \
  -c "$CTX_SIZE" \
  -ngl 99 \
  $EXTRA_FLAGS