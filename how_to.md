Here is the updated **Complete Setup Guide**, fully integrated with our tool capability analysis, network orchestration, and configuration matrix.

---

# Complete Setup Guide: Multi-Port Local LLM Infrastructure

**Target Environment:** macOS (Apple Silicon M3 Pro, 36GB Unified Memory)

**Core Components:** `llama-server` (`llama.cpp`), Homebrew, Tailscale, VS Code, **Cline**, and **Twinny**.

---

## Architectural Division of Labor

Before configuring the tools, it is vital to understand the separation of responsibilities between your models and VS Code extensions:

```
                      [ Apple Silicon M3 Pro Workstation ]
                                       │
         ┌─────────────────────────────┼─────────────────────────────┐
         ▼                             ▼                             ▼
  Port 11434 (Chat)            Port 11435 (FIM)            Port 11436 (Embeddings)
  Qwen3.8-27B-GGUF             Qwen2.5-Coder-1.5B          nomic-embed-text-v1.5
         │                             │                             │
         ▼                             └──────────────┬──────────────┘
  ┌──────────────┐                                    ▼
  │  VS Code     │                             ┌──────────────┐
  │  Cline       │                             │  VS Code     │
  │  (Agentic)   │                             │  Twinny      │
  └──────────────┘                             └──────────────┘

```

* **Cline (Port 11434):** Your **Agentic Task Engine**. Handles file creation, multi-file refactoring, terminal execution, and tool calls using the 27B model.
* **Twinny (Ports 11435 & 11436):** Your **Silent Editor Helper**. Twinny **does not support autonomous tool execution** (it cannot run terminal commands or auto-edit files on disk). Instead, it provides ultra-fast inline ghost-text code completion (FIM) and vectorizes your workspace into RAG embeddings.

---

## Step-by-Step Installation & Setup

1. **1. Install System Dependencies:** Homebrew, llama.cpp, and Tailscale.
Open your macOS Terminal and run:

```bash
# Update Homebrew and install core tools
brew update
brew install llama.cpp tailscale lsof

```

Authenticate Tailscale to ensure your services are accessible securely across your mesh network:

```bash
sudo tailscale up

```


2. **2. Create start_llama_network.sh:** Production Orchestrator Script.
Create the bash manager in your project directory:

```bash
cat << 'EOF' > start_llama_network.sh
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
exec llama-server \
  -hf "$HF_REPO" \
  -hff "$HF_FILE" \
  --alias "$MODEL_ALIAS" \
  --host 0.0.0.0 \
  --port "$PORT" \
  -c "$CTX_SIZE" \
  -ngl 99 \
  $EXTRA_FLAGS
EOF

chmod +x start_llama_network.sh

```


3. **3. Launch Network Servers:** Persistent Terminals.
Open three terminal tabs to keep all services running simultaneously:

* **Tab 1:** Run `./start_llama_network.sh`, choose `1` $\rightarrow$ **Chat Server** (`11434`)
* **Tab 2:** Run `./start_llama_network.sh`, choose `2` $\rightarrow$ **FIM Autocomplete** (`11435`)
* **Tab 3:** Run `./start_llama_network.sh`, choose `3` $\rightarrow$ **Workspace Embeddings** (`11436`)


4. **4. Setup Cline (VS Code):** Agent Execution & Tools.
1. Install **Cline** from VS Code Extensions.
2. Open Cline settings (gear icon) and set:
* **API Provider:** `OpenAI Compatible`
* **Base URL:** `http://localhost:11434/v1`
* **Model ID:** `Qwen3.8-27B`
* **API Key:** `not-needed`




5. **5. Setup Twinny (VS Code):** Ghost Text & Codebase RAG.
1. Install **Twinny** (`ext install rjmacarthy.twinny`).
2. Click the **Twinny Plug Icon** and set up the providers:
* **FIM / Completion:** Hostname: `http://localhost`, Port: `11435`, Path: `/v1/completions`, Model: `Qwen2.5-Coder-1.5B`, Template: `qwen`.
* **Embeddings:** Hostname: `http://localhost`, Port: `11436`, Path: `/v1/embeddings`, Model: `nomic-embed-text`.


3. Click **Embed Workspace** in Twinny to vector index your project.


---

## Key Hardware & Flag Optimizations Summary

| Setting / Flag | Technical Function | Benefit on M3 Pro |
| --- | --- | --- |
| **`-fa on`** | Flash Attention | Cuts memory bandwidth strain during prompt parsing. |
| **`-ctk q8_0 -ctv q8_0`** | 8-bit KV Cache Compression | Halves context RAM usage (~2.5GB vs ~5GB at 16k context). |
| **`-ngl 99`** | Complete GPU Offloading | Pins 100% of layers directly to Apple Unified Memory. |
| **`--embedding --pooling mean`** | Pooling Kernel Activation | Transforms `llama-server` into a vector generation endpoint. |