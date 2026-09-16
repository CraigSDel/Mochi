#!/bin/zsh

# Ensure local Homebrew binaries are in the PATH
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

echo "=== Llama-Server Multi-Model Infrastructure Manager ==="

# 1. Check if Tailscale CLI tool exists
if ! command -v tailscale &> /dev/null; then
   echo "❌ Error: Tailscale binary not found. Run 'brew install tailscale' first."
   exit 1
fi

# 2. Check if llama.cpp (llama-server) is installed; auto-install if missing via Homebrew
if ! command -v llama-server &> /dev/null; then
   echo "⚙️ llama-server not found. Installing llama.cpp automatically via Homebrew..."
   brew install llama.cpp
   if ! command -v llama-server &> /dev/null; then
      echo "❌ Error: Failed to install llama.cpp automatically."
      exit 1
   fi
fi

# 3. Retrieve Tailscale IP & Local IP
TAILSCALE_IP=$(tailscale ip -4 2>/dev/null | tr -d '[:space:]')
if [ -z "$TAILSCALE_IP" ] || [[ "$TAILSCALE_IP" == *"Error"* ]] || [[ "$TAILSCALE_IP" == *"no current"* ]]; then
   echo "🔑 Tailscale is not logged in or active. Launching login portal..."
   sudo tailscale up
   sleep 2
   TAILSCALE_IP=$(tailscale ip -4 | tr -d '[:space:]')
fi

LOCAL_IP=$(ipconfig getifaddr en0 2>/dev/null)

# 4. Selection Menu for Models & Dynamic Port Assignment
echo ""
echo "Select the model you want to spin up:"
echo "1) Qwen3.8-27B (Heavy reasoning - Port 11434)"
echo "2) Qwen2.5-Coder-1.5B (Lightweight coding - Port 11435)"
echo -n "Enter choice [1 or 2, default 1]: "
read MODEL_CHOICE
MODEL_CHOICE=${MODEL_CHOICE:-1}

if [ "$MODEL_CHOICE" = "2" ]; then
    HF_REPO="Qwen/Qwen2.5-Coder-1.5B-Instruct-GGUF"
    HF_FILE="qwen2.5-coder-1.5b-instruct-q4_k_m.gguf"
    MODEL_NAME="Qwen2.5-Coder-1.5B"
    PORT=11435
else
    HF_REPO="unsloth/Qwen3.8-27B-GGUF"
    HF_FILE="Qwen3.8-27B-UD-Q4_K_M.gguf"
    MODEL_NAME="Qwen3.8-27B"
    PORT=11434
fi

# 5. Conflict Prevention: Check if the target port is occupied and clear it
if lsof -Pi :${PORT} -sTCP:LISTEN -t >/dev/null ; then
   echo "⚠️ Warning: Port ${PORT} is currently in use. Clearing conflicting processes..."
   killall llama-server 2>/dev/null
   brew services stop ollama 2>/dev/null
   killall ollama 2>/dev/null
   sleep 1
fi

# 6. Print Unified Network Dashboard
echo ""
echo "🌐 LLAMA-SERVER ACTIVE ($MODEL_NAME on Port $PORT)"
echo "--------------------------------------------------------"
echo "🔒 SECURE REMOTE API BASE (Use in your OpenAI-compatible IDE config):"
echo "   👉 http://${TAILSCALE_IP}:${PORT}/v1"
echo ""
if [ ! -z "$LOCAL_IP" ]; then
echo "🏠 LOCAL WI-FI API BASE:"
echo "   👉 http://${LOCAL_IP}:${PORT}/v1"
echo ""
fi
echo "💻 LOCALHOST API BASE:"
echo "   👉 http://localhost:${PORT}/v1"
echo "--------------------------------------------------------"
echo "Press Ctrl+C in this window to stop the server safely."
echo ""

# 7. Start high-performance llama-server on the selected port
exec llama-server \
   -hf "$HF_REPO" \
   -hff "$HF_FILE" \
   --host 0.0.0.0 \
   --port $PORT \
   --ctx-size 32768 \
   --n-gpu-layers -1 \
   --parallel 1 \
   --threads 6 \
   --flash-attn on